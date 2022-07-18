#!/usr/bin/env bash
#set -e

# This script has benn generated automatically 
{{- $fix := .Values.bucardo.fixMissingPrimaryKey.enabled }}
{{- $clean := .Values.bucardo.cleanTargetsDbs }}
{{- $primaryKey := $.Values.bucardo.fixMissingPrimaryKey.primaryKey | default "__pk__"}}

# pgpass file
export PGPASSFILE=/media/bucardo/.pgpass
function clean() {
  bucardo stop "Exit" 

  # delete bucardo schema in all databases
  # delete temporary primarykey added column
  {{- range concat .Values.bucardo.sources .Values.bucardo.targets }}
  psql --host "{{ .dbhost }}" -U "{{ .dbuser }}" -d "{{ .dbname }}" -At <<EOF
    DROP SCHEMA IF EXISTS bucardo CASCADE;

    do $$ 
    declare
      r record;
    begin
      FOR r in (select tbl.table_schema ts, 
              tbl.table_name tn
        from information_schema.tables tbl
        where table_type = 'BASE TABLE'
          and table_schema not in ('pg_catalog', 'information_schema', 'bucardo')
          and exists (select 1 
                          from information_schema.key_column_usage kcu
                          where kcu.table_name = tbl.table_name 
                            and kcu.table_schema = tbl.table_schema
                            and lower(kcu.column_name) = lower('{{ $primaryKey }}'))) LOOP
      
        
      raise notice 'alter table % drop column {{ $primaryKey }}', r.tn;
      end LOOP;
    end; $$
EOF
  {{- end }}

}

bucardo set log_level=debug

trap "clean" EXIT

echo "[i] clean bucardo previous init"
{{- range concat .Values.bucardo.sources .Values.bucardo.targets }}
psql --host "{{ .dbhost }}" -U "{{ .dbuser }}" -d "{{ .dbname }}" -At <<EOF > /dev/null
  DROP SCHEMA IF EXISTS bucardo CASCADE;
EOF
{{- end }}

{{- range concat .Values.bucardo.targets }}
{{- if $clean }}
psql --host "{{ .dbhost }}" -U "{{ .dbuser }}" -d "{{ .dbname }}" -At <<EOF > /dev/null

  

EOF
{{- end }}


{{- range concat .Values.bucardo.sources .Values.bucardo.targets }}

{{- if $fix }}
# try to fix tables with missing primary key
echo "[i] try to fix tables with missing primary key on db {{ .dbname }}"
T_TABLES=($(psql -v ON_ERROR_STOP=1 --host "{{ .dbhost }}" -U "{{ .dbuser }}" -d "{{ .dbname }}" -At --csv <<EOF | awk -F, '{print "\"" $1 "\"" "." $2}' 
  select tbl.table_schema, 
        tbl.table_name
  from information_schema.tables tbl
  where table_type = 'BASE TABLE'
    and table_schema not in ('pg_catalog', 'information_schema', 'bucardo')
    and not exists (select 1 
                    from information_schema.key_column_usage kcu
                    where kcu.table_name = tbl.table_name 
                      and kcu.table_schema = tbl.table_schema)
EOF
))

for i in "${T_TABLES[@]}"; do
  echo "add primary key {{ $primaryKey }} to table [$i] in database [{{ .dbname }}]"
  psql -v ON_ERROR_STOP=1 --host "{{ .dbhost }}" -U "{{ .dbuser }}" -d "{{ .dbname }}" -At <<EOF
    ALTER TABLE $i ADD COLUMN {{ $primaryKey }} SERIAL PRIMARY KEY;
EOF

done

{{- end }}

# adding databases
echo "[i] adding database {{ .dbname }} to bucardo"
bucardo add database {{ .name }}  dbname="{{ .dbname }}" host="{{ .dbhost }}" user="{{ .dbuser }}" pass="{{ .dbpass }}" 
#bucardo add all tables db="{{ .name }}" relgroup="{{ .name }}" --verbose
#bucardo add all sequences db="{{ .name }}" relgroup="{{ .name }}"
{{- end }} 

 
# adding tables and sequences for sources database
{{- range concat .Values.bucardo.sources }}
# adding tables 
echo "[i] adding all tables from {{ .name }} to bucardo"
bucardo add all tables db="{{ .name }}" relgroup="{{ .name }}" 
# adding sequences
#echo "[i] adding all sequences from {{ .name }} to bucardo"
#bucardo add all sequences db="{{ .name }}" relgroup="{{ .name }}"

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
bucardo add sync {{ .name }} relgroup="{{ $relgroup }}" dbs={{ $dbs }} status=active onetimecopy={{ .onetimecopy }} conflict_strategy=bucardo_source strict_checking=false
{{- end }}

# start bucardo
bucardo start 

tail -f /var/log/bucardo/log.bucardo

# print status
# while [ true ]; do
# {{- range .Values.bucardo.syncs }}
# echo -e "\n----  LOG ----\n"
# tail /var/log/bucardo/log.bucardo
# echo -e "--- STATUS ---\n"
# bucardo status
# {{- end }}
# sleep 5
# done
