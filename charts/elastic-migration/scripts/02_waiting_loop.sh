# 03_waiting_loop.sh
# This script code a waiting loop that prints Bucardo status and 
# large object sync status (if present)

LAST_TARGET_COUNT=0
while [ true ]; do  
  {{- range .Values.elasticdump.syncs }}
  {{ $name := .name | replace " " "-" }}
  echo ""
  info "Indices replication status sync: {{ $name }}"
  
  # get info from source and dest aboud count
  SRC_PATH="/tmp/source_{{ $name }}.lst"
  TRG_PATH="/tmp/target_{{ $name }}.lst"
  curl -sf {{ .sourceBaseUrl }}/_cat/indices/{{ .indexPattern }} -o - | awk '{ print $3","$7 }' > $SRC_PATH
  curl -sf {{ .targetBaseUrl }}/_cat/indices/{{ .indexPattern }} -o - | awk '{ print $3","$7 }' > $TRG_PATH
  
  for i in $(cat $SRC_PATH); do        
    SOURCE_IDX="$(echo "$i" | awk -F, '{ print $1 }')"
    SOURCE_COUNT="$(echo "$i" | awk -F, '{ print $2 }')"
    TARGET_COUNT="$(cat $TRG_PATH | grep "$SOURCE_IDX" | awk -F, '{ print $2 }')"
    SOURCE_COUNT=${SOURCE_COUNT:-0}
    TARGET_COUNT=${TARGET_COUNT:-0}
 
    [ "$SOURCE_COUNT" != "0" ] && [ "$TARGET_COUNT" -gt "0" ] && [ "$SOURCE_COUNT" != "$TARGET_COUNT" ] && {
      PERC_INT=$(awk -vn=$TARGET_COUNT -vt=$SOURCE_COUNT 'BEGIN{printf("%.0f\n", n/t*100)}')
      PERC_2=$(awk -vn=$TARGET_COUNT -vt=$SOURCE_COUNT 'BEGIN{printf("%.2f\n", n/t*100)}')
      info "\t\t$(progress $PERC_INT "$PERC_2 % [$SOURCE_IDX ($SOURCE_COUNT/$TARGET_COUNT)]")"
    }
  done
  
  # print last line of error if any
  [ -s "/tmp/sync_{{ $name }}_error.log" ] && {
    error "Last error line: $(tail -n 1 /tmp/sync_{{ $name }}_error.log)"    
  }
  
  {{- end }}
  sleep {{ .Values.elasticdump.refreshStatusSec }}
done 