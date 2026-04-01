{{/*
Expand the name of the chart.
*/}}
{{- define "forgejo-sovereign.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "forgejo-sovereign.fullname" -}}
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
Common labels
*/}}
{{- define "forgejo-sovereign.labels" -}}
helm.sh/chart: {{ include "forgejo-sovereign.name" . }}-{{ .Chart.Version }}
app.kubernetes.io/name: {{ include "forgejo-sovereign.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Forgejo hostname
*/}}
{{- define "forgejo-sovereign.host" -}}
{{- printf "forgejo.%s" .Values.global.domain }}
{{- end }}
