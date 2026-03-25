{{/*
Sovereign Platform — shared HA helpers
Included by wrapper charts via: {{ include "sovereign.pdb" (dict "name" "my-svc" "root" .) }}
These helpers are NOT rendered by the _globals chart itself — they are copied into
charts that need them by declaring _globals as a chart dependency.
*/}}

{{/*
sovereign.pdb — emit a PodDisruptionBudget for a named component.

Usage:
  {{ include "sovereign.pdb" (dict
       "name"      "my-component"
       "namespace" .Release.Namespace
       "selector"  (dict "app.kubernetes.io/name" "my-component")
       "root"      .) }}
*/}}
{{- define "sovereign.pdb" -}}
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ .name }}-pdb
  namespace: {{ .namespace | default .root.Release.Namespace }}
  labels:
    helm.sh/chart: {{ .root.Chart.Name }}-{{ .root.Chart.Version }}
    app.kubernetes.io/managed-by: {{ .root.Release.Service }}
    app.kubernetes.io/instance: {{ .root.Release.Name }}
spec:
  minAvailable: 1
  selector:
    matchLabels:
      {{- range $k, $v := .selector }}
      {{ $k }}: {{ $v | quote }}
      {{- end }}
{{- end }}

{{/*
sovereign.podAntiAffinity — emit a preferredDuringScheduling podAntiAffinity block.
Spreads replicas of a component across nodes.

Usage (inside a pod spec's affinity block):
  affinity:
    {{- include "sovereign.podAntiAffinity" (dict "matchLabels" (dict "app.kubernetes.io/name" "my-svc")) | nindent 4 }}
*/}}
{{- define "sovereign.podAntiAffinity" -}}
podAntiAffinity:
  preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchLabels:
            {{- range $k, $v := .matchLabels }}
            {{ $k }}: {{ $v | quote }}
            {{- end }}
        topologyKey: kubernetes.io/hostname
{{- end }}
