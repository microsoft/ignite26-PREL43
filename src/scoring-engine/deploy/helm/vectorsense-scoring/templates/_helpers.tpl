{{- define "vs.name" -}}vectorsense-scoring{{- end -}}
{{- define "vs.fullname" -}}{{ .Release.Name | trunc 40 | trimSuffix "-" }}{{- end -}}
{{- define "vs.labels" -}}
app.kubernetes.io/part-of: vectorsense-scoring
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Values.image.tag | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
{{- define "vs.image" -}}
{{- $root := index . 0 -}}{{- $repo := index . 1 -}}
{{- if $root.Values.image.registry -}}{{ $root.Values.image.registry }}/{{- end -}}{{ $repo }}:{{ $root.Values.image.tag }}
{{- end -}}
{{- define "vs.secretName" -}}
{{- if .Values.existingSecret -}}{{ .Values.existingSecret }}{{- else -}}{{ include "vs.fullname" . }}-secrets{{- end -}}
{{- end -}}
{{- define "vs.publicBaseUrl" -}}https://{{ .Values.adminHost }}{{- end -}}
{{- define "vs.scorecardBaseUrl" -}}https://{{ .Values.scorecardHost }}{{- end -}}

{{/* Shared pod pieces for api, worker and migration job */}}
{{- define "vs.backendEnv" -}}
envFrom:
  - configMapRef:
      name: {{ include "vs.fullname" . }}-config
  - secretRef:
      name: {{ include "vs.secretName" . }}
{{- end -}}
{{- define "vs.kvVolume" -}}
{{- if and .Values.keyVault.enabled (not .Values.existingSecret) }}
volumes:
  - name: kv-secrets
    csi:
      driver: secrets-store.csi.k8s.io
      readOnly: true
      volumeAttributes:
        secretProviderClass: {{ include "vs.fullname" . }}-kv
{{- end }}
{{- end -}}
{{- define "vs.kvMount" -}}
{{- if and .Values.keyVault.enabled (not .Values.existingSecret) }}
volumeMounts:
  - name: kv-secrets
    mountPath: /mnt/secrets
    readOnly: true
{{- end }}
{{- end -}}
