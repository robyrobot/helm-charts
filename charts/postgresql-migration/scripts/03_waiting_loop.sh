# 03_waiting_loop.sh
# This script code a waiting loop that prints Bucardo status and 
# large object sync status (if present)

# function count_total_lo() {
#   local TABLES=($(psql --host "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -At --csv -c "select table_schema, table_name, column_name from information_schema.columns c where c.data_type = 'oid' and c.table_schema in ($SCHEMA_LIST)"))
#   local COUNT=0
#   for t in ${TABLES[@]}; do        
#     local CMD="$(echo $t | awk -F, '{ printf "select count(%s) from \"%s\".%s where %s is not null;", $3, $1, $2, $3 }')"
#     local RES=$(psql --host "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -At -c "$CMD")
#     COUNT=$(( $COUNT + ${RES:-0} ))
#   done  
#   echo $COUNT
# }

touch /tmp/lo_replication_error.log
while [ true ]; do
  info "Bucardo status"
  echo -e ""
  bucardo status
  echo -e ""
{{- range .Values.bucardo.syncs }}
{{ $source := index .sources 0 }}
{{- range .targets }}
{{- if .blobs.enabled }}
  SOURCE_COUNT=$(psql --host "{{ $source.dbhost }}" -U "{{ $source.dbuser }}" -d "{{ $source.dbname }}" -At -c "select count(oid) from pg_largeobject_metadata")
  TARGET_COUNT=$(psql --host "{{ .dbhost }}" -U "{{ .dbuser }}" -d "{{ .dbname }}" -At -c "select count(oid) from pg_largeobject_metadata")
  [ "$SOURCE_COUNT" != "0" ] && {
    PERC_INT=$(awk -vn=$TARGET_COUNT -vt=$SOURCE_COUNT 'BEGIN{printf("%.0f\n", n/t*100)}')
    PERC_2=$(awk -vn=$TARGET_COUNT -vt=$SOURCE_COUNT 'BEGIN{printf("%.2f\n", n/t*100)}')
    info "$(progress $PERC_INT "$PERC_2 % [{{ .dbname }} ($SOURCE_COUNT/$TARGET_COUNT)]")"
  }
{{- end }}
{{- end }}
{{- end }}

  # print last line of error if any
  [ -s "/tmp/lo_replication_error.log" ] && {
    error "Last error line: $(tail /tmp/lo_replication_error.log | sed 's/\[i\]/\[✘\]/')"    
  }
  
  sleep {{ .Values.bucardo.refreshStatusSec }}
done 