{{/*
Expand the name of the chart.
*/}}
{{- define "gitlab-sovereign.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "gitlab-sovereign.fullname" -}}
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
{{- define "gitlab-sovereign.labels" -}}
helm.sh/chart: {{ include "gitlab-sovereign.name" . }}-{{ .Chart.Version }}
app.kubernetes.io/name: {{ include "gitlab-sovereign.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
GitLab hostname
*/}}
{{- define "gitlab-sovereign.gitlabHost" -}}
{{- printf "gitlab.%s" .Values.global.domain }}
{{- end }}

{{/*
Registry hostname
*/}}
{{- define "gitlab-sovereign.registryHost" -}}
{{- printf "registry.%s" .Values.global.domain }}
{{- end }}
