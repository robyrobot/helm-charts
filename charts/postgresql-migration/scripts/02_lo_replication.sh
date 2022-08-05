# 02_lo_replication.sh
# This script is experimental and provide large object syncronization between sources and targets. 
# The script run a neverending task in background

export -f info
export -f secs_to_human
bash <<"BACKGROUND_PROCESS" 2> /tmp/lo_replication_error.log 1> /dev/null &
while [ true ]; do
{{- range .Values.bucardo.syncs }}
{{ $source := index .sources 0 }}
{{- range .targets }}
{{- if .blobs.enabled }}
{{- $block_size := .blobs.blobs_block_size | default 1000 }}
{{- $blob_role := .blobs.blobs_role | default .dbuser }}
LAST_SYNCED_OID=$(psql --host "{{ .dbhost }}" -U "{{ .dbuser }}" -d "{{ .dbname }}" -At -c "select max(oid) from pg_largeobject_metadata;")

# removes objects referring to deleted references
# vacuumlo -l 1000 -h {{ .dbhost }} -U {{ .dbuser }} -p {{ .dbport | default "5432" }} {{ .dbname }} > /dev/null

# get not synced oids
psql --host "{{ $source.dbhost }}" -U "{{ $source.dbuser }}" -d "{{ $source.dbname }}" -At --csv <<EOF | awk -F, '{printf "select lo_from_bytea(%s,'\''%s'\'');\n", $1, $2}' > /tmp/blobs-{{ .dbname }}.txt
select m.oid,lo_get(m.oid) from pg_largeobject_metadata m where m.oid > ${LAST_SYNCED_OID:-0} limit {{ $block_size }};
EOF
      
BLOBS_NUM="$(cat /tmp/blobs-{{ .dbname }}.txt | wc -l)"
[ "$BLOBS_NUM" != "0" ] && {
info "split file in blocks"
split -l {{ $block_size }} /tmp/blobs-{{ .dbname }}.txt /tmp/block-{{ .dbname }}_
      
info "copy $BLOBS_NUM blobs from {{ $source.dbname }} to {{ .dbname }}"
PROCESSED=0
STARTTIME=$(date +%s)
for b in /tmp/block-{{ .dbname }}_*; do
    psql --host "{{ .dbhost }}" -U "{{ .dbuser }}" -d "{{ .dbname }}" <<EOF > /dev/null
    BEGIN;
    SET LOCAL ROLE {{ $blob_role }};
    $(cat $b)
    COMMIT;
EOF
    COPIED_BLOBS="$(psql --host "{{ .dbhost }}" -U "{{ .dbuser }}" -d "{{ .dbname }}" -At -c "select count(oid) from pg_catalog.pg_largeobject_metadata;")"
    PERC=$(awk -vn=$COPIED_BLOBS -vt=$BLOBS_NUM 'BEGIN{printf("%.0f\n", n/t*100)}')
    info "processed $COPIED_BLOBS / $BLOBS_NUM ($PERC%)"
done
rm -f /tmp/block-{{ .dbname }}_*

info "copied $COPIED_BLOBS on $BLOBS_NUM"
ENDTIME=$(date +%s)
ELAPSED=$(($ENDTIME - $STARTTIME))
info "elapsed time: $(secs_to_human $ELAPSED)"
} 
{{- end }}

{{- end }}
{{- end }}
sleep {{ .Values.bucardo.refreshStatusSec }}
done
BACKGROUND_PROCESS
