#!/bin/bash
# Agent Squad Management CLI
# Usage: ./manage.sh [add|remove|regenerate|status|reset] [agent-name] [options]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQUAD_FILE="${SQUAD_FILE:-squad.yaml}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[SQUAD]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

# Check deps
check_deps() {
    if ! command -v yq &> /dev/null; then
        error "yq not found. Install: brew install yq or apt-get install yq"
    fi
    if [[ ! -f "$SQUAD_FILE" ]]; then
        error "Squad file not found: $SQUAD_FILE"
    fi
}

# Get next available schedule offset for new agent
get_next_schedule() {
    local base_interval=15
    local max_agents=20
    
    # Find existing agents and their offsets
    local existing_offsets=$(grep -oE "^[0-9]+-59/15" squad.yaml 2>/dev/null | cut -d'-' -f1 | sort -n | uniq || echo "")
    
    if [[ -z "$existing_offsets" ]]; then
        echo "*/15 * * * *"
        return
    fi
    
    # Find next available offset (0, 2, 4, 6... up to 14)
    for offset in 0 2 4 6 8 10 12 14; do
        if ! echo "$existing_offsets" | grep -q "^${offset}$"; then
            if [[ "$offset" -eq 0 ]]; then
                echo "*/15 * * * *"
            else
                echo "${offset}-59/15 * * * *"
            fi
            return
        fi
    done
    
    # If all slots full, use random offset
    local random_offset=$((RANDOM % 14))
    echo "${random_offset}-59/15 * * * *"
}

# Add a new agent to squad.yaml
add_agent() {
    local name=$1
    local role=$2
    local template=$3
    
    if [[ -z "$name" || -z "$role" ]]; then
        echo "Usage: ./manage.sh add <name> <role> [--template <template>] [--specialty <text>] [--desc <text>]"
        echo ""
        echo "Roles: squad-lead, researcher, writer, developer, analyst, designer, marketer, support"
        echo "Templates: squad-lead, researcher, writer, developer, analyst, designer, social-media, support"
        exit 1
    fi
    
    # Check if name already exists
    if yq -e ".agents[] | select(.name == \"$name\")" "$SQUAD_FILE" &>/dev/null; then
        error "Agent '$name' already exists in $SQUAD_FILE"
    fi
    
    # Default values
    template="${template:-$role}"
    display_name="${DISPLAY_NAME:-$(echo "$name" | sed 's/-/ /g' | sed 's/.*/\u&/')}"
    schedule=$(get_next_schedule)
    
    # Interactive prompts if not provided via env
    if [[ -z "$SPECIALTY" ]]; then
        read -p "Specialty/focus area (optional): " specialty
    else
        specialty="$SPECIALTY"
    fi
    
    if [[ -z "$DESCRIPTION" ]]; then
        read -p "Description (optional): " description
    else
        description="$DESCRIPTION"
    fi
    
    # Build agent entry
    local agent_entry="  - name: \"$name\""
    agent_entry="$agent_entry
    display_name: \"$display_name\""
    agent_entry="$agent_entry
    role: \"$role\""
    agent_entry="$agent_entry
    template: \"$template\""
    agent_entry="$agent_entry
    schedule: \"$schedule\""
    
    if [[ -n "$description" ]]; then
        agent_entry="$agent_entry
    description: \"$description\""
    fi
    
    if [[ -n "$specialty" ]]; then
        agent_entry="$agent_entry
    specialty: \"$specialty\""
    fi
    
    # Append to squad.yaml
    echo "$agent_entry" >> "$SQUAD_FILE"
    
    log "Added agent '$name' to $SQUAD_FILE"
    log "Schedule: $schedule"
    log "Run './deploy.sh --agent $name' to deploy"
}

# Remove an agent
remove_agent() {
    local name=$1
    
    if [[ -z "$name" ]]; then
        error "Usage: ./manage.sh remove <agent-name> [--yes]"
    fi
    
    if ! yq -e ".agents[] | select(.name == \"$name\")" "$SQUAD_FILE" &>/dev/null; then
        error "Agent '$name' not found in $SQUAD_FILE"
    fi
    
    if [[ "${CONFIRM:-}" != "yes" ]]; then
        read -p "Remove agent '$name'? (y/N): " confirm
        [[ "$confirm" == "y" || "$confirm" == "Y" ]] || exit 0
    fi
    
    # Remove from squad.yaml
    yq -i "del(.agents[] | select(.name == \"$name\"))" "$SQUAD_FILE"
    
    # Remove cron
    log "Removing cron job..."
    openclaw cron remove --id "${name}-heartbeat" 2>/dev/null || warn "Cron not found or gateway not running"
    
    # Optional: remove agent directory
    if [[ -d "agents/$name" ]]; then
        read -p "Remove agent directory agents/$name/? (y/N): " remove_dir
        if [[ "$remove_dir" == "y" || "$remove_dir" == "Y" ]]; then
            rm -rf "agents/$name"
            log "Removed agents/$name/"
        fi
    fi
    
    log "Agent '$name' removed"
}

