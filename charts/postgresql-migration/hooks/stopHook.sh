# clean up script
# delete bucardo schema in all databases
# delete temporary primarykey added column

{{- $fix := .Values.bucardo.fixMissingPrimaryKey.enabled }}
{{- $primaryKey := .Values.bucardo.fixMissingPrimaryKey.primaryKey | default "__pk__"}}

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

{{- range .Values.bucardo.syncs }}

{{- range concat .sources .targets }}
psql --host "{{ .dbhost }}" -U "{{ .dbuser }}" -d "{{ .dbname }}" <<EOF
DROP SCHEMA IF EXISTS bucardo CASCADE;

-- remove temporary added primary keys
do \$\$ declare
r record;
begin
for r in (select tbl.table_schema, tbl.table_name
        from information_schema.tables tbl
        where table_type = 'BASE TABLE'
        and table_schema not in ('pg_catalog', 'information_schema', 'bucardo')
        and exists (select 1 
                        from information_schema.key_column_usage kcu
                        where kcu.table_name = tbl.table_name 
                            and kcu.table_schema = tbl.table_schema
                            and kcu.column_name = '{{ $primaryKey }}')) loop
    execute format ('alter table %s.%s drop column {{ $primaryKey }} ;', quote_ident(r.table_schema), quote_ident(r.table_name));
end loop;
end; \$\$
EOF
{{- end }}

{{- end }}