{{/*
Expand the name of the chart.
*/}}
{{- define "harbor-sovereign.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "harbor-sovereign.fullname" -}}
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
{{- define "harbor-sovereign.labels" -}}
helm.sh/chart: {{ include "harbor-sovereign.name" . }}-{{ .Chart.Version }}
app.kubernetes.io/name: {{ include "harbor-sovereign.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Harbor hostname
*/}}
{{- define "harbor-sovereign.harborHost" -}}
{{- printf "harbor.%s" .Values.global.domain }}
{{- end }}