# Regenerate single agent's files
regenerate_agent() {
    local name=$1
    
    if [[ -z "$name" ]]; then
        error "Usage: ./manage.sh regenerate <agent-name>"
    fi
    
    if ! yq -e ".agents[] | select(.name == \"$name\")" "$SQUAD_FILE" &>/dev/null; then
        error "Agent '$name' not found in $SQUAD_FILE"
    fi
    
    log "Regenerating agent: $name"
    
    # Backup existing memory
    if [[ -d "agents/$name/memory" ]]; then
        local backup_dir="agents/${name}/.backup-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$backup_dir"
        cp -r "agents/$name/memory/" "$backup_dir/"
        log "  Backed up memory to $backup_dir/"
    fi
    
    # Regenerate via deploy script
    ./deploy.sh --agent "$name"
    
    log "Regeneration complete"
}

# Show squad status
show_status() {
    log "Squad Status"
    echo ""
    
    # Show squad info
    local squad_name=$(yq -r '.squad.name' "$SQUAD_FILE")
    local backend=$(yq -r '.squad.backend.type' "$SQUAD_FILE")
    local agent_count=$(yq -r '.agents | length' "$SQUAD_FILE")
    
    echo "Squad: $squad_name"
    echo "Backend: $backend"
    echo "Agents: $agent_count"
    echo ""
    
    # List agents
    echo "Agents:"
    echo "--------"
    
    for i in $(seq 0 $((agent_count - 1))); do
        local name=$(yq -r ".agents[$i].name" "$SQUAD_FILE")
        local display=$(yq -r ".agents[$i].display_name" "$SQUAD_FILE")
        local role=$(yq -r ".agents[$i].role" "$SQUAD_FILE")
        local schedule=$(yq -r ".agents[$i].schedule" "$SQUAD_FILE")
        
        # Check if deployed
        if [[ -d "agents/$name" ]]; then
            local status="${GREEN}✓${NC} deployed"
        else
            local status="${YELLOW}○${NC} not deployed"
        fi
        
        # Check cron
        local cron_status=""
        if openclaw cron list 2>/dev/null | grep -q "${name}-heartbeat"; then
            cron_status="${GREEN}●${NC}"
        else
            cron_status="${RED}○${NC}"
        fi
        
        printf "  %-12s %-20s (%s) %s cron:%s\n" "$name" "$display" "$role" "$status" "$cron_status"
        echo "     Schedule: $schedule"
    done
    
    echo ""
    
    # Show crons if available
    if command -v openclaw &> /dev/null; then
        echo "OpenClaw Crons:"
        openclaw cron list 2>/dev/null | grep -E "(NAME|heartbeat)" || echo "  (no agent crons found)"
    fi
}

# Clone/modify an existing agent
clone_agent() {
    local source_name=$1
    local new_name=$2
    
    if [[ -z "$source_name" || -z "$new_name" ]]; then
        error "Usage: ./manage.sh clone <source-agent> <new-name>"
    fi
    
    # Get source agent config
    local source_idx=$(yq -r ".agents | map(.name == \"$source_name\") | index(true)" "$SQUAD_FILE")
    if [[ "$source_idx" == "null" ]]; then
        error "Source agent '$source_name' not found"
    fi
    
    # Check new name doesn't exist
    if yq -e ".agents[] | select(.name == \"$new_name\")" "$SQUAD_FILE" &>/dev/null; then
        error "Agent '$new_name' already exists"
    fi
    
    # Get new schedule
    local schedule=$(get_next_schedule)
    
    # Copy agent entry with new name and schedule
    yq -i ".agents += [.agents[$source_idx] | .name = \"$new_name\" | .schedule = \"$schedule\" | .display_name = \"$new_name\"]" "$SQUAD_FILE"
    
    log "Cloned '$source_name' → '$new_name'"
    log "Schedule: $schedule"
    log "Edit squad.yaml to customize, then run './deploy.sh --agent $new_name'"
}

