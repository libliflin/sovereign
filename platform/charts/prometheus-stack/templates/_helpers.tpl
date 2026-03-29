{{/*
Expand the name of the chart.
*/}}
{{- define "prometheus-stack.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart label.
*/}}
{{- define "prometheus-stack.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels.
*/}}
{{- define "prometheus-stack.labels" -}}
helm.sh/chart: {{ include "prometheus-stack.chart" . }}
app.kubernetes.io/name: {{ include "prometheus-stack.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Grafana hostname.
*/}}
{{- define "prometheus-stack.grafanaHost" -}}
{{- printf "grafana.%s" .Values.global.domain }}
{{- end }}

{{/*
Keycloak base URL.
*/}}
{{- define "prometheus-stack.keycloakUrl" -}}
{{- printf "%s/realms/%s" .Values.global.keycloak.url .Values.global.keycloak.realm }}
{{- end }}
