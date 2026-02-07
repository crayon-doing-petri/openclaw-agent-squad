# Setup Guide — Agent Squad Pattern

## Prerequisites

1. **OpenClaw installed and running**
   ```bash
   openclaw gateway status
   ```

2. **Tools installed**
   ```bash
   # macOS
   brew install yq jq
   
   # Ubuntu/Debian
   sudo apt-get install yq jq
   ```

3. **1Password CLI configured** (for secrets)
   ```bash
   op whoami
   ```

## Quick Start

```bash
# 1. Clone the pattern repo (keep as reference for updates)
git clone https://github.com/crayon-doing-petri/openclaw-agent-squad.git
cd openclaw-agent-squad

# 2. Copy to your new squad directory
cp -r ./ ~/Projects/my-marketing-squad

# 3. Enter your squad and initialize it
cd ~/Projects/my-marketing-squad
git init
git add . && git commit -m "init: my marketing squad"

# 4. Create your squad configuration
cp squad.yaml.example squad.yaml

# 5. Edit squad.yaml with your agents, roles, schedules
#    See squad.yaml.example for reference

# 6. Deploy
./deploy.sh

# 7. Start your backend (choose one):
#    For Convex: cd shared-state/convex && npx convex dev
#    For SQLite: cd shared-state/sqlite && ./init.sh
#    For Filesystem: (no setup needed)

# 8. Verify crons are installed
openclaw cron list

# 9. Start notification daemon (optional, for @mentions)
#    tmux new-session -d -s notifications "./tools/notify.sh"
```

## Configuration Reference

### squad.yaml Structure

```yaml
squad:
  name: "Your Squad Name"
  backend:
    type: "convex" | "sqlite" | "filesystem"
  heartbeat_interval: 15  # minutes
  standup:
    enabled: true
    cron: "30 23 * * *"     # Daily at 11:30 PM
    channel: "telegram"
  notifications:
    enabled: true
    poll_interval_seconds: 30

agents:
  - name: "unique-id"       # machine name (no spaces)
    display_name: "Name"    # human name
    role: "squad-lead"      # for session key
    template: "squad-lead"  # which SOUL template
    schedule: "*/15 * * * *" # cron expression
    description: "What they do"
    specialty: "Specific focus area"
    style: "Voice/personality notes"
```

### Schedule Format (Cron)

Stagger agents so they don't all wake at once:

```
Every 15 minutes:
  */15 * * * *     → :00, :15, :30, :45
  2-59/15 * * * *  → :02, :17, :32, :47
  4-59/15 * * * *  → :04, :19, :34, :49
  6-59/15 * * * *  → :06, :21, :36, :51
  8-59/15 * * * *  → :08, :23, :38, :53
```

### Backend Options

| Backend | Best For | Setup Complexity | Cost |
|---------|----------|------------------|------|
| **Convex** | Production, real-time sync | Medium | Generous free tier |
| **SQLite** | Single-machine, simple | Low | Free |
| **Filesystem** | Minimal setup, debugging | Lowest | Free |

**Recommendation:** Start with SQLite for testing, migrate to Convex for production.

## Operating Your Squad

### Daily Workflow

1. **Morning**: Check Telegram for standup report
2. **Throughout day**: Chat with squad lead (Jarvis) for direct requests
3. **Agents wake**: Every 15 min, check for work, do it, go back to sleep
4. **Evening**: Review deliverables in shared state

### Managing Tasks

**Via Convex:**
```bash
# List inbox
npx convex run tasks:list --watch

# Create task
npx convex run tasks:create '{"title": "Blog post", "description": "...", "status": "inbox"}'

# Assign to agent
npx convex run tasks:assign '{"taskId": "...", "agentId": "..."}'
```

**Via Sqlite:**
```bash
sqlite3 shared-state/sqlite/squad.db
> INSERT INTO tasks (id, title, description, status) VALUES ('t1', '...', '...', 'inbox');
> INSERT INTO task_assignees (task_id, agent_id) VALUES ('t1', 'agent:content-writer:loki');
```

### Adding a New Agent

1. Edit `squad.yaml`
2. Add new agent entry with unique name, offset schedule
3. Create new template if needed (or use existing)
4. Re-run `./deploy.sh`
5. New agent will start checking in on schedule

### Removing an Agent

1. Edit `squad.yaml`, remove agent entry
2. Run `openclaw cron remove --id "{agent-name}-heartbeat"`
3. Optional: Delete `agents/{agent-name}/` directory

### Debugging

**Agent not waking up:**
```bash
# Check cron is installed
openclaw cron list

# Check session exists
openclaw sessions list

# Manually trigger heartbeat
openclaw sessions send --session "agent:{role}:{name}" --message "HEARTBEAT"
```

**OpenClaw not responding:**
```bash
# Start gateway
openclaw gateway start

# Check status
openclaw status
```

**Backend issues:**
```bash
# For Convex, check it's running
npx convex dev

# For SQLite, verify database exists
ls -la shared-state/sqlite/squad.db
```

## Advanced Configuration

### Custom Tools

Add shared tools to `tools/` directory. Agents can run them via shell.

### Custom Templates

Create new `.md` files in `templates/`. Use `{{VARIABLE}}` syntax for substitution.

Available variables:
- `{{DISPLAY_NAME}}` — Agent's display name
- `{{NAME}}` — Agent's machine name
- `{{ROLE}}` — Agent's role
- `{{DESCRIPTION}}` — Agent description
- `{{SPECIALTY}}` — Agent specialty
- `{{STYLE}}` — Style notes
- `{{SQUAD_LEAD_NAME}}` — Name of squad lead agent
- `{{RESEARCHER_NAME}}` — Name of first researcher
- `{{WRITER_NAME}}` — Name of first writer
- `{{SEO_NAME}}` — Name of SEO agent

### Multi-Backend Setup

For advanced setups, you can run different backends for different data types:
- Tasks → Convex (needs real-time)
- Documents → File system (large files)
- Logs → SQLite (local queries)

Edit `AGENTS.md` for each agent to document this.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "yq not found" | Install yq: `brew install yq` or `apt-get install yq` |
| "openclaw not found" | Ensure OpenClaw CLI is in PATH |
| Cron not firing | Check `openclaw gateway status`, verify cron with `openclaw cron list` |
| Agent responding slowly | Check model being used; cheaper models for heartbeats |
| Notifications not working | Ensure notification daemon is running (`tools/notify.sh`) |
| Agents forget tasks | Check `WORKING.md` is being written on every wake |

## Security Notes

- SOUL files contain personality, not secrets
- Store API keys in 1Password, referenced via `op://` in env
- Backend credentials should not be committed (see .gitignore)
- Agent sessions are isolated; they can't see each other's session memory
- Shared state is the only collaboration point

## Next Steps

- Read `README.md` for architecture overview
- Customize templates for your domain
- Build domain-specific tools in `tools/`
- Consider adding a web UI for Mission Control visibility

---
Questions? The pattern is based on [Bhanu Teja's Mission Control](https://x.com/pbteja1998/status/2017662163540971756).
