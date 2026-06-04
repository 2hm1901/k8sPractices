{{/*
=============================================================================
_helpers.tpl — Template helpers/partials for my-webapp chart
These are reusable snippets called with {{ include "my-webapp.xxx" . }}
=============================================================================
*/}}

{{/*
Expand the name of the chart.
Usage: {{ include "my-webapp.name" . }}
*/}}
{{- define "my-webapp.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
If fullnameOverride is set, use it directly.
If nameOverride is set, use release-name + nameOverride.
Otherwise, use release-name + chart-name.
Truncated to 63 chars (K8s label value limit).
Usage: {{ include "my-webapp.fullname" . }}
*/}}
{{- define "my-webapp.fullname" -}}
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
Create chart name and version as used by the chart label.
Usage: {{ include "my-webapp.chart" . }}
*/}}
{{- define "my-webapp.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels — applied to ALL resources created by this chart.
Include: managed-by, chart name/version, app name, instance.
Usage: {{ include "my-webapp.labels" . | nindent 4 }}
*/}}
{{- define "my-webapp.labels" -}}
helm.sh/chart: {{ include "my-webapp.chart" . }}
{{ include "my-webapp.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels — used in spec.selector.matchLabels and spec.template.metadata.labels.
These MUST remain stable across upgrades (K8s does not allow changing selectors).
Usage: {{ include "my-webapp.selectorLabels" . | nindent 6 }}
*/}}
{{- define "my-webapp.selectorLabels" -}}
app.kubernetes.io/name: {{ include "my-webapp.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use.
Usage: {{ include "my-webapp.serviceAccountName" . }}
*/}}
{{- define "my-webapp.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "my-webapp.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Return the full image name including registry, repository and tag.
Handles global imageRegistry override from parent chart.
Usage: {{ include "my-webapp.image" . }}
*/}}
{{- define "my-webapp.image" -}}
{{- $registry := .Values.global.imageRegistry | default "" -}}
{{- $repository := .Values.image.repository -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- if $registry -}}
{{- printf "%s/%s:%s" $registry $repository $tag -}}
{{- else -}}
{{- printf "%s:%s" $repository $tag -}}
{{- end -}}
{{- end }}

{{/*
Return the imagePullSecrets (merged global + local).
Usage: {{ include "my-webapp.imagePullSecrets" . | nindent 6 }}
*/}}
{{- define "my-webapp.imagePullSecrets" -}}
{{- $secrets := concat .Values.global.imagePullSecrets .Values.imagePullSecrets -}}
{{- if $secrets -}}
imagePullSecrets:
{{- range $secrets }}
  - name: {{ . }}
{{- end }}
{{- end -}}
{{- end }}

{{/*
ConfigMap name.
Usage: {{ include "my-webapp.configMapName" . }}
*/}}
{{- define "my-webapp.configMapName" -}}
{{- printf "%s-config" (include "my-webapp.fullname" .) -}}
{{- end }}
