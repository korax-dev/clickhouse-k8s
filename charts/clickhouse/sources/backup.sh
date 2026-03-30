#!/bin/bash
set -e

CLICKHOUSE_CLIENT_CMD=("clickhouse-client" "-mn" "--user=${CLICKHOUSE_USERNAME}" "--port=${CLICKHOUSE_PORT}")
if [[ "${CLICKHOUSE_PASSWORD}" ]]; then
  CLICKHOUSE_CLIENT_CMD+=("--password=${CLICKHOUSE_PASSWORD}")
fi

function query() {
  local cmd=("${CLICKHOUSE_CLIENT_CMD[@]}") args=() count=1
  for arg in "$@"; do
    if [[ "$arg" == --* ]]; then
      cmd+=("$arg")
    else
      args+=("$arg")
    fi
  done
  while [[ count -le 4 ]]; do
    if "${cmd[@]}" -q "${args[0]}"; then
      return 0
    fi
    echo "*** ERROR: got return code $? from clickhouse client, retrying"
    ((count++))
  done
  return 1
}

IFS=',' read -ra CLICKHOUSE_SVC_LIST <<<"${CLICKHOUSE_SERVICES}"
BACKUP_DATE="$(date +%Y-%m-%d-%H-%M-%S)"
declare -A BACKUP_NAMES DIFF_FROM

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
  echo "*** INFO: set backup name on $SERVER = ${BACKUP_NAMES[$SERVER]}"
done

for SERVER in "${CLICKHOUSE_SVC_LIST[@]}"; do
  echo "*** INFO: create ${BACKUP_NAMES[$SERVER]} on $SERVER"
  query --host="${SERVER}" --echo "INSERT INTO system.backup_actions(command) VALUES('create ${SERVER}-${BACKUP_NAMES[$SERVER]}')"
done

for SERVER in "${CLICKHOUSE_SVC_LIST[@]}"; do
  while [[ "in progress" == $(query --host="${SERVER}" "SELECT status FROM system.backup_actions WHERE command='create ${SERVER}-${BACKUP_NAMES[$SERVER]}' FORMAT TabSeparatedRaw") ]]; do
    echo "*** INFO: still in progress ${BACKUP_NAMES[$SERVER]} on $SERVER"
    sleep 1
  done
  if [[ "success" != $(query --host="${SERVER}" "SELECT status FROM system.backup_actions WHERE command='create ${SERVER}-${BACKUP_NAMES[$SERVER]}' FORMAT TabSeparatedRaw") ]]; then
    echo "*** INFO: error create ${BACKUP_NAMES[$SERVER]} on $SERVER"
    query --host="${SERVER}" --echo "SELECT status,error FROM system.backup_actions WHERE command='create ${SERVER}-${BACKUP_NAMES[$SERVER]}'"
    exit 1
  fi
done

for SERVER in "${CLICKHOUSE_SVC_LIST[@]}"; do
  echo "*** INFO: upload ${DIFF_FROM[$SERVER]} ${BACKUP_NAMES[$SERVER]} on $SERVER"
  query --host="${SERVER}" --echo "INSERT INTO system.backup_actions(command) VALUES('upload ${DIFF_FROM[$SERVER]} ${SERVER}-${BACKUP_NAMES[$SERVER]}')"
done

for SERVER in "${CLICKHOUSE_SVC_LIST[@]}"; do
  while [[ "in progress" == $(query --host="${SERVER}" "SELECT status FROM system.backup_actions WHERE command='upload ${DIFF_FROM[$SERVER]} ${SERVER}-${BACKUP_NAMES[$SERVER]}'") ]]; do
    echo "*** INFO: upload still in progress ${BACKUP_NAMES[$SERVER]} on $SERVER"
    sleep 5
  done
  if [[ "success" != $(query --host="${SERVER}" "SELECT status FROM system.backup_actions WHERE command='upload ${DIFF_FROM[$SERVER]} ${SERVER}-${BACKUP_NAMES[$SERVER]}'") ]]; then
    echo "*** ERROR: error ${BACKUP_NAMES[$SERVER]} on $SERVER"
    query --host="${SERVER}" --echo "SELECT status,error FROM system.backup_actions WHERE command='upload ${DIFF_FROM[$SERVER]} ${SERVER}-${BACKUP_NAMES[$SERVER]}'"
    exit 1
  fi
  if [[ "${DELETE_LOCAL_BACKUPS}" == "true" ]]; then
    query --host="${SERVER}" --echo "INSERT INTO system.backup_actions(command) VALUES('delete local ${SERVER}-${BACKUP_NAMES[$SERVER]}')"
  fi
done

echo "*** INFO: BACKUPS CREATED"
