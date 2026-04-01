{{- define "victorialogs-sovereign.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "victorialogs-sovereign.fullname" -}}
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

{{- define "victorialogs-sovereign.labels" -}}
helm.sh/chart: {{ include "victorialogs-sovereign.name" . }}-{{ .Chart.Version }}
app.kubernetes.io/name: {{ include "victorialogs-sovereign.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "victorialogs-sovereign.host" -}}
{{- printf "logs.%s" .Values.global.domain }}
{{- end }}
