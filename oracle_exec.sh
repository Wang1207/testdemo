#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: oracle_exec.sh <db_user> <db_password> <db_sid> <sql_file> <work_path>

Arguments:
  db_user      Oracle database user
  db_password  Oracle database password
  db_sid       Oracle SID or service name (TNS alias)
  sql_file     SQL file to execute (DML)
  work_path    Directory for logs and generated SQL
USAGE
}

log() {
  local message="$1"
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$message" | tee -a "$LOG_FILE"
}

validate_args() {
  if [[ $# -ne 5 ]]; then
    usage
    exit 1
  fi
}

ensure_work_path() {
  if [[ ! -d "$WORK_PATH" ]]; then
    mkdir -p "$WORK_PATH"
  fi
}

validate_credentials() {
  log "Validating database credentials for user ${DB_USER}."
  local output
  output=$(sqlplus -s "${DB_USER}/${DB_PASSWORD}@${DB_SID}" <<'SQL'
whenever sqlerror exit sql.sqlcode
set heading off feedback off pagesize 0
select 1 from dual;
exit;
SQL
  )
  if [[ "$output" != "1" ]]; then
    log "Credential validation failed. Output: ${output}"
    return 1
  fi
  log "Credential validation succeeded."
}

create_generated_sql() {
  local generated_file="$WORK_PATH/generated_${DB_USER}_$(date '+%Y%m%d%H%M%S').sql"
  cat <<EOF_SQL > "$generated_file"
-- Generated SQL with global variable usage
DEFINE GLOBAL_SCHEMA = '${GLOBAL_SCHEMA}'

BEGIN
  INSERT INTO &GLOBAL_SCHEMA..audit_log (event_time, event_message)
  VALUES (SYSDATE, 'Generated SQL executed by ${DB_USER}');
END;
/
EOF_SQL
  log "Generated SQL file created at ${generated_file}."
  GENERATED_SQL_FILE="$generated_file"
}

execute_sql_file() {
  local sql_file="$1"
  if [[ ! -f "$sql_file" ]]; then
    log "SQL file not found: ${sql_file}"
    return 1
  fi
  log "Executing SQL file: ${sql_file}"
  sqlplus -s "${DB_USER}/${DB_PASSWORD}@${DB_SID}" <<SQL
whenever sqlerror exit sql.sqlcode rollback
set feedback on echo on
@${sql_file}
commit;
exit;
SQL
  log "SQL execution finished successfully."
}

main() {
  validate_args "$@"

  DB_USER="$1"
  DB_PASSWORD="$2"
  DB_SID="$3"
  INPUT_SQL_FILE="$4"
  WORK_PATH="$5"

  ORACLE_HOME="${ORACLE_HOME:-/opt/oracle/product/19c/dbhome_1}"
  PATH="$ORACLE_HOME/bin:$PATH"
  export ORACLE_HOME PATH

  GLOBAL_SCHEMA="${DB_USER}"
  ensure_work_path
  LOG_FILE="$WORK_PATH/${DB_USER}_$(date '+%Y%m%d%H%M%S').log"
  touch "$LOG_FILE"

  log "Starting Oracle SQL execution script."
  log "ORACLE_HOME=${ORACLE_HOME}"
  log "DB_SID=${DB_SID}"

  validate_credentials
  create_generated_sql

  execute_sql_file "$INPUT_SQL_FILE"
  execute_sql_file "$GENERATED_SQL_FILE"

  log "All SQL files executed successfully."
}

main "$@"
