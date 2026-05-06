#!/bin/bash
set -e

CLICKHOUSE_CLIENT_CMD=("clickhouse-client" "-mn" "--user=${CLICKHOUSE_USERNAME}" "--port=${CLICKHOUSE_PORT}")
if [[ "${CLICKHOUSE_PASSWORD}" ]]; then
  CLICKHOUSE_CLIENT_CMD+=("--password=${CLICKHOUSE_PASSWORD}")
fi

LOGFORMAT="${LOGFORMAT:-"text"}"
CYAN='\033[0;36m'
ORANGE='\033[38;5;208m'
RED='\033[0;31m'
RST='\033[0m'

function log() {
  local level msg highlight emoji output ts
  level="$(tr '[:lower:]' '[:upper:]' <<<"${@:1:1}")"
  msg=("${@:2}")
  case "${level}" in
  FATAL)
    highlight="${RED}"
    emoji="💀 "
    ;;
  ERR*)
    highlight="${RED}"
    emoji="⛔️ "
    ;;
  WARN*)
    highlight="${ORANGE}"
    emoji="⚠️  "
    ;;
  DEBUG)
    if [[ "${VERBOSE}" != "true" ]]; then return; fi
    highlight=""
    emoji="🔎 "
    ;;
  *)
    highlight="${CYAN}"
    emoji=""
    ;;
  esac
  if [[ "${LOGFORMAT}" == "json" ]]; then
    ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    output="$(jq -cn \
      --arg severity "${level}" \
      --arg message "${msg[*]}" \
      --arg ts "${ts}" \
      '{"severity":$severity,"message":$message,"time":$ts}')"
    echo "${output}" 1>&2
  else
    output="${highlight}*** ${emoji}${level}: ${msg[*]}${RST}"
    echo -e "${output}" 1>&2
  fi
  if [[ "${level}" == "FATAL" ]]; then
    if [[ "${-}" =~ 'i' ]]; then return 1; else exit 1; fi
  fi
}

function query() {
  local cmd=("${CLICKHOUSE_CLIENT_CMD[@]}") args=() count=1 rc client_output
  for arg in "$@"; do
    if [[ "$arg" == --* ]]; then
      cmd+=("$arg")
    else
      args+=("$arg")
    fi
  done
  while [[ count -le 4 ]]; do
    if client_output="$("${cmd[@]}" -q "${args[0]}" 2>&1)"; then
      if [[ -n "${client_output}" ]]; then
        echo "${client_output}"
      fi
      return 0
    fi
    rc=$?
    log error "got return code $rc from clickhouse client (attempt $count/4): ${client_output}"
    ((count++))
  done
  return 1
}

if [[ "${LOGFORMAT}" == "json" ]]; then
  if ! command -v jq >/dev/null 2>&1; then
    LOGFORMAT=text
    log warning "jq is not available in this image, falling back to text-mode logging"
  fi
fi

IFS=',' read -ra CLICKHOUSE_SVC_LIST <<<"${CLICKHOUSE_SERVICES}"
BACKUP_DATE="$(date +%Y-%m-%d-%H-%M-%S)"
declare -A BACKUP_NAMES DIFF_FROM