# Interactive wizard for adding an agent
wizard_add() {
    log "Agent Creation Wizard"
    echo ""
    
    read -p "Agent name (lowercase, no spaces): " name
    [[ -z "$name" ]] && error "Name is required"
    
    # Check exists
    if yq -e ".agents[] | select(.name == \"$name\")" "$SQUAD_FILE" &>/dev/null; then
        error "Agent '$name' already exists"
    fi
    
    echo ""
    echo "Select role:"
    echo "  1) squad-lead    - Coordinator, delegates tasks"
    echo "  2) researcher    - Deep research, provides sources"
    echo "  3) writer        - Content creation, copywriting"
    echo "  4) developer     - Code, automation, scripts"
    echo "  5) analyst       - Data analysis, reporting"
    echo "  6) designer      - Visual design, UI/UX"
    echo "  7) marketer      - Social media, growth"
    echo "  8) support       - Customer support, documentation"
    read -p "Role (1-8): " role_num
    
    case "$role_num" in
        1) role="squad-lead"; template="squad-lead" ;;
        2) role="researcher"; template="researcher" ;;
        3) role="writer"; template="writer" ;;
        4) role="developer"; template="developer" ;;
        5) role="analyst"; template="analyst" ;;
        6) role="designer"; template="designer" ;;
        7) role="marketer"; template="social-media" ;;
        8) role="support"; template="support" ;;
        *) error "Invalid role number" ;;
    esac
    
    read -p "Display name [$name]: " display_name
    display_name="${display_name:-$name}"
    
    read -p "Description: " description
    read -p "Specialty/focus: " specialty
    
    # Get schedule
    local schedule=$(get_next_schedule)
    
    # Build entry
    local agent_entry="  - name: \"$name\""
    agent_entry="$agent_entry
    display_name: \"$display_name\""
    agent_entry="$agent_entry
    role: \"$role\""
    agent_entry="$agent_entry
    template: \"$template\""
    agent_entry="$agent_entry
    schedule: \"$schedule\""
    
    [[ -n "$description" ]] && agent_entry="$agent_entry
    description: \"$description\""
    [[ -n "$specialty" ]] && agent_entry="$agent_entry
    specialty: \"$specialty\""
    
    # Add to squad.yaml
    echo "" >> "$SQUAD_FILE"
    echo "$agent_entry" >> "$SQUAD_FILE"
    
    log ""
    log "Agent '$name' added!"
    log "Next step: ./deploy.sh --agent $name"
}

# Full reset (careful!)
reset_all() {
    if [[ "${CONFIRM:-}" != "yes" ]]; then
        warn "This will remove ALL agent crons and optionally ALL agent directories"
        read -p "Are you sure? Type 'yes' to confirm: " confirm
        [[ "$confirm" == "yes" ]] || exit 0
    fi
    
    log "Removing all agent crons..."
    
    # Get all agent names
    local agent_count=$(yq -r '.agents | length' "$SQUAD_FILE")
    for i in $(seq 0 $((agent_count - 1))); do
        local name=$(yq -r ".agents[$i].name" "$SQUAD_FILE")
        openclaw cron remove --id "${name}-heartbeat" 2>/dev/null || true
    done
    
    # Remove standup cron
    openclaw cron remove --id "daily-standup" 2>/dev/null || true
    
    # Optional: remove directories
    read -p "Remove all agent directories in agents/? (y/N): " remove_dirs
    if [[ "$remove_dirs" == "y" || "$remove_dirs" == "Y" ]]; then
        rm -rf agents/*
        log "Removed all agent directories"
    fi
    
    log "Reset complete. Run './deploy.sh' to redeploy."
}

# Show help
show_help() {
    cat << 'EOF'
Agent Squad Manager

USAGE:
  ./manage.sh <command> [options]

COMMANDS:
  add <name> <role>       Add new agent to squad.yaml
                          Options: --template <t>, --specialty <s>, --desc <d>
  
  remove <name>           Remove agent from squad.yaml and crons
                          Options: --yes (skip confirmation)
  
  clone <src> <new>       Clone existing agent config with new name
  
  regenerate <name>       Regenerate an agent's files (keep memory)
  
  status                  Show squad status and deployment state
  
  wizard                  Interactive agent creation
  
  reset                   Remove ALL crons and optionally directories
                          Options: --yes (dangerous!)

EXAMPLES:
  # Add a new researcher
  ./manage.sh add scout researcher --specialty "competitive intel"

  # Add with all options
  ./manage.sh add ghost writer --template writer --desc "Ghost writer for blog" --specialty "SEO long-form"

  # Remove an agent
  ./manage.sh remove scout --yes

  # Clone and modify
  ./manage.sh clone jarvis jarvis-2
  
  # Check everything is deployed
  ./manage.sh status

  # Interactive wizard
  ./manage.sh wizard

ENV VARIABLES:
  SQUAD_FILE              Path to squad.yaml (default: ./squad.yaml)
  DISPLAY_NAME            Override display name for 'add' command
  SPECIALTY               Set specialty for 'add' command
  DESCRIPTION             Set description for 'add' command
  CONFIRM=yes             Skip confirmations (for scripts)
EOF
}

# Parse global args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --yes)
            CONFIRM="yes"
            shift
            ;;
        --template)
            TEMPLATE="$2"
            shift 2
            ;;
        --specialty)
            SPECIALTY="$2"
            shift 2
            ;;
        --desc|--description)
            DESCRIPTION="$2"
            shift 2
            ;;
        -h|--help|help)
            show_help
            exit 0
            ;;
        *)
            break
            ;;
    esac
done

# Main command dispatch
case "${1:-}" in
    add)
        check_deps
        add_agent "$2" "$3"
        ;;
    remove)
        check_deps
        remove_agent "$2"
        ;;
    clone)
        check_deps
        clone_agent "$2" "$3"
        ;;
    regenerate)
        check_deps
        regenerate_agent "$2"
        ;;
    status)
        check_deps
        show_status
        ;;
    wizard)
        check_deps
        wizard_add
        ;;
    reset)
        check_deps
        reset_all
        ;;
    *)
        show_help
        exit 1
        ;;
esac
