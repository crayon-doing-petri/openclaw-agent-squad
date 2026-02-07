#!/bin/bash
# Run Discord Bridge as daemon or one-shot

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_PATH="${DB_PATH:-$SCRIPT_DIR/../shared-state/sqlite/squad.db}"
CHANNEL="${DISCORD_CHANNEL:-agent-squad}"
MODE="${1:-daemon}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[BRIDGE]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

check_deps() {
    if ! command -v python3 &> /dev/null; then
        echo "Error: python3 required"
        exit 1
    fi
    
    if [[ ! -f "$DB_PATH" ]]; then
        warn "Database not found at $DB_PATH"
        warn "Run: cd shared-state/sqlite && ./init.sh"
        exit 1
    fi
}

run_once() {
    log "Running bridge one-shot..."
    export SQUAD_DB="$DB_PATH"
    export DISCORD_CHANNEL="$CHANNEL"
    export POLL_INTERVAL="0"
    
    cd "$SCRIPT_DIR"
    python3 bridge.py --once 2>/dev/null || python3 -c "
import sys
sys.path.insert(0, '.')
from bridge import run_bridge_cycle
run_bridge_cycle()
"
}

run_daemon() {
    log "Starting Discord bridge daemon..."
    log "Database: $DB_PATH"
    log "Channel: $CHANNEL"
    log "Press Ctrl+C to stop"
    echo ""
    
    export SQUAD_DB="$DB_PATH"
    export DISCORD_CHANNEL="$CHANNEL"
    export POLL_INTERVAL="30"
    
    cd "$SCRIPT_DIR"
    python3 bridge.py
}

check_deps

case "$MODE" in
    once|oneshot|single)
        run_once
        ;;
    daemon|start|*)
        run_daemon
        ;;
esac
