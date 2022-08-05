# 03_waiting_loop.sh
# This script code a waiting loop that prints Bucardo status and 
# large object sync status (if present)

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
  SOURCE_BLOBS=$(psql --host "{{ $source.dbhost }}" -U "{{ $source.dbuser }}" -d "{{ $source.dbname }}" -At -c "select count(oid) from pg_largeobject_metadata")
  TARGET_BLOBS=$(psql --host "{{ .dbhost }}" -U "{{ .dbuser }}" -d "{{ .dbname }}" -At -c "select count(oid) from pg_largeobject_metadata")
  [ "$SOURCE_BLOBS" != "0" ] && {
    PERC=$(awk -vn=$TARGET_BLOBS -vt=$SOURCE_BLOBS 'BEGIN{printf("%.0f\n", n/t*100)}')
    info "BLOBs on {{ .dbname }} - source: $SOURCE_BLOBS, synced: $TARGET_BLOBS - process: $PERC%"
  }
{{- end }}
{{- end }}
{{- end }}
  tail /tmp/lo_replication_error.log | sed 's/\[i\]/\[✘\]/'
  sleep {{ .Values.bucardo.refreshStatusSec }}
done 