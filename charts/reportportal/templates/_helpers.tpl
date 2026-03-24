{{/*
Chart name.
*/}}
{{- define "reportportal.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified app name.
*/}}
{{- define "reportportal.fullname" -}}
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
Chart label.
*/}}
{{- define "reportportal.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels.
*/}}
{{- define "reportportal.labels" -}}
helm.sh/chart: {{ include "reportportal.chart" . }}
app.kubernetes.io/name: {{ include "reportportal.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels (base — used with component appended).
*/}}
{{- define "reportportal.selectorLabels" -}}
app.kubernetes.io/name: {{ include "reportportal.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Ingress hostname.
*/}}
{{- define "reportportal.host" -}}
{{- printf "reports.%s" .Values.global.domain }}
{{- end }}

{{/*
Keycloak OIDC issuer URL.
*/}}
{{- define "reportportal.oidcIssuerURL" -}}
{{- printf "%s/realms/%s" .Values.global.keycloak.url .Values.global.keycloak.realm }}
{{- end }}

{{/*
Image reference for a ReportPortal service.
Usage: include "reportportal.serviceImage" (dict "root" . "svc" .Values.images.api)
*/}}
{{- define "reportportal.serviceImage" -}}
{{- $root := .root }}
{{- $svc := .svc }}
{{- if $root.Values.global.imageRegistry }}
{{- printf "%s/%s:%s" $root.Values.global.imageRegistry $svc.name $svc.tag }}
{{- else }}
{{- printf "%s:%s" $svc.repository $svc.tag }}
{{- end }}
{{- end }}

{{/*
Pod anti-affinity spec (shared by all ReportPortal service deployments).
*/}}
{{- define "reportportal.podAntiAffinity" -}}
podAntiAffinity:
  preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchLabels:
            {{- include "reportportal.selectorLabels" . | nindent 12 }}
        topologyKey: kubernetes.io/hostname
{{- end }}
