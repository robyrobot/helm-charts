#set -e

# This script has benn generated automatically 
{{- $fix := .Values.bucardo.fixMissingPrimaryKey.enabled }}
{{- $primaryKey := .Values.bucardo.fixMissingPrimaryKey.primaryKey | default "__pk__"}}

# cd to working folder
cd /media/bucardo

function info() {
  echo "[i] $1"
}

# pgpass file
export PGPASSFILE=/tmp/.pgpass

[ -e "$PGPASSFILE" ] || {
  info "create pgpass file"
  cat <<EOF > /tmp/.pgpass
{{- range .Values.bucardo.syncs }}
{{- range concat .sources .targets }}
{{ .dbhost }}:{{ .dbport | default "5432" }}:{{ .dbname }}:{{ .dbuser }}:{{ .dbpass | replace ":" "\\:" }}
{{- end }}
{{- end }}
EOF
chmod 600 /tmp/.pgpass
}

{{- if .Values.bucardo.debug }}
# debug level
bucardo set log_level=debug
{{- end }}

{{- range .Values.bucardo.syncs }}
  {{- range .sources }}
   info "drop bucardo schema if exists for {{ .dbname }}"   
   psql --host "{{ .dbhost }}" -U "{{ .dbuser }}" -d "{{ .dbname }}" -c 'DROP SCHEMA IF EXISTS "bucardo" CASCADE;'
   info "vacum large object from {{ .dbname }}"
   vacuumlo -v -l 1000 -h {{ .dbhost }} -U {{ .dbuser }} -p {{ .dbport | default "5432" }} {{ .dbname }}
  {{- end }}  
  
  {{ $source := index .sources 0 }}
  # for each target restore the db using source schema one
  {{- range .targets }}
    {{- if .overwrite.enabled }}
      info "clear connections"
      psql -v ON_ERROR_STOP=1 --host "{{ .dbhost }}" -U "{{ .dbuser }}" -d "{{ .dbname }}" <<EOF
      select pg_terminate_backend(pid) from pg_stat_activity where datname='{{ .dbname }}' and pid <> pg_backend_pid();      
EOF

      {{- if .overwrite.schemas }}
      info "drop schemas for {{ .dbname }}"      
      psql -v ON_ERROR_STOP=1 --host "{{ .dbhost }}" -U "{{ .dbuser }}" -d "{{ .dbname }}" <<EOF
      {{- range  .overwrite.schemas }}
      DROP SCHEMA IF EXISTS "{{ . }}" CASCADE; 
      --CREATE SCHEMA IF NOT EXISTS "{{ . }}";     
      {{- end }}      
      CREATE SCHEMA IF NOT EXISTS "public";
EOF

      {{- end }}
      # using pgcopydb
      export PGCOPYDB_SOURCE_PGURI='port=5432 host={{ $source.dbhost }} dbname={{ $source.dbname }} user={{ $source.dbuser }} password={{ $source.dbpass }}'
      export PGCOPYDB_TARGET_PGURI='port=5432 host={{ .dbhost }} dbname={{ .dbname }} user={{ .dbuser }} password={{ .dbpass }}'
      cat <<EOF > /tmp/pgcopydb.cfg
      [exclude-schema]
      bucardo

EOF
      info "vacum large objects from {{ .dbname }}"
      vacuumlo -v -l 1000 -h {{ .dbhost }} -U {{ .dbuser }} -p {{ .dbport | default "5432" }} {{ .dbname }}
      
      info "copy schema"
      #pg_dump --schema-only --no-acl --no-owner --no-comments --no-publications --no-subscriptions -N bucardo --host "{{ $source.dbhost }}" -U "{{ $source.dbuser }}" -d "{{ $source.dbname }}" -Fc | \
      #pg_restore --schema-only --clean --if-exists --no-acl --no-owner --no-comments --no-publications --no-subscriptions --host "{{ .dbhost }}" -U "{{ .dbuser }}" -d "{{ .dbname }}" -N bucardo

      pgcopydb copy schema --dir /tmp/pgcopydb/{{ .dbname }} --table-jobs 1 --index-jobs 1 --no-acl --no-owner --no-comments --resume --not-consistent --filters /tmp/pgcopydb.cfg
      {{- if .overwrite.dumpBlobs }}
      info "copy blobs"
      pgcopydb copy blobs --dir /tmp/pgcopydb/{{ .dbname }} --table-jobs 1 --index-jobs 1 --no-owner --no-acl --no-comments --resume --not-consistent --filters /tmp/pgcopydb.cfg 
      {{- end }}
              
    {{- else }}
      info "no clean required for {{ .dbname }}"
    {{- end }}
  {{- end }}
{{- end }}

{{- range .Values.bucardo.syncs }}
  {{- range concat .sources .targets }}
    {{- if $fix }}
      # try to fix tables with missing primary key
      info "try to fix tables with missing primary key on db {{ .dbname }}"
      PGPASSWORD='{{ .dbpass }}' psql -v ON_ERROR_STOP=1 --host "{{ .dbhost }}" -U "{{ .dbuser }}" -d "{{ .dbname }}" <<EOF
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
  bucardo add database {{ .name }}  dbname="{{ .dbname }}" host="{{ .dbhost }}" user="{{ .dbuser }}" pass="{{ .dbpass }}" 

  {{- end }}

  {{- range .sources }}
    {{ $excludeTables := "" }}
    {{- if .excludeTables }}
      {{ $excludeTables = join " -T " .excludeTables }}
    {{- end }}

    {{- if .includeTables }}
      {{- range .includeTables }}
        bucardo add table . db="{{ .name }}" relgroup="{{ .name }}" 
      {{- end }}
    {{- else }}
      bucardo add all tables db="{{ .name }}" relgroup="{{ .name }}" {{ $excludeTables }} 
    {{- end }}
    bucardo add all sequences db="{{ .name }}" relgroup="{{ .name }}"
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
  bucardo add sync {{ .name }} relgroup="{{ $relgroup }}" dbs={{ $dbs }} status=active onetimecopy={{ .onetimecopy }} conflict_strategy=bucardo_source strict_checking=false
{{- end }}


{{- range .Values.bucardo.syncs }}  
  {{- range .targets }}
    {{- if .postAction.enabled }}
      info "execute post actions on {{ .dbname }}"      
      PGPASSWORD='{{ .dbpass }}' psql -v ON_ERROR_STOP=1 --host "{{ .dbhost }}" -U "{{ .dbuser }}" -d "{{ .dbname }}" <<EOF
      {{ .postAction.script | nindent 8 }}
EOF
    {{- end }}
  {{- end }}
{{- end }}

info "start bucardo"
bucardo start 

while [ true ]; do
  bucardo status
  sleep {{ .Values.bucardo.refreshStatusSec }}
done 



