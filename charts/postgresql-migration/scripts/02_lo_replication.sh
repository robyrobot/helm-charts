# 02_lo_replication.sh
# This script is experimental and provide large object syncronization between sources and targets. 
# The script run a neverending task in background
{{- range .Values.bucardo.syncs }}
{{ $source := index .sources 0 }}
bash <<"BACKGROUND_PROCESS" 2> /tmp/lo_replication_{{ .name }}_error.log 1> $STDLOG &
while [ true ]; do
{{- range .targets }}
{{- if .blobs.enabled }}
{{- $block_size := .blobs.blobs_block_size | default 1000 }}
{{- $blob_role := .blobs.blobs_role | default .dbuser }}

LAST_SYNCED_OID=$(psql --host "{{ .dbhost }}" -U "{{ .dbuser }}" -d "{{ .dbname }}" -At -c "select max(oid) from pg_largeobject_metadata;")

# removes objects referring to deleted references
# vacuumlo -l 1000 -h {{ .dbhost }} -U {{ .dbuser }} -p {{ .dbport | default "5432" }} {{ .dbname }} 

# generate_lo_list
LO_LIST="/tmp/blobs-{{ .dbname }}.txt" 
psql --host "{{ $source.dbhost }}" -U "{{ $source.dbuser }}" -d "{{ $source.dbname }}" -At --csv <<EOF | awk -F, '{printf "select lo_from_bytea(%s,'\''%s'\'');\n", $1, $2}' > $LO_LIST
select m.oid,lo_get(m.oid) from pg_largeobject_metadata m where m.oid > ${LAST_SYNCED_OID:-0};
EOF
      
BLOBS_NUM="$(cat $LO_LIST | wc -l)"
[ "$BLOBS_NUM" != "0" ] && {
info "split file in blocks"
split -l {{ $block_size }} $LO_LIST /tmp/block-{{ .dbname }}_
      
info "copy $BLOBS_NUM blobs from {{ $source.dbname }} to {{ .dbname }}"
for b in /tmp/block-{{ .dbname }}_*; do
    psql --host "{{ .dbhost }}" -U "{{ .dbuser }}" -d "{{ .dbname }}" -At <<EOF > /dev/null
    BEGIN;
    SET LOCAL ROLE {{ $blob_role }};
    $(cat $b)
    COMMIT;
EOF
done
rm -f /tmp/block-{{ .dbname }}_*
} 
sleep {{ $.Values.bucardo.refreshStatusSec }}
{{- else }}
exit 0;
{{- end }}
done
{{- end }}
BACKGROUND_PROCESS
{{- end }}