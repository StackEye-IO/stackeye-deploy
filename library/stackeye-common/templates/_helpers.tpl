{{/*
Create the name of the service account to use
*/}}
{{- define "stackeye.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "stackeye.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Return the proper image name
*/}}
{{- define "stackeye.image" -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- printf "%s:%s" .Values.image.repository $tag -}}
{{- end }}

{{/*
Return pod annotations with config checksum
*/}}
{{- define "stackeye.podAnnotations" -}}
{{- with .Values.podAnnotations }}
{{- toYaml . }}
{{- end }}
{{- end }}

{{/*
Define common environment variables for database connection
*/}}
{{- define "stackeye.databaseEnv" -}}
- name: DATABASE_URL
  valueFrom:
    secretKeyRef:
      name: {{ include "stackeye.fullname" . }}-secrets
      key: DATABASE_URL
- name: DATABASE_MAX_OPEN_CONNS
  valueFrom:
    configMapKeyRef:
      name: {{ include "stackeye.fullname" . }}-config
      key: DATABASE_MAX_OPEN_CONNS
- name: DATABASE_MAX_IDLE_CONNS
  valueFrom:
    configMapKeyRef:
      name: {{ include "stackeye.fullname" . }}-config
      key: DATABASE_MAX_IDLE_CONNS
- name: DATABASE_CONN_MAX_LIFETIME
  valueFrom:
    configMapKeyRef:
      name: {{ include "stackeye.fullname" . }}-config
      key: DATABASE_CONN_MAX_LIFETIME
{{- end }}

{{/*
Define common environment variables for logging
*/}}
{{- define "stackeye.loggingEnv" -}}
- name: LOG_LEVEL
  valueFrom:
    configMapKeyRef:
      name: {{ include "stackeye.fullname" . }}-config
      key: LOG_LEVEL
- name: LOG_FORMAT
  valueFrom:
    configMapKeyRef:
      name: {{ include "stackeye.fullname" . }}-config
      key: LOG_FORMAT
{{- end }}