log info "Getting backup status"
for SERVER in "${CLICKHOUSE_SVC_LIST[@]}"; do
  if [[ "${INCREMENTAL_BACKUP}" == "true" ]]; then
    LAST_FULL_BACKUP=$(query --host="${SERVER}" "SELECT name FROM system.backup_list WHERE location='remote' AND name LIKE '%${SERVER}%' AND name LIKE '%full%' AND desc NOT LIKE 'broken%' ORDER BY created DESC LIMIT 1 FORMAT TabSeparatedRaw")
    TODAY_FULL_BACKUP=$(query --host="${SERVER}" "SELECT name FROM system.backup_list WHERE location='remote' AND name LIKE '%${SERVER}%' AND name LIKE '%full%' AND desc NOT LIKE 'broken%' AND toDate(created) = today() ORDER BY created DESC LIMIT 1 FORMAT TabSeparatedRaw")
    PREV_BACKUP_NAME=$(query --host="${SERVER}" "SELECT name FROM system.backup_list WHERE location='remote' AND desc NOT LIKE 'broken%' ORDER BY created DESC LIMIT 1 FORMAT TabSeparatedRaw")
    DIFF_FROM[$SERVER]=""
    if [[ ("$FULL_BACKUP_WEEKDAY" == "$(date +%u)" && "" == "$TODAY_FULL_BACKUP") || -z "$PREV_BACKUP_NAME" || -z "$LAST_FULL_BACKUP" ]]; then
      BACKUP_NAMES[$SERVER]="full-$BACKUP_DATE"
    else
      BACKUP_NAMES[$SERVER]="increment-$BACKUP_DATE"
      DIFF_FROM[$SERVER]="--diff-from-remote=$PREV_BACKUP_NAME"
    fi
  else
    BACKUP_NAMES[$SERVER]="full-$BACKUP_DATE"
  fi
  log info "set backup name on $SERVER = ${BACKUP_NAMES[$SERVER]}"
done

log info "Creating backup actions"
for SERVER in "${CLICKHOUSE_SVC_LIST[@]}"; do
  q="INSERT INTO system.backup_actions(command) VALUES('create ${SERVER}-${BACKUP_NAMES[$SERVER]}')"
  log info "creating backup job: ${q}"
  if ! output="$(query --host="${SERVER}" "${q}")"; then
    log fatal "Could not create backup job: ${output}"
  fi
done

log info "Waiting for backups to complete"
for SERVER in "${CLICKHOUSE_SVC_LIST[@]}"; do
  q="SELECT status,error FROM system.backup_actions WHERE command='create ${SERVER}-${BACKUP_NAMES[$SERVER]}' FORMAT TabSeparatedRaw"
  while IFS=$'\t' read -r status errmsg < <(query --host="${SERVER}" "${q}"); do
    case "${status}" in
    "in progress")
      log info "backup still in progress: ${BACKUP_NAMES[$SERVER]} on $SERVER"
      ;;
    "success")
      log info "backup finished: ${BACKUP_NAMES[$SERVER]} on $SERVER"
      break
      ;;
    *)
      log fatal "backup ${BACKUP_NAMES[$SERVER]} on $SERVER status '${status}': ${errmsg}"
      ;;
    esac
    log info "sleeping 5s before re-checking"
    sleep 5
  done
done

log info "Creating upload actions"
for SERVER in "${CLICKHOUSE_SVC_LIST[@]}"; do
  q="INSERT INTO system.backup_actions(command) VALUES('upload ${DIFF_FROM[$SERVER]} ${SERVER}-${BACKUP_NAMES[$SERVER]}')"
  log info "creating upload job: ${q}"
  if ! output="$(query --host="${SERVER}" "${q}")"; then
    log fatal "Could not create upload job: ${output}"
  fi
done

log info "Waiting for uploads to complete"
for SERVER in "${CLICKHOUSE_SVC_LIST[@]}"; do
  q="SELECT error,status FROM system.backup_actions WHERE command='upload ${DIFF_FROM[$SERVER]} ${SERVER}-${BACKUP_NAMES[$SERVER]}' FORMAT TabSeparatedRaw"
  while IFS=$'\t' read -r status errmsg < <(query --host="${SERVER}" "${q}"); do
    case "${status}" in
    "in progress")
      log info "upload still in progress ${BACKUP_NAMES[$SERVER]} on $SERVER"
      ;;
    "success")
      log info "upload complete ${BACKUP_NAMES[$SERVER]} on $SERVER"
      break
      ;;
    *)
      log fatal "upload ${BACKUP_NAMES[$SERVER]} on $SERVER status '${status}': ${errmsg}"
      ;;
    esac
    log info "sleeping 5s before re-checking"
    sleep 5
  done
done

log info "DONE: BACKUPS CREATED"
