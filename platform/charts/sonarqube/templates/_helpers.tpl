{{/*
Chart name.
*/}}
{{- define "sonarqube-wrapper.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart label.
*/}}
{{- define "sonarqube-wrapper.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels.
*/}}
{{- define "sonarqube-wrapper.labels" -}}
helm.sh/chart: {{ include "sonarqube-wrapper.chart" . }}
app.kubernetes.io/name: sonarqube
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Ingress hostname.
*/}}
{{- define "sonarqube-wrapper.host" -}}
{{- printf "sonar.%s" .Values.global.domain }}
{{- end }}
