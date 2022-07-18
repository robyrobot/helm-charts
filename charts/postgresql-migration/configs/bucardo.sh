#!/usr/bin/env bash
#set -e

# This script has benn generated automatically 
{{- $fix := .Values.bucardo.fixMissingPrimaryKey.enabled }}
{{- $primaryKey := .Values.bucardo.fixMissingPrimaryKey.primaryKey | default "__pk__"}}

# pgpass file
#export PGPASSFILE=/media/bucardo/.pgpass

# cd to working folder
cd /media/bucardo

function info() {
  echo "[i] $1"
}

#trap "stopHook.sh" SIGINT SIGTERM SIGHUP EXIT

#info "clean bucardo previous init"
#clean "init actions"

{{- if .Values.bucardo.debug }}
# debug level
bucardo set log_level=debug
{{- end }}

info "start bucardo"
bucardo start 

{{- range .Values.bucardo.syncs }}
  {{ $source := index .sources 0 }}
  # for each target restore the db using source schema one
  {{- range .targets }}
    {{- if .cleanDb }}
      # pgdump source db
      info "dump {{ $source.dbname }}"
      {{- if .copyBlobs }}
      pg_dump -v --clean --if-exists --no-privileges --blobs --no-comments --no-owner -N bucardo --host "{{ $source.dbhost }}" -U "{{ $source.dbuser }}" -d "{{ $source.dbname }}" -Fc > {{ $source.name }}.sql 
      info "restore {{ $source.dbname }} -> {{ .dbname }} with data and blobs"
      pg_restore -v --clean --if-exists --no-privileges --no-comments --no-owner -N bucardo --host "{{ $source.dbhost }}" -U "{{ $source.dbuser }}" -d "{{ $source.dbname }}" -Fc < {{ $source.name }}.sql

      {{- else }}  
      pg_dump -v --clean --if-exists --no-privileges --schema-only --no-comments --no-owner -N bucardo --host "{{ $source.dbhost }}" -U "{{ $source.dbuser }}" -d "{{ $source.dbname }}" -Fc > {{ $source.name }}.sql
      info "restore {{ $source.dbname }} -> {{ .dbname }} schema only"
      pg_restore -v --clean --if-exists --no-privileges --no-comments --no-owner -N bucardo --host "{{ $source.dbhost }}" -U "{{ $source.dbuser }}" -d "{{ $source.dbname }}" -Fc < {{ $source.name }}.sql

      {{- end }}
      
      #psql -v ON_ERROR_STOP=1 --echo-all --echo-queries --echo-hidden --echo-errors --host "{{ .dbhost }}" -U "{{ .dbuser }}" -d "{{ .dbname }}" < {{ $source.name }}.sql
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
      psql -v ON_ERROR_STOP=1 --host "{{ .dbhost }}" -U "{{ .dbuser }}" -d "{{ .dbname }}" <<EOF
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
      psql -v ON_ERROR_STOP=1 --host "{{ .dbhost }}" -U "{{ .dbuser }}" -d "{{ .dbname }}" <<EOF
      {{ .postAction.script | nindent 8 }}
EOF
    {{- end }}
  {{- end }}
{{- end }}

#tail -f /var/log/bucardo/log.bucardo

while [ true ]; do
  bucardo status
  sleep {{ .Values.bucardo.refreshStatusSec }}
done 



