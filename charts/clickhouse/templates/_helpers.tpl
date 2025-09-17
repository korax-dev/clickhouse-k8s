{{/*
Expand the name of the chart.
*/}}
{{- define "clickhouse.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "clickhouse.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "clickhouse.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "clickhouse.labels" -}}
helm.sh/chart: {{ include "clickhouse.chart" . }}
{{ include "clickhouse.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "clickhouse.selectorLabels" -}}
app.kubernetes.io/name: {{ include "clickhouse.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Default pod anti-affinity for ClickHouse
*/}}
{{- define "clickhouse.podAntiAffinity" -}}
{{- $shard := .shard -}}
{{- with .context -}}
  {{- if .Values.clickhouse.affinity -}}
    {{- toYaml .Values.clickhouse.affinity -}}
  {{- else -}}
    {{- $antiAffinity := .Values.clickhouse.podAntiAffinity -}}
    {{- if eq $antiAffinity.type "hard" -}}
podAntiAffinity:
  requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchLabels:
          {{- include "clickhouse.selectorLabels" . | nindent 10 }}
          app.kubernetes.io/component: clickhouse
          shard: "{{ $shard }}"
      topologyKey: {{ $antiAffinity.topologyKey | quote }}
    {{- else -}}
podAntiAffinity:
  preferredDuringSchedulingIgnoredDuringExecution:
    - weight: {{ $antiAffinity.weight }}
      podAffinityTerm:
        labelSelector:
          matchLabels:
            {{- include "clickhouse.selectorLabels" . | nindent 12 }}
            app.kubernetes.io/component: clickhouse
            shard: "{{ $shard }}"
        topologyKey: {{ $antiAffinity.topologyKey | quote }}
    {{- end }}
  {{- end }}
{{- end -}}
{{- end -}}

{{/*
ClickHouse ServiceAccount name
*/}}
{{- define "clickhouse.serviceAccountName" -}}
{{- if .Values.clickhouse.serviceAccount.create }}
{{- default (include "clickhouse.fullname" .) .Values.clickhouse.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.clickhouse.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
ClickHouse Auth Secret name
*/}}
{{- define "clickhouse.authSecretName" -}}
{{- if .Values.clickhouse.auth.secretName }}
{{- .Values.clickhouse.auth.secretName }}
{{- else }}
{{- printf "%s-auth" (include "clickhouse.fullname" .) }}
{{- end }}
{{- end }}

{{/*
ClickHouse Interserver Credentials Secret name
*/}}
{{- define "clickhouse.interserverSecretName" -}}
{{- if .Values.clickhouse.interserverCredentials.secretName }}
{{- .Values.clickhouse.interserverCredentials.secretName }}
{{- else }}
{{- printf "%s-interserver-auth" (include "clickhouse.fullname" .) }}
{{- end }}
{{- end }}

{{/*
ClickHouse Init DB Secret name
*/}}
{{- define "clickhouse.initdbSecretName" -}}
{{- if .Values.clickhouse.initdb.existingSecret }}
{{- .Values.clickhouse.initdb.existingSecret }}
{{- else }}
{{- printf "%s-initdb" (include "clickhouse.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Default pod anti-affinity for Keeper
*/}}
{{- define "clickhouse.keeperPodAntiAffinity" -}}
{{- if .Values.keeper.affinity -}}
  {{- toYaml .Values.keeper.affinity -}}
{{- else -}}
  {{- $antiAffinity := .Values.keeper.podAntiAffinity -}}
  {{- if eq $antiAffinity.type "hard" -}}
podAntiAffinity:
  requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchLabels:
          {{- include "clickhouse.selectorLabels" . | nindent 10 }}
          app.kubernetes.io/component: keeper
      topologyKey: {{ $antiAffinity.topologyKey | quote }}
    {{- else -}}
podAntiAffinity:
  preferredDuringSchedulingIgnoredDuringExecution:
    - weight: {{ $antiAffinity.weight }}
      podAffinityTerm:
        labelSelector:
          matchLabels:
            {{- include "clickhouse.selectorLabels" . | nindent 12 }}
            app.kubernetes.io/component: keeper
        topologyKey: {{ $antiAffinity.topologyKey | quote }}
    {{- end }}
  {{- end }}
{{- end -}}

{{/*
ClickHouse Keeper ServiceAccount name
*/}}
{{- define "clickhouse.keeperServiceAccountName" -}}
{{- if .Values.keeper.serviceAccount.create }}
{{- default (printf "%s-keeper" (include "clickhouse.fullname" .)) .Values.keeper.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.keeper.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
ClickHouse Keeper Auth Secret name
*/}}
{{- define "clickhouse.keeperAuthSecretName" -}}
{{- if .Values.keeper.auth.secretName }}
{{- .Values.keeper.auth.secretName }}
{{- else }}
{{- printf "%s-keeper-auth" (include "clickhouse.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Validate keeper auth settings and check for changes
*/}}
{{- define "clickhouse.validateKeeperAuth" -}}
{{- if and .Values.keeper.enabled .Values.keeper.auth.enabled -}}
{{- if .Release.IsUpgrade }}
{{- $oldValues := (lookup "v1" "Secret" .Release.Namespace (include "clickhouse.keeperAuthSecretName" .)) }}
{{- if and $oldValues .Values.keeper.auth.generateSecret }}
{{- if not (hasKey $oldValues.data .Values.keeper.auth.secretKey) }}
{{ fail "Cannot determine previous auth settings. If you need to change keeper auth, you must do it manually." }}
{{- end }}

{{- if .Values.keeper.auth.password }}
{{- $oldAuth := (b64dec (get $oldValues.data .Values.keeper.auth.secretKey)) }}
{{- $newAuth := (printf "%s:%s" .Values.keeper.auth.username .Values.keeper.auth.password) }}

{{- if ne $oldAuth $newAuth }}
{{ fail "Cannot change keeper authentication credentials through Helm. You must reset authentication manually. See documentation for instructions." }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Validate that keeper is enabled if using multiple shards or replicas
*/}}
{{- define "clickhouse.validateKeeperRequirement" -}}
{{- if or (gt (int .Values.clickhouse.shards) 1) (gt (int .Values.clickhouse.replicasPerShard) 1) }}
{{- if not .Values.keeper.enabled }}
{{- fail "ClickHouse Keeper is required when using multiple shards or replicas. Please enable keeper (set keeper.enabled=true) or set both clickhouse.shards=1 and clickhouse.replicasPerShard=1" }}
{{- end }}
{{- end }}
{{- end }}