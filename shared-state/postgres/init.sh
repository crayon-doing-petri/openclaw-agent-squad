#!/bin/bash
# Initialize PostgreSQL database for Agent Squad

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[POSTGRES]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Configuration (can be overridden by env vars)
DB_HOST="${PG_HOST:-localhost}"
DB_PORT="${PG_PORT:-5432}"
DB_NAME="${PG_DATABASE:-agent_squad}"
DB_USER="${PG_USER:-squad_user}"
DB_PASS="${PG_PASSWORD:-}"

log "PostgreSQL initialization"
log "Host: $DB_HOST:$DB_PORT"
log "Database: $DB_NAME"
log "User: $DB_USER"

# Check if psql is available
if ! command -v psql &> /dev/null; then
    error "psql not found. Install PostgreSQL client:"
    error "  Ubuntu/Debian: sudo apt-get install postgresql-client"
    error "  macOS: brew install libpq"
fi

# Build connection string
if [[ -n "$DB_PASS" ]]; then
    export PGPASSWORD="$DB_PASS"
    CONN="-h $DB_HOST -p $DB_PORT -U $DB_USER"
else
    # Assume local socket or trust auth
    CONN="-h $DB_HOST -p $DB_PORT"
    DB_USER="${PG_USER:-$(whoami)}"
fi

# Test connection
log "Testing connection..."
if ! psql $CONN -d postgres -c "SELECT 1;" &>/dev/null; then
    error "Cannot connect to PostgreSQL at $DB_HOST:$DB_PORT"
    error "Check that PostgreSQL is running and credentials are correct"
fi

# Check if database exists
log "Checking database..."
DB_EXISTS=$(psql $CONN -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME';" 2>/dev/null || echo "")

if [[ "$DB_EXISTS" == "1" ]]; then
    warn "Database '$DB_NAME' already exists"
    read -p "Drop and recreate? (y/N): " recreate
    if [[ "$recreate" == "y" || "$recreate" == "Y" ]]; then
        log "Dropping existing database..."
        psql $CONN -d postgres -c "DROP DATABASE IF EXISTS $DB_NAME;"
        psql $CONN -d postgres -c "CREATE DATABASE $DB_NAME;"
    else
        log "Using existing database"
    fi
else
    log "Creating database '$DB_NAME'..."
    psql $CONN -d postgres -c "CREATE DATABASE $DB_NAME;"
fi

# Apply schema
log "Applying schema..."
psql $CONN -d "$DB_NAME" -f "$SCRIPT_DIR/schema.sql"

# Verify
log "Verifying tables..."
TABLES=$(psql $CONN -d "$DB_NAME" -tAc "SELECT tablename FROM pg_tables WHERE schemaname='public';")

if echo "$TABLES" | grep -q "agents"; then
    log "✓ Schema applied successfully"
    log "Tables created:"
    echo "$TABLES" | sed 's/^/  - /'
else
    error "Schema application failed"
fi

# Create connection info file for agents
cat > "$SCRIPT_DIR/.pg_connection" << EOF
# PostgreSQL connection details
# Source this file or reference it in your squad.yaml

PG_HOST=$DB_HOST
PG_PORT=$DB_PORT
PG_DATABASE=$DB_NAME
PG_USER=$DB_USER
PG_PASSWORD=$DB_PASS

# Connection string for applications
DATABASE_URL=postgresql://$DB_USER:$DB_PASS@$DB_HOST:$DB_PORT/$DB_NAME
EOF

chmod 600 "$SCRIPT_DIR/.pg_connection"

log ""
log "==================================="
log "PostgreSQL database ready!"
log "==================================="
log ""
log "Update your squad.yaml:"
log "  backend:"
log "    type: postgres"
log "    host: $DB_HOST"
log "    port: $DB_PORT"
log "    database: $DB_NAME"
log "    username: $DB_USER"
log "    password: $DB_PASS"
log ""
log "Connection details saved to:"
log "  $SCRIPT_DIR/.pg_connection"
log ""
