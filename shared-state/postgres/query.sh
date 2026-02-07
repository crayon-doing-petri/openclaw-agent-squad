#!/bin/bash
# PostgreSQL query helper for Agent Squad
# Usage: ./query.sh "SELECT * FROM tasks;"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load connection details if available
if [[ -f "$SCRIPT_DIR/.pg_connection" ]]; then
    source "$SCRIPT_DIR/.pg_connection"
fi

# Use env vars or defaults
DB_HOST="${PG_HOST:-localhost}"
DB_PORT="${PG_PORT:-5432}"
DB_NAME="${PG_DATABASE:-agent_squad}"
DB_USER="${PG_USER:-squad_user}"
DB_PASS="${PG_PASSWORD:-}"

# Build connection string
if [[ -n "$DB_PASS" ]]; then
    export PGPASSWORD="$DB_PASS"
fi

CONN="-h $DB_HOST -p $DB_PORT -U $DB_USER"

# Run query
if [[ -n "$1" ]]; then
    psql $CONN -d "$DB_NAME" -c "$1"
else
    # Interactive mode
    psql $CONN -d "$DB_NAME"
fi