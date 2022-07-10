#!/usr/bin/env bash
set -euo pipefail

# This script has benn generated automatically 

trap "clean" EXIT

function clean() {
  bucardo stop
}

{{- $fix := $.Values.bucardo.fixMissingPrimaryKey.enabled }}
{{- $primaryKey := $.Values.bucardo.fixMissingPrimaryKey.primaryKey}}
{{- range concat .Values.bucardo.sources .Values.bucardo.targets }}
{{- if $fix }}
# try to fix tables with missing primary key
T_TABLES=($(psql -v ON_ERROR_STOP=1 --host "{{ .dbhost }}" -U "{{ .dbuser }}" -d "{{ .dbname }}" -At --csv <<EOF | awk -F, '{print $1"."$2}' 
  select tbl.table_schema, 
        tbl.table_name
  from information_schema.tables tbl
  where table_type = 'BASE TABLE'
    and table_schema not in ('pg_catalog', 'information_schema')
    and not exists (select 1 
                    from information_schema.key_column_usage kcu
                    where kcu.table_name = tbl.table_name 
                      and kcu.table_schema = tbl.table_schema)
EOF
  ))

  for i in "${T_TABLES[@]}"; do
    echo "add primary key {{ primaryKey }} to table [$i] in database [{{ .dbname }}]"
    psql -v ON_ERROR_STOP=1 --host "{{ .dbhost }}" -U "{{ .dbuser }}" -d "{{ .dbname }}" -At <<EOF
      ALTER TABLE $i ADD COLUMN {{ $primaryKey }} SERIAL PRIMARY KEY;
EOF
  done
done
{{- end }} # if

# adding databases
bucardo add database {{ .dbname }} dbname="{{ .dbname }}" dbuser="{{ .dbuser }}"

{{- end }} # range

# adding tables and sequences for sources database
{{- range .Values.bucardo.sources }}
# adding tables 
bucardo add all tables db="{{ .dbname }}" relgroup="{{ .dbname }}" 
# adding sequences
bucardo add all sequences db="{{ .dbname }}" relgroup="{{ .dbname }}" 

{{- end }}

# adding syncs
{{- range .Values.bucardo.syncs }}
{{- $relgroup := index .sources 0 }}
{{- $sources := "" }}
{{- $targets := "" }}

{{- range .sources }}
{{- $sources = printf "%s:source,%s" . $sources | trimAll "," }}
{{- end }}

{{- range .targets }}
{{- $targets = printf "%s:target,%s" . $targets | trimAll "," }}
{{- end }}

{{- $dbs := printf "%s,%s" $sources $targets }}
bucardo add sync {{ .name }} relgroup="{{ $relgroup }}" dbs={{ $dbs }} onetimecopy={{ .onetimecopy }} 
{{- end }}

# start bucardo
bucardo start

# print status
while [ true ]; do
bucardo status 
sleep 15
done
