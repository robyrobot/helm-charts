# 01_setup_elasticdump.sh
# This script setup elasticdump and starts indices replication
# 

{{- range .Values.elasticdump.syncs }}
{{ $name := .name | replace " " "-" }}
# run each syncs in background
bash <<"EOF" 2> /tmp/sync_{{ $name }}_error.log &
# set initial time range to copy
TM_START=0
TM_END="$(date +%s000)"

# copy data in a neverending loop
while [ true ]; do

  # get info from source and dest about count
  SRC_PATH="/tmp/source_{{ $name }}.lst"
  TRG_PATH="/tmp/target_{{ $name }}.lst"
  curl -sf {{ .sourceBaseUrl }}/_cat/indices/{{ .indexPattern }} -o - | awk '{ print $3","$7 }' > $SRC_PATH
  curl -sf {{ .targetBaseUrl }}/_cat/indices/{{ .indexPattern }} -o - | awk '{ print $3","$7 }' > $TRG_PATH
  
  # copy mapping
  #INDICES=($(curl -sf {{ .sourceBaseUrl }}/_cat/indices/{{ .indexPattern }} -o - | awk '{ print $3 }'))
  INDICES=($(cat $SRC_PATH | awk -F, '{ print $1 }'))
  JOBS="/tmp/elasticdump_{{ $name }}.jobs"
  > $JOBS
  for idx in ${INDICES[@]}; do
    cat <<IDX_EOF > $JOBS
    elasticdump \
      --quiet \
      --input={{ .sourceBaseUrl }}/$idx \
      --output={{ .targetBaseUrl }}/$idx \
      --type=mapping
IDX_EOF
  done

  cat $JOBS | parallel --jobs {{ .jobs }} bash -c
   
  # create temp file that contains the command to execute
  > $JOBS
  for idx in ${INDICES[@]}; do
    TARGET_COUNT="$(cat $TRG_PATH | grep "$idx" | awk -F, '{ print $2 }')"
    SOURCE_COUNT="$(cat $SRC_PATH | grep "$idx" | awk -F, '{ print $2 }')"
    SOURCE_COUNT=${SOURCE_COUNT:-0}
    TARGET_COUNT=${TARGET_COUNT:-0}
    [ "$(( $SOURCE_COUNT - $TARGET_COUNT ))" -gt "0" ] && {
      cat <<DUMP_EOF >> $JOBS
        elasticdump \
        --quiet \
        --input={{ .sourceBaseUrl }}/$idx \
        --output={{ .targetBaseUrl }}/$idx \
        --searchBody "{\"query\":{\"range\":{\"{{ .timestampField }}\":{\"gt\":$TM_START,\"lte\":$TM_END}}}}" \
        --retryAttempts {{ .retryAttempts }} \
        --throttleInterval {{ .throttleInterval }} \
        --scrollTime 1m \
        --type=data 
DUMP_EOF
    }

done

# run elasticdump jobs
cat $JOBS | parallel --jobs {{ .jobs }} bash -c

# reset time range for the next batch
TM_START="$TM_END"
TM_END="$(date +%s000)"

done
EOF

{{- end }}



