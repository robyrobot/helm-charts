# 01_setup_bucardo.sh
# This script setup replication with Bucardo
# 

{{ $log := "/dev/null" }}

BUCARDO_OPTS="--quiet"
{{- $fix := .Values.bucardo.fixMissingPrimaryKey.enabled }}
{{- $primaryKey := .Values.bucardo.fixMissingPrimaryKey.primaryKey | default "__pk__"}}

# for each syncs sources
{{- range .Values.bucardo.syncs }}
{{- range .sources }}
info "drop bucardo schema if exists for {{ .dbname }}"   
psql --host "{{ .dbhost }}" -U "{{ .dbuser }}" -d "{{ .dbname }}" -c 'DROP SCHEMA IF EXISTS "bucardo" CASCADE;' > {{ $log }}
#info "vacum large object from {{ .dbname }}"
#vacuumlo -l 1000 -h {{ .dbhost }} -U {{ .dbuser }} -p {{ .dbport | default "5432" }} {{ .dbname }} > {{ $log }}
{{- end }}  
  
{{ $source := index .sources 0 }}
  
# for each target restore the db using source schema one
{{- range .targets }}
{{- if .overwrite.enabled }}
{{- $table_jobs := .overwrite.table_jobs | default 2 }}
{{- $index_jobs := .overwrite.index_jobs | default 2 }}
{{- $target := . }}
# target: {{ .dbname }}
#
info "clear connections"
psql --host "{{ .dbhost }}" -U "{{ .dbuser }}" -d "{{ .dbname }}" <<EOF > {{ $log }}
select pg_terminate_backend(pid) from pg_stat_activity where datname='{{ .dbname }}' and pid <> pg_backend_pid();      
EOF

# using pgcopydb
export PGCOPYDB_SOURCE_PGURI='port=5432 host={{ $source.dbhost }} dbname={{ $source.dbname }} user={{ $source.dbuser }} password={{ $source.dbpass }}'
export PGCOPYDB_TARGET_PGURI='port=5432 host={{ .dbhost }} dbname={{ .dbname }} user={{ .dbuser }} password={{ .dbpass }}'
cat <<EOF > /tmp/pgcopydb.cfg
[exclude-schema]
bucardo
EOF

{{- if .overwrite.schemas }}
info "drop schemas"
psql --host "{{ $target.dbhost }}" -U "{{ $target.dbuser }}" -d "{{ $target.dbname }}" <<EOF > {{ $log }}
{{- range .overwrite.schemas }}
DROP SCHEMA IF EXISTS "{{ . }}" CASCADE;
{{- end }}
CREATE SCHEMA IF NOT EXISTS public;
EOF

{{ end }} 

info "vacum large objects from {{ .dbname }}"
vacuumlo -h {{ .dbhost }} -U {{ .dbuser }} -p {{ .dbport | default "5432" }} {{ .dbname }} > {{ $log }}
      
{{- if .overwrite.clone }}
info "clone"
pgcopydb clone --dir /tmp/pgcopydb/{{ .dbname }} --table-jobs {{ $table_jobs }} --index-jobs {{ $index_jobs }} --no-owner --no-acl --skip-large-objects --no-comments --restart --not-consistent --drop-if-exists --filters /tmp/pgcopydb.cfg
{{- else }}
info "copy schema"
pg_dump --schema-only --no-acl --no-owner --no-comments --no-publications --no-subscriptions -N bucardo --host "{{ $source.dbhost }}" -U "{{ $source.dbuser }}" -d "{{ $source.dbname }}" -Fc | \
pg_restore --schema-only --clean --if-exists --no-acl --no-owner --no-comments --no-publications --no-subscriptions --host "{{ .dbhost }}" -U "{{ .dbuser }}" -d "{{ .dbname }}" -N bucardo > {{ $log }}
#pgcopydb copy schema --dir /tmp/pgcopydb/{{ .dbname }} --table-jobs {{ $table_jobs }} --index-jobs {{ $index_jobs }} --no-acl --no-owner --no-comments --resume --not-consistent --drop-if-exists --filters /tmp/pgcopydb.cfg
{{- end }}
     
{{- else }}
info "no clean required for {{ .dbname }}"
{{- end }}
   
# end for each targets
{{- end }}
{{- end }}



# post actions
{{- range .Values.bucardo.syncs }}  
{{- range .targets }}
{{- if .postAction.enabled }}
info "execute post actions on {{ .dbname }}"      
psql --host "{{ .dbhost }}" -U "{{ .dbuser }}" -d "{{ .dbname }}" <<EOF > {{ $log }}
{{ .postAction.script | nindent 8 }}
EOF
{{- end }}
{{- end }}
{{- end }}


{{- range .Values.bucardo.syncs }}
{{- range concat .sources .targets }}
{{- if $fix }}
  # try to fix tables with missing primary key
  info "try to fix tables with missing primary key on db {{ .dbname }}"
  psql --host "{{ .dbhost }}" -U "{{ .dbuser }}" -d "{{ .dbname }}" <<EOF > {{ $log }}
  -- add primary keys where not available
  do \$\$ declare
    r record;
  begin
    for r in (select tbl.table_schema, tbl.table_name
              from information_schema.tables tbl
              where table_type = 'BASE TABLE'
                and table_schema not in ('pg_catalog', 'information_schema', 'bucardo')
                and not exists (select 1 
                                from information_schema.key_column_usage kcu
                                where kcu.table_name = tbl.table_name 
                                  and kcu.table_schema = tbl.table_schema)) loop
      execute format ('alter table %s.%s add column {{ $primaryKey }} serial primary key;', quote_ident(r.table_schema), quote_ident(r.table_name));
    end loop;
  end; \$\$
EOF
{{- end }}

# adding databases
info "adding database {{ .dbname }} to bucardo"
bucardo add database {{ .name }}  dbname="{{ .dbname }}" host="{{ .dbhost }}" user="{{ .dbuser }}" pass="{{ .dbpass }}" $BUCARDO_OPTS > {{ $log }}
{{- end }}

{{- range .sources }}
{{ $excludeTables := "" }}
{{- if .excludeTables }}
{{ $excludeTables = join " -T " .excludeTables }}
{{- end }}
{{- if .includeTables }}
{{- range .includeTables }}
bucardo add table . db="{{ .name }}" relgroup="{{ .name }}" $BUCARDO_OPTS > {{ $log }}
{{- end }}
{{- else }}
bucardo add all tables db="{{ .name }}" relgroup="{{ .name }}" {{ $excludeTables }} $BUCARDO_OPTS > {{ $log }}
{{- end }}
bucardo add all sequences db="{{ .name }}" relgroup="{{ .name }}" $BUCARDO_OPTS > {{ $log }}
{{- end }}

{{- end }}

 
# adding syncs
{{- range .Values.bucardo.syncs }}
{{- $relgroup := (index .sources 0).name }}
{{- $sources := "" }}
{{- $targets := "" }}
{{- range .sources }}
  {{- $sources = printf "%s:source,%s" .name $sources | trimAll "," }}
{{- end }}
{{- range .targets }}
  {{- $targets = printf "%s:target,%s" .name $targets | trimAll "," }}
{{- end }}
{{- $dbs := printf "%s,%s" $sources $targets }}
bucardo add sync {{ .name }} relgroup="{{ $relgroup }}" dbs={{ $dbs }} status=active onetimecopy={{ .onetimecopy }} conflict_strategy=bucardo_source strict_checking=false $BUCARDO_OPTS > {{ $log }}
{{- end }}

info "start bucardo"
bucardo start 


