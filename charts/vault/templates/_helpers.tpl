{{/*
Common labels for Vault resources
*/}}
{{- define "vault.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/name: vault
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Vault UI ingress hostname — vault.<global.domain>
*/}}
{{- define "vault.hostname" -}}
{{- printf "vault.%s" .Values.global.domain -}}
{{- end }}

{{/*
Vault internal address (used by jobs)
*/}}
{{- define "vault.address" -}}
{{- printf "http://%s-vault:8200" .Release.Name -}}
{{- end }}
