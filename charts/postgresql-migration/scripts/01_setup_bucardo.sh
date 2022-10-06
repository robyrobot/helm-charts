# 01_setup_bucardo.sh
# This script setup replication with Bucardo
# 

#BUCARDO_OPTS="--quiet"
{{- $fix := .Values.bucardo.fixMissingPrimaryKey.enabled }}
{{- $primaryKey := .Values.bucardo.fixMissingPrimaryKey.primaryKey | default "__pk__"}}

# for each syncs sources
{{- range .Values.bucardo.syncs }}
{{ $source := index .sources 0 }}
  
# for each target restore the db using source schema one
{{- range .targets }}

# if clean required
{{- if .overwrite.enabled }}
{{- $table_jobs := .overwrite.table_jobs | default 2 }}
{{- $index_jobs := .overwrite.index_jobs | default 2 }}
{{- $target := . }}
# target: {{ .dbname }}
#

info "clear connections"
psql --host "{{ .dbhost }}" -U "{{ .adminUser | default .dbuser }}" -d "{{ .dbname }}" <<EOF > $STDLOG
select pg_terminate_backend(pid) from pg_stat_activity where datname='{{ .dbname }}' and pid <> pg_backend_pid();      
EOF

# using pgcopydb
export PGCOPYDB_SOURCE_PGURI='port=5432 host={{ $source.dbhost }} dbname={{ $source.dbname }} user={{ $source.dbuser }} password={{ $source.dbpass }}'
export PGCOPYDB_TARGET_PGURI='port=5432 host={{ .dbhost }} dbname={{ .dbname }} user={{ .adminUser | default .dbuser }} password={{ .adminPass | default .dbpass }}'
cat <<EOF > /tmp/pgcopydb.cfg
[exclude-schema]
bucardo
EOF

{{- if .overwrite.schemas }}
info "drop schemas {{ join "," .overwrite.schemas }} on {{ $target.dbname }}"
psql --host "{{ $target.dbhost }}" -U "{{ $target.adminUser | default $target.dbuser }}" -d "{{ $target.dbname }}" <<EOF > $STDLOG
{{- range .overwrite.schemas }}
DROP SCHEMA IF EXISTS "{{ . }}" CASCADE;
{{- end }}
CREATE SCHEMA IF NOT EXISTS public;
EOF

{{ end }} 

info "vacum large objects from {{ .dbname }}"
vacuumlo -h {{ .dbhost }} -U {{ .adminUser | default .dbuser }} -p {{ .dbport | default "5432" }} {{ .dbname }} > $STDLOG
      
{{- if .overwrite.clone }}
info "clone"
pgcopydb clone --dir /tmp/pgcopydb/{{ .dbname }} --table-jobs {{ $table_jobs }} --index-jobs {{ $index_jobs }} --no-owner --no-acl --skip-large-objects --no-comments --restart --not-consistent --drop-if-exists --filters /tmp/pgcopydb.cfg
{{- else }}
info "copy schema"
pg_dump --schema-only --no-acl --no-owner --no-comments --no-publications --no-subscriptions -N bucardo --host "{{ $source.dbhost }}" -U "{{ $source.dbuser }}" -d "{{ $source.dbname }}" -Fc | \
pg_restore --schema-only --clean --if-exists --no-acl --no-owner --no-comments --no-publications --no-subscriptions --host "{{ .dbhost }}" -U "{{ .adminUser | default .dbuser }}" -d "{{ .dbname }}" -N bucardo > $STDLOG
#pgcopydb copy schema --dir /tmp/pgcopydb/{{ .dbname }} --table-jobs {{ $table_jobs }} --index-jobs {{ $index_jobs }} --no-acl --no-owner --no-comments --resume --not-consistent --drop-if-exists --filters /tmp/pgcopydb.cfg
{{- end }}

# fix schema ownership
info "fix ownership in db {{ .dbname }}"
psql --host "{{ .dbhost }}" -U "{{ .adminUser | default .dbuser }}" -d "{{ .dbname }}" <<EOF > $STDLOG
  -- fix ownership
  do \$\$ declare
    r record;
  begin
    for r in (select * from information_schema.tables where table_schema not in ('pg_catalog', 'information_schema')) loop
      execute format ('alter table %s.%s owner to {{ .dbuser }};', quote_ident(r.table_schema), quote_ident(r.table_name));
    end loop;
  end; \$\$
EOF

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
psql --host "{{ .dbhost }}" -U "{{ .adminUser | default .dbuser }}" -d "{{ .dbname }}" <<EOF > $STDLOG
{{ .postAction.script | nindent 8 }}
EOF
{{- end }}
{{- end }}
{{- end }}

