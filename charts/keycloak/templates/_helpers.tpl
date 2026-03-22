{{/*
Common labels for Keycloak resources
*/}}
{{- define "keycloak.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/name: keycloak
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Keycloak ingress hostname — auth.<global.domain>
*/}}
{{- define "keycloak.hostname" -}}
{{- printf "auth.%s" .Values.global.domain -}}
{{- end }}

{{/*
Keycloak internal service URL (used by realm-init job)
*/}}
{{- define "keycloak.serviceUrl" -}}
{{- printf "http://%s-keycloak" .Release.Name -}}
{{- end }}

{{/*
Keycloak admin CLI URL
*/}}
{{- define "keycloak.adminUrl" -}}
{{- printf "http://%s-keycloak/auth" .Release.Name -}}
{{- end }}
