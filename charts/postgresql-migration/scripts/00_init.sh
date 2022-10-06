# 00_init.sh
#

function info() {
  echo -e "$(date +"%Y-%m-%d %H:%M:%S") => [i] $@"
}

function error() {
  echo -e "$(date +"%Y-%m-%d %H:%M:%S") => [✘] $@"
}

function progress() {
  local w=30 p=$1;
  shift;
  printf -v dots "%*s" "$(( $p*$w/100 ))" "";
  dots=${dots// /#};
  #printf "[%-*s] %3d %% %s" "$w" "$dots" "$p" "$*";  
  printf "[%-*s] %s" "$w" "$dots" "$*";
}

function progress() {
  local w=30 p=$1;
  shift;
  printf -v dots "%*s" "$(( $p*$w/100 ))" "";
  dots=${dots// /#};
  #printf "[%-*s] %3d %% %s" "$w" "$dots" "$p" "$*";  
  printf "[%-*s] %s" "$w" "$dots" "$*";
}

[ -e "$PGPASSFILE" ] || {
cat <<EOF > /tmp/.pgpass && chmod 600 /tmp/.pgpass
{{- range .Values.bucardo.syncs }}
{{- range .sources }}
{{ .dbhost }}:{{ .dbport | default "5432" }}:{{ .dbname }}:{{ .dbuser }}:{{ .dbpass | replace ":" "\\:" }}
{{- end }}
{{- range .targets }}
{{ .dbhost }}:{{ .dbport | default "5432" }}:{{ .dbname }}:{{ .dbuser }}:{{ .dbpass | replace ":" "\\:" }}
{{ .dbhost }}:{{ .dbport | default "5432" }}:{{ .dbname }}:{{ .adminUser }}:{{ .adminPass | replace ":" "\\:" }}
{{- end }}
{{- end }}
EOF
}

STDLOG="/dev/null"
{{- if .Values.bucardo.debug }}
STDLOG="/dev/stdout"
{{- end }}

export -f info
export -f error
export -f progress

# pgpass file
export PGPASSFILE=/tmp/.pgpass
export STDLOG
