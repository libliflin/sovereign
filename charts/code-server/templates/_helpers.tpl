{{/*
Expand the name of the chart.
*/}}
{{- define "code-server.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "code-server.fullname" -}}
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
Create chart label.
*/}}
{{- define "code-server.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels.
*/}}
{{- define "code-server.labels" -}}
helm.sh/chart: {{ include "code-server.chart" . }}
{{ include "code-server.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels.
*/}}
{{- define "code-server.selectorLabels" -}}
app.kubernetes.io/name: {{ include "code-server.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Service account name.
*/}}
{{- define "code-server.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "code-server.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Ingress hostname.
*/}}
{{- define "code-server.host" -}}
{{- printf "code.%s" .Values.global.domain }}
{{- end }}

{{/*
code-server image reference.
Uses imageRegistry when set, falls back to full repository path.
*/}}
{{- define "code-server.image" -}}
{{- if .Values.global.imageRegistry }}
{{- printf "%s/%s:%s" .Values.global.imageRegistry .Values.image.name .Values.image.tag }}
{{- else }}
{{- printf "%s:%s" .Values.image.repository .Values.image.tag }}
{{- end }}
{{- end }}

{{/*
oauth2-proxy image reference.
*/}}
{{- define "code-server.oauth2ProxyImage" -}}
{{- if .Values.global.imageRegistry }}
{{- printf "%s/%s:%s" .Values.global.imageRegistry .Values.oauth2Proxy.image.name .Values.oauth2Proxy.image.tag }}
{{- else }}
{{- printf "%s:%s" .Values.oauth2Proxy.image.repository .Values.oauth2Proxy.image.tag }}
{{- end }}
{{- end }}

{{/*
Keycloak OIDC issuer URL.
*/}}
{{- define "code-server.oidcIssuerURL" -}}
{{- printf "%s/realms/%s" .Values.global.keycloak.url .Values.global.keycloak.realm }}
{{- end }}
