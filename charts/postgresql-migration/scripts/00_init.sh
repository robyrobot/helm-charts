# 00_init.sh
#

function info() {
  echo "$(date +"%Y-%m-%d %H:%M:%S") => [i] $@"
}

# print huma readable time
secs_to_human() {
    echo "$(( $1 / 3600 ))h $(( ($1 / 60) % 60 ))m $(( $1 % 60 ))s"
}

# pgpass file
export PGPASSFILE=/tmp/.pgpass

[ -e "$PGPASSFILE" ] || {
  info "create pgpass file"
  cat <<EOF > /tmp/.pgpass && chmod 600 /tmp/.pgpass
{{- range .Values.bucardo.syncs }}
{{- range concat .sources .targets }}
{{ .dbhost }}:{{ .dbport | default "5432" }}:{{ .dbname }}:{{ .dbuser }}:{{ .dbpass | replace ":" "\\:" }}
{{- end }}
{{- end }}
EOF
}