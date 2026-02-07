#!/bin/bash
# Deploy Agent Squad
# Usage: ./deploy.sh [squad.yaml]

set -e

SQUAD_FILE="${1:-squad.yaml}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[DEPLOY]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Check dependencies
check_deps() {
    log "Checking dependencies..."
    
    if ! command -v openclaw &> /dev/null; then
        error "openclaw CLI not found. Install it first."
    fi
    
    if ! command -v yq &> /dev/null; then
        warn "yq not found. Install with: brew install yq or apt-get install yq"
        error "yq is required to parse squad.yaml"
    fi
    
    log "Dependencies OK"
}

# Parse squad.yaml and create agent configs
parse_squad() {
    log "Parsing $SQUAD_FILE..."
    
    if [[ ! -f "$SQUAD_FILE" ]]; then
        error "Squad file not found: $SQUAD_FILE"
        copy squad.yaml.example squad.yaml and customize first"
    fi
    
    # Extract squad metadata
    SQUAD_NAME=$(yq -r '.squad.name' "$SQUAD_FILE")
    BACKEND_TYPE=$(yq -r '.squad.backend.type' "$SQUAD_FILE")
    HEARTBEAT_INTERVAL=$(yq -r '.squad.heartbeat_interval' "$SQUAD_FILE")
    
    log "Squad: $SQUAD_NAME"
    log "Backend: $BACKEND_TYPE"
    log "Heartbeat: ${HEARTBEAT_INTERVAL}min"
}

# Generate agent directory structure
generate_agents() {
    log "Generating agent configurations..."
    
    # Read agents array
    AGENT_COUNT=$(yq -r '.agents | length' "$SQUAD_FILE")
    
    for ((i=0; i<AGENT_COUNT; i++)); do
        NAME=$(yq -r ".agents[$i].name" "$SQUAD_FILE")
        ROLE=$(yq -r ".agents[$i].role" "$SQUAD_FILE")
        TEMPLATE=$(yq -r ".agents[$i].template" "$SQUAD_FILE")
        SCHEDULE=$(yq -r ".agents[$i].schedule" "$SQUAD_FILE")
        
        log "Creating agent: $NAME ($ROLE)"
        
        # Create agent directory
        mkdir -p "agents/$NAME"
        
        # Generate SOUL.md from template
        generate_soul "$NAME" "$ROLE" "$TEMPLATE" "$i"
        
        # Generate AGENTS.md (operating manual)
        generate_agents_manual "$NAME" "$ROLE" "$BACKEND_TYPE"
        
        # Generate cron script
        generate_cron "$NAME" "$SCHEDULE"
        
        # Create workspace structure
        mkdir -p "agents/$NAME/memory"
        mkdir -p "agents/$NAME/tools"
        touch "agents/$NAME/memory/.gitkeep"
    done
    
    log "Generated $AGENT_COUNT agents"
}

# Generate SOUL.md from template
generate_soul() {
    local name=$1
    local role=$2
    local template=$3
    local index=$4
    
    local template_file="templates/${template}.md"
    local soul_file="agents/${name}/SOUL.md"
    
    if [[ ! -f "$template_file" ]]; then
        warn "Template not found: $template_file, using default"
        template_file="templates/researcher.md"
    fi
    
    # Read agent details from squad.yaml
    DISPLAY_NAME=$(yq -r ".agents[$index].display_name" "$SQUAD_FILE")
    DESCRIPTION=$(yq -r ".agents[$index].description" "$SQUAD_FILE")
    SPECIALTY=$(yq -r ".agents[$index].specialty // empty" "$SQUAD_FILE")
    STYLE=$(yq -r ".agents[$index].style // empty" "$SQUAD_FILE")
    
    # Get squad lead name for references
    SQUAD_LEAD=$(yq -r '.agents[] | select(.role == "squad-lead") | .display_name' "$SQUAD_FILE" | head -1)
    RESEARCHER=$(yq -r '.agents[] | select(.role | contains("research")) | .display_name' "$SQUAD_FILE" | head -1)
    WRITER=$(yq -r '.agents[] | select(.role | contains("writer")) | .display_name' "$SQUAD_FILE" | head -1)
    SEO=$(yq -r '.agents[] | select(.role | contains("seo")) | .display_name' "$SQUAD_FILE" | head -1)
    
    # Process template with substitutions
    cat "$template_file" | \
        sed "s/{{DISPLAY_NAME}}/${DISPLAY_NAME}/g" | \
        sed "s/{{NAME}}/${name}/g" | \
        sed "s/{{ROLE}}/${role}/g" | \
        sed "s/{{ROLE_DISPLAY}}/${role}/g" | \
        sed "s/{{DESCRIPTION}}/${DESCRIPTION}/g" | \
        sed "s/{{SPECIALTY}}/${SPECIALTY}/g" | \
        sed "s/{{STYLE}}/${STYLE}/g" | \
        sed "s/{{SQUAD_LEAD_NAME}}/${SQUAD_LEAD}/g" | \
        sed "s/{{RESEARCHER_NAME}}/${RESEARCHER}/g" | \
        sed "s/{{WRITER_NAME}}/${WRITER}/g" | \
        sed "s/{{SEO_NAME}}/${SEO}/g" | \
        sed "s/{{ROLE_DESCRIPTION}}/${DESCRIPTION}/g" | \
        sed "s/{{ROLE_CAPABILITIES}}/- ${SPECIALTY}/g" \
        > "$soul_file"
    
    log "  Created SOUL.md for $DISPLAY_NAME"
}