# adding databases
{{- range .Values.bucardo.syncs }}
{{- range concat .sources .targets }}
{{- if $fix }}
# try to fix tables with missing primary key
info "try to fix tables with missing primary key on db {{ .dbname }}"
psql --host "{{ .dbhost }}" -U "{{ .adminUser | default .dbuser }}" -d "{{ .dbname }}" <<EOF > $STDLOG
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

info "adding database {{ .dbname }} to bucardo"
bucardo add database {{ .name }}  dbname="{{ .dbname }}" host="{{ .dbhost }}" user="{{ .adminUser | default .dbuser }}" pass="{{ .adminPass | default .dbpass }}" $BUCARDO_OPTS > $STDLOG
{{- end }}
{{- end }}


# add tables to bucardo sync
{{- range .Values.bucardo.syncs }}
{{- $sync := . }}
{{- range .targets }}
# create a table list from targets
TARGET_TABLES_INFO=()
TARGET_TABLES_INFO+=($(psql --host "{{ .dbhost }}" -U "{{ .adminUser | default .dbuser }}" -d "{{ .dbname }}" -At --csv <<EOF 
select table_schema,table_name from information_schema.tables where table_schema not in ('pg_catalog', 'information_schema');
EOF
))
{{- end }}

{{- range .sources }}
{{- if $sync.excludeTables }}
{{ $excludeTables = join " -T " $sync.excludeTables }}
info "add all tables but: $excludeTables"
bucardo add all tables db="{{ .name }}" relgroup="{{ .name }}" {{ $excludeTables }} $BUCARDO_OPTS > $STDLOG
{{- else }}
{{- if $sync.includeTables }}
{{- range $sync.includeTables }}
info "add table {{ . }}"
bucardo add table {{ . }} db="{{ .name }}" relgroup="{{ .name }}" $BUCARDO_OPTS > $STDLOG
{{- end }}
{{- else }}
for t in ${TARGET_TABLES_INFO[@]}; do
TNAME="$(echo $t | awk -F, '{ print $2; }')"
TSCHEMA="$(echo $t | awk -F, '{ print $1; }')"
info "add table "$TSCHEMA".$TNAME db: {{ .dbname }}"
bucardo add table "$TSCHEMA.$TNAME" db="{{ .name }}" relgroup="{{ $sync.name }}" $BUCARDO_OPTS > $STDLOG
done
{{- end }}
{{- end }}

# end range .sources
{{- end }}

# end range syncs
{{- end }}

# adding syncs
{{- range .Values.bucardo.syncs }}
{{- $relgroup := .name }}
{{- $sources := "" }}
{{- $targets := "" }}
{{- range .sources }}
  {{- $sources = printf "%s:source,%s" .name $sources | trimAll "," }}
{{- end }}
{{- range .targets }}
  {{- $targets = printf "%s:target,%s" .name $targets | trimAll "," }}
{{- end }}
{{- $dbs := printf "%s,%s" $sources $targets }}
bucardo add sync {{ .name }} relgroup="{{ $relgroup }}" dbs={{ $dbs }} status=active onetimecopy={{ .onetimecopy }} conflict_strategy=bucardo_source strict_checking=false $BUCARDO_OPTS > $STDLOG

{{- end }}

# add customcols
# https://bucardo.org/Bucardo/operations/customselect

{{- range .Values.bucardo.syncs }}
{{- $sync := . }}
{{- if $sync.customcols }}
{{- range $sync.customcols }}
bucardo add customcols {{ .tableName }} "{{ .expr }}"
{{- end }}
{{- else }}
{{- range .targets }}
# create a table list 
TARGET_TABLES_INFO=($(psql --host "{{ .dbhost }}" -U "{{ .adminUser | default .dbuser }}" -d "{{ .dbname }}" -At --csv <<EOF 
select table_schema,table_name from information_schema.tables where table_schema not in ('pg_catalog', 'information_schema');
EOF
))
for t in ${TARGET_TABLES_INFO[@]}; do
TNAME="$(echo $t | awk -F, '{ print $2; }')"
TSCHEMA="$(echo $t | awk -F, '{ print $1; }')"

# get columns
COLUMN_LIST=($(psql --host "{{ .dbhost }}" -U "{{ .adminUser | default .dbuser }}" -d "{{ .dbname }}" -At <<EOF 
select column_name from information_schema."columns" where table_name = '$TNAME' order by ordinal_position;
EOF
))

COLUMNS="$(echo "${COLUMN_LIST[*]}" | sed 's/ /,/g')"
info "add customcols for table: $TNAME from db: {{ .dbname }}: SELECT $COLUMNS"
bucardo add customcols "$TSCHEMA.$TNAME" "SELECT $COLUMNS" sync="{{ $sync.name }}" > $STDLOG
done
{{- end }} 
{{- end }}
{{- end }}

info "start bucardo"
bucardo start 


