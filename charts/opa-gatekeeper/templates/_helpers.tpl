{{/*
Common labels
*/}}
{{- define "opa-gatekeeper.labels" -}}
helm.sh/chart: opa-gatekeeper-{{ .Chart.Version }}
app.kubernetes.io/name: opa-gatekeeper
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