# Generate AGENTS.md operating manual
generate_agents_manual() {
    local name=$1
    local role=$2
    local backend=$3
    
    local agents_file="agents/${name}/AGENTS.md"
    
    cat > "$agents_file" << EOF
# AGENTS.md — Operating Manual

## Your Environment

### Session Key
\`agent:${role}:${name}\`

### Workspace
\`agents/${name}/\`

### Memory Files
- \`memory/WORKING.md\` — Current task state (READ ON EVERY WAKE)
- \`memory/YYYY-MM-DD.md\` — Daily notes
- \`memory/MEMORY.md\` — Long-term curated knowledge

### Backend
Type: ${backend}

EOF

    # Add backend-specific instructions
    case "$backend" in
        convex)
            cat >> "$agents_file" << EOF
Access via Convex CLI:
\`\`\`bash
npx convex run tasks:list
npx convex run messages:create '{"taskId": "...", "content": "..."}'
npx convex run tasks:update '{"id": "...", "status": "..."}'
\`\`\`
EOF
            ;;
        sqlite)
            cat >> "$agents_file" << EOF
Access via SQLite:
\`\`\`bash
sqlite3 shared-state/squad.db "SELECT * FROM tasks WHERE status='inbox'"
\`\`\`
EOF
            ;;
        postgres|postgresql)
            cat >> "$agents_file" << EOF
Access via PostgreSQL:
\`\`\`bash
# Interactive
psql -h \$PG_HOST -U \$PG_USER -d agent_squad

# Single query
psql -h \$PG_HOST -U \$PG_USER -d agent_squad -c "SELECT * FROM tasks WHERE status='inbox'"

# Or use the helper
cd shared-state/postgres && ./query.sh "SELECT * FROM tasks WHERE status='inbox'"
\`\`\`
EOF
            ;;
        filesystem)
            cat >> "$agents_file" << EOF
Access via filesystem:
\`\`\`bash
ls shared-state/fs/tasks/
cat shared-state/fs/tasks/task-001.json
\`\`\`
EOF
            ;;
    esac

    cat >> "$agents_file" << EOF

## Your Schedule

You wake via cron job: \`${SCHEDULE}\`

On wake:
1. Read \`memory/WORKING.md\`
2. Check shared state for @mentions and assigned tasks
3. Resume work or report HEARTBEAT_OK

## Communication

- @mentions: You get notified of @yourname in task threads
- Thread subscriptions: Auto-subscribed to tasks you comment on
- Standup: Daily summary compiled by Squad Lead

## When to Speak vs. Stay Silent

**Respond when:**
- Directly @mentioned
- Assigned to a task
- You have genuine value to add

**Stay silent (HEARTBEAT_OK) when:**
- Nothing needs your attention
- Another agent already handled it
- Your response would be "nice" or "agreed"

## Task Lifecycle

1. **Inbox** → Available, not started
2. **Assigned** → Has owner, ready to start
3. **In Progress** → You're working on it
4. **Review** → Done, awaiting approval
5. **Done** → Complete
6. **Blocked** → Stuck, needs something

## Golden Rules

1. **Write to remember** — Mental notes don't survive restarts
2. **Update WORKING.md** — Always record what you're doing
3. **Post progress** — Keep task threads updated
4. **Ask if stuck** — Better than going silent
5. **Link everything** — Sources, files, commands

---
Generated by agent-squad-pattern deploy.sh
EOF

    log "  Created AGENTS.md for $name"
}

# Generate cron script for an agent
generate_cron() {
    local name=$1
    local schedule=$2
    
    local cron_file="agents/${name}/cron.sh"
    
    cat > "$cron_file" << 'EOF'
#!/bin/bash
# Cron job for agent: {{AGENT_NAME}}
# Schedule: {{SCHEDULE}}

source ~/.op_service_account_token 2>/dev/null || true

# Run heartbeat
openclaw sessions send \
    --session "agent:{{ROLE}}:{{AGENT_NAME}}" \
    --message "HEARTBEAT: Check Mission Control for assigned tasks, @mentions, and activity. If nothing needs attention, reply HEARTBEAT_OK."
EOF

    sed -i "s/{{AGENT_NAME}}/${name}/g" "$cron_file"
    sed -i "s/{{SCHEDULE}}/${schedule}/g" "$cron_file"
    sed -i "s/{{ROLE}}/${role}/g" "$cron_file"
    
    chmod +x "$cron_file"
    log "  Created cron.sh for $name"
}

# Setup shared state backend
setup_backend() {
    log "Setting up $BACKEND_TYPE backend..."
    
    case "$BACKEND_TYPE" in
        convex)
            setup_convex
            ;;
        sqlite)
            setup_sqlite
            ;;
        postgres|postgresql)
            setup_postgres
            ;;
        filesystem)
            setup_filesystem
            ;;
        *)
            warn "Unknown backend: $BACKEND_TYPE"
            ;;
    esac
}

setup_convex() {
    log "Initializing Convex backend..."
    
    mkdir -p shared-state/convex
    
    # Create schema.ts
    cat > shared-state/convex/schema.ts << 'EOF'
import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

export default defineSchema({
  agents: defineTable({
    name: v.string(),
    role: v.string(),
    status: v.union(v.literal("idle"), v.literal("active"), v.literal("blocked")),
    currentTaskId: v.optional(v.id("tasks")),
    sessionKey: v.string(),
  }),
  
  tasks: defineTable({
    title: v.string(),
    description: v.string(),
    status: v.union(
      v.literal("inbox"),
      v.literal("assigned"),
      v.literal("in_progress"),
      v.literal("review"),
      v.literal("done")
    ),
    assigneeIds: v.array(v.id("agents")),
    createdAt: v.number(),
    updatedAt: v.number(),
  }),
  
  messages: defineTable({
    taskId: v.id("tasks"),
    fromAgentId: v.id("agents"),
    content: v.string(),
    createdAt: v.number(),
  }),
  
  activities: defineTable({
    type: v.string(),
    agentId: v.id("agents"),
    message: v.string(),
    createdAt: v.number(),
  }),
  
  notifications: defineTable({
    mentionedAgentId: v.id("agents"),
    content: v.string(),
    delivered: v.boolean(),
    createdAt: v.number(),
  }),
});
EOF

    # Create package.json for Convex
    cat > shared-state/convex/package.json << 'EOF'
{
  "name": "agent-squad-convex",
  "version": "1.0.0",
  "dependencies": {
    "convex": "^1.0.0"
  }
}
EOF

    log "  Convex schema created"
    log "  Run 'cd shared-state/convex && npx convex dev' to start"
}

setup_sqlite() {
    log "Setting up SQLite backend..."
    
    mkdir -p shared-state/sqlite
    
    cat > shared-state/sqlite/init.sql << 'EOF'
CREATE TABLE IF NOT EXISTS agents (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    role TEXT NOT NULL,
    status TEXT CHECK(status IN ('idle', 'active', 'blocked')),
    current_task_id TEXT,
    session_key TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS tasks (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    status TEXT CHECK(status IN ('inbox', 'assigned', 'in_progress', 'review', 'done')),
    created_at INTEGER,
    updated_at INTEGER
);

CREATE TABLE IF NOT EXISTS task_assignees (
    task_id TEXT,
    agent_id TEXT,
    PRIMARY KEY (task_id, agent_id)
);

CREATE TABLE IF NOT EXISTS messages (
    id TEXT PRIMARY KEY,
    task_id TEXT NOT NULL,
    from_agent_id TEXT NOT NULL,
    content TEXT NOT NULL,
    created_at INTEGER
);

CREATE TABLE IF NOT EXISTS activities (
    id TEXT PRIMARY KEY,
    type TEXT NOT NULL,
    agent_id TEXT NOT NULL,
    message TEXT NOT NULL,
    created_at INTEGER
);

CREATE TABLE IF NOT EXISTS notifications (
    id TEXT PRIMARY KEY,
    mentioned_agent_id TEXT NOT NULL,
    content TEXT NOT NULL,
    delivered INTEGER DEFAULT 0,
    created_at INTEGER
);
EOF

    # Create init script
    cat > shared-state/sqlite/init.sh << 'EOF'
#!/bin/bash
sqlite3 squad.db < init.sql
echo "Database initialized at squad.db"
EOF
    chmod +x shared-state/sqlite/init.sh

    log "  SQLite schema created"
    log "  Run: cd shared-state/sqlite && ./init.sh"
}

setup_postgres() {
    log "Setting up PostgreSQL backend..."
    
    mkdir -p shared-state/postgres
    
    # Note: Schema already created in repo, just need to apply it
    log "  PostgreSQL schema available in shared-state/postgres/schema.sql"
    log "  Run the following to initialize:"
    log "    cd shared-state/postgres && ./init.sh"
    log ""
    log "  Or with custom credentials:"
    log "    PG_HOST=localhost PG_PORT=5432 PG_DATABASE=agent_squad PG_USER=squad_user ./init.sh"
    log ""
    log "  Query helper available:"
    log "    cd shared-state/postgres && ./query.sh \"SELECT * FROM tasks;\""
}

setup_filesystem() {
    log "Setting up filesystem backend..."
    
    mkdir -p shared-state/fs/{tasks,messages,activities,documents,notifications}
    
    # Create example task file
    cat > shared-state/fs/tasks/example.json << 'EOF'
{
  "id": "task-001",
  "title": "Example Task",
  "description": "This is an example task structure",
  "status": "inbox",
  "assigneeIds": [],
  "createdAt": 1704067200000,
  "updatedAt": 1704067200000
}
EOF

    log "  Filesystem structure created"
}

# Install crons to OpenClaw
install_crons() {
    log "Installing cron jobs to OpenClaw..."
    
    if ! command -v openclaw &> /dev/null; then
        warn "openclaw CLI not available, skipping cron installation"
        return
    fi
    
    # Add agent heartbeats
    AGENT_COUNT=$(yq -r '.agents | length' "$SQUAD_FILE")
    
    for ((i=0; i<AGENT_COUNT; i++)); do
        NAME=$(yq -r ".agents[$i].name" "$SQUAD_FILE")
        ROLE=$(yq -r ".agents[$i].role" "$SQUAD_FILE")
        SCHEDULE=$(yq -r ".agents[$i].schedule" "$SQUAD_FILE")
        
        log "  Installing cron: ${NAME}-heartbeat"
        
        # Remove existing cron if present
        openclaw cron remove --id "${NAME}-heartbeat" 2>/dev/null || true
        
        # Add new cron
        openclaw cron add \
            --name "${NAME}-heartbeat" \
            --cron "$SCHEDULE" \
            --session "isolated" \
            --message "HEARTBEAT: Check shared state for tasks and @mentions. Read agents/${NAME}/memory/WORKING.md. Reply HEARTBEAT_OK if nothing needs attention." \
            2>/dev/null || warn "    Failed to install cron for $NAME (openclaw may not be running)"
    done
    
    # Add standup cron if enabled
    STANDUP_ENABLED=$(yq -r '.squad.standup.enabled' "$SQUAD_FILE")
    if [[ "$STANDUP_ENABLED" == "true" ]]; then
        STANDUP_CRON=$(yq -r '.squad.standup.cron' "$SQUAD_FILE")
        
        log "  Installing cron: daily-standup"
        
        openclaw cron remove --id "daily-standup" 2>/dev/null || true
        
        openclaw cron add \
            --name "daily-standup" \
            --cron "$STANDUP_CRON" \
            --session "isolated" \
            --message "Compile daily standup report from shared state activity. Generate summary and send to configured channel." \
            2>/dev/null || warn "    Failed to install standup cron"
    fi
    
    log "Cron jobs installed"
}

# Create tools
create_tools() {
    log "Creating shared tools..."
    
    # Notify tool for @mentions
    cat > tools/notify.sh << 'EOF'
#!/bin/bash
# Notification daemon for @mentions
# Polls shared state for undelivered notifications

POLL_INTERVAL=30
BACKEND_TYPE="{{BACKEND_TYPE}}"

while true; do
    case "$BACKEND_TYPE" in
        convex)
            # Query undelivered notifications via Convex
            UNDELIVERED=$(npx convex run notifications:getUndelivered 2>/dev/null || echo "[]")
            ;;
        sqlite)
            UNDELIVERED=$(sqlite3 shared-state/squad.db "SELECT id, mentioned_agent_id, content FROM notifications WHERE delivered=0;")
            ;;
        postgres|postgresql)
            UNDELIVERED=$(psql "$DATABASE_URL" -tAc "SELECT id, mentioned_agent_id, content FROM notifications WHERE delivered=false;")
            ;;
        filesystem)
            # Check fs/notifications/ for undelivered
            UNDELIVERED=$(find shared-state/fs/notifications -name "*.json" -exec cat {} \; | jq -r 'select(.delivered==false) | [.id, .mentionedAgentId, .content] | @tsv')
            ;;
    esac
    
    # Deliver each notification
    # TODO: Implement delivery logic
    
    sleep $POLL_INTERVAL
done
EOF

    sed -i "s/{{BACKEND_TYPE}}/${BACKEND_TYPE}/g" tools/notify.sh
    chmod +x tools/notify.sh
    
    # Standup generator
    cat > tools/standup.sh << 'EOF'
#!/bin/bash
# Generate daily standup report

BACKEND_TYPE="{{BACKEND_TYPE}}"
DATE=$(date +%Y-%m-%d)

# Query today's activity
# TODO: Implement query based on backend type

echo "📊 DAILY STANDUP — $DATE"
echo ""
echo "✅ COMPLETED TODAY"
echo "🔄 IN PROGRESS"
echo "🚫 BLOCKED"
echo "👀 NEEDS REVIEW"
EOF

    sed -i "s/{{BACKEND_TYPE}}/${BACKEND_TYPE}/g" tools/standup.sh
    chmod +x tools/standup.sh
    
    log "Tools created in tools/"
}

# Deploy single agent
# Usage: deploy_agent <name>
deploy_single_agent() {
    local name=$1
    
    log "Deploying single agent: $name"
    
    # Find agent index
    local agent_count=$(yq -r '.agents | length' "$SQUAD_FILE")
    local idx="null"
    
    for ((i=0; i<AGENT_COUNT; i++)); do
        local agent_name=$(yq -r ".agents[$i].name" "$SQUAD_FILE")
        if [[ "$agent_name" == "$name" ]]; then
            idx=$i
            break
        fi
    done
    
    if [[ "$idx" == "null" ]]; then
        error "Agent '$name' not found in $SQUAD_FILE"
    fi
    
    local ROLE=$(yq -r ".agents[$idx].role" "$SQUAD_FILE")
    local TEMPLATE=$(yq -r ".agents[$idx].template" "$SQUAD_FILE")
    local SCHEDULE=$(yq -r ".agents[$idx].schedule" "$SQUAD_FILE")
    
    # Create agent directory
    log "Creating agent directory: agents/$name/"
    mkdir -p "agents/$name"
    
    # Generate SOUL.md
    generate_soul "$name" "$ROLE" "$TEMPLATE" "$idx"
    
    # Generate AGENTS.md
    generate_agents_manual "$name" "$ROLE" "$BACKEND_TYPE"
    
    # Generate cron script
    generate_cron "$name" "$SCHEDULE"
    
    # Create workspace structure
    mkdir -p "agents/$name/memory"
    mkdir -p "agents/$name/tools"
    
    # Install single cron
    log "Installing cron job..."
    openclaw cron remove --id "${name}-heartbeat" 2>/dev/null || true
    
    openclaw cron add \
        --name "${name}-heartbeat" \
        --cron "$SCHEDULE" \
        --session "isolated" \
        --message "HEARTBEAT: Check shared state for tasks and @mentions. Read agents/${name}/memory/WORKING.md. Reply HEARTBEAT_OK if nothing needs attention." \
        2>/dev/null || warn "Failed to install cron (openclaw may not be running)"
    
    log "Agent '$name' deployed successfully!"
    log "  Session key: agent:${ROLE}:${name}"
    log "  Schedule: $SCHEDULE"
    log "  Next: Agent will wake on schedule, or run 'openclaw sessions send --session agent:${ROLE}:${name} --message HEARTBEAT' to test"
}

# Main deployment
main() {
    # Handle --agent flag for single agent deploy
    if [[ "$1" == "--agent" && -n "$2" ]]; then
        check_deps
        parse_squad
        deploy_single_agent "$2"
        exit 0
    fi
    
    # Handle --help
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        cat << 'EOF'
Agent Squad Deployment

USAGE:
  ./deploy.sh               Deploy all agents from squad.yaml
  ./deploy.sh --agent NAME  Deploy single agent (for incremental adds)
  ./deploy.sh --help        Show this help

EXAMPLES:
  # First-time setup - deploy entire squad
  ./deploy.sh

  # Add a new agent incrementally
  ./manage.sh add ghost writer --specialty "SEO content"
  ./deploy.sh --agent ghost

  # Regenerate one agent
  ./deploy.sh --agent jarvis

INCREMENTAL WORKFLOW:
  1. Start with 2 agents in squad.yaml
  2. ./deploy.sh
  3. Later: ./manage.sh add researcher3 researcher
  4. ./deploy.sh --agent researcher3
  5. (Old agents untouched, new one joins the squad)

For more control, use ./manage.sh:
  ./manage.sh status    - Check all agents
  ./manage.sh wizard    - Interactive add
  ./manage.sh remove    - Remove an agent
EOF
        exit 0
    fi
    
    echo "================================"
    echo "  Agent Squad Deployment"
    echo "================================"
    echo ""
    
    check_deps
    parse_squad
    
    # Check if incremental or full deploy
    local deployed_count=$(ls -1 agents/ 2>/dev/null | wc -l)
    local squad_count=$(yq -r '.agents | length' "$SQUAD_FILE")
    
    if [[ "$deployed_count" -gt 0 && "$deployed_count" -lt "$squad_count" ]]; then
        warn "Partial deployment detected ($deployed_count of $squad_count agents)"
        warn "Run './manage.sh status' to see what's missing"
        echo ""
        read -p "Continue with full deployment? (Y/n): " confirm
        if [[ "$confirm" == "n" || "$confirm" == "N" ]]; then
            echo "Use './deploy.sh --agent <name>' to deploy specific agents"
            exit 0
        fi
    fi
    
    generate_agents
    setup_backend
    create_tools
    install_crons
    
    echo ""
    echo "================================"
    log "Deployment complete!"
    echo ""
    echo "Next steps:"
    echo "  1. Review generated agents/ directory"
    echo "  2. Set up backend: cd shared-state/${BACKEND_TYPE}/"
    echo "  3. Start OpenClaw gateway if not running"
    echo "  4. Agents will begin checking in on their schedules"
    echo ""
    echo "Management commands:"
    echo "  ./manage.sh status      - Check squad status"
    echo "  ./manage.sh add         - Add a new agent"
    echo "  ./manage.sh wizard      - Interactive agent creation"
    echo "  ./manage.sh remove      - Remove an agent"
    echo ""
}

main "$@"
