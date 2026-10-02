{{- define "kt.name" -}}{{ required "tenant is required" .Values.tenant }}{{- end -}}
{{- define "kt.bootstrap" -}}{{ include "kt.name" . }}.{{ required "domain is required (set in your tenant values file)" .Values.domain }}{{- end -}}
{{- define "kt.broker" -}}{{ include "kt.name" .ctx }}-bk{{ .id }}.{{ .ctx.Values.domain }}{{- end -}}
{{- define "kt.labels" -}}
app.kubernetes.io/part-of: kafka-service
kafka-service/tenant: {{ include "kt.name" . }}
kafka-service/environment: {{ .Values.environment }}
{{- end -}}
{{- define "kt.controllerClass" -}}{{ .Values.controllers.storage.class | default .Values.kafka.storage.class }}{{- end -}}
{{- define "kt.dnsAnn" -}}
external-dns.alpha.kubernetes.io/hostname: {{ .host }}
external-dns.alpha.kubernetes.io/ttl: {{ .ctx.Values.network.dnsTtl | quote }}
metallb.io/address-pool: {{ .ctx.Values.network.metallbPool }}
{{- end -}}
