{{/*
Expand the name of the chart.
*/}}
{{- define "kiali.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "kiali.labels" -}}
helm.sh/chart: {{ include "kiali.name" . }}-{{ .Chart.Version }}
app.kubernetes.io/name: {{ include "kiali.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
