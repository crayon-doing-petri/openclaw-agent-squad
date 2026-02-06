# Quick Reference — Agent Squad Pattern

## Common Workflows

### Start Fresh (Empty Squad)

```bash
cd ~/Projects/my-squad

# Edit squad.yaml with your first 2 agents
cp squad.yaml.example squad.yaml
nano squad.yaml  # or use Cursor

# Deploy everything
./deploy.sh

# Start backend (choose one)
cd shared-state/sqlite && ./init.sh     # Simple
cd shared-state/convex && npx convex dev  # Production

# Done! Agents will start waking on their schedules
```

### Add Your First Agent to an Existing Squad

```bash
cd ~/Projects/my-squad

# Method 1: Quick add
./manage.sh add scout researcher --specialty "market scanning"
./deploy.sh --agent scout

# Method 2: Interactive wizard (easier)
./manage.sh wizard
# ...answer prompts...
./deploy.sh --agent <name-from-wizard>
```

### Add 3+ Agents at Once

```bash
# Edit squad.yaml directly, add the agents
nano squad.yaml

# Deploy specific new ones individually
./deploy.sh --agent agent1
./deploy.sh --agent agent2
./deploy.sh --agent agent3

# Or just redeploy all (existing agents won't break)
./deploy.sh
```

### Check What's Running

```bash
./manage.sh status

# Shows:
# - Which agents are configured
# - Which are deployed
# - Which have crons installed
# - Schedules
```

### Remove an Agent

```bash
# Soft remove (keeps files)
./manage.sh remove scout

# Full remove (files too)
./manage.sh remove scout --yes
# ...then confirm directory removal
```

### Clone/Duplicate an Agent

```bash
# Copy config from existing agent
./manage.sh clone jarvis jarvis-backup

# Edit squad.yaml to customize the clone
nano squad.yaml

# Deploy the copy
./deploy.sh --agent jarvis-backup
```

## Template Selection Guide

| Template | Best For | Personality |
|----------|----------|-------------|
| **squad-lead** | Coordinator, manages others | Decisive, delegator |
| **researcher** | Deep research, sources | Skeptical, thorough |
| **analyst** | Data, metrics, validation | Precise, methodological |
| **writer** | Content, copy, long-form | Opinionated about words |
| **developer** | Code, automation, scripts | Pragmatic, clean code |
| **designer** | Visuals, UI/UX, graphics | Visual-first, systematic |
| **social-media** | Social content, growth | Hook-focused, audience-obsessed |
| **support** | Help, docs, user feedback | Empathetic, efficient |

## Schedule Quick Reference

| Expression | Meaning | Use For |
|------------|---------|---------|
| `*/15 * * * *` | Every 15 min (:00, :15, :30, :45) | First agent |
| `2-59/15 * * * *` | Every 15 min, offset +2 | Second agent |
| `4-59/15 * * * *` | Every 15 min, offset +4 | Third agent |
| `8-59/15 * * * *` | Every 15 min, offset +8 | Fifth agent |
| `0 */6 * * *` | Every 6 hours | Batch jobs |
| `30 9 * * *` | 9:30 AM daily | Daily tasks |

New agents automatically get the next available offset via `manage.sh`.

## Backend Selection

| Backend | Setup | Best For |
|---------|-------|----------|
| **SQLite** | `./init.sh` | Testing, single machine |
| **Convex** | `npx convex dev` | Production, real-time |
| **Filesystem** | Nothing | Debugging, minimal setup |

Switch backends in `squad.yaml`:
```yaml
backend:
  type: "sqlite"  # or "convex" or "filesystem"
```

## Emergency Commands

```bash
# Agent not responding?
openclaw sessions list                    # Check session exists
openclaw cron list | grep <agent>         # Check cron exists
openclaw sessions send --session agent:role:name --message "HEARTBEAT"

# Restart everything?
./manage.sh reset --yes                   # Remove all crons
./deploy.sh                               # Redeploy

# Gateway not running?
openclaw gateway start
openclaw gateway status
```

## Troubleshooting

**"Agent not found in squad.yaml"**
→ Check spelling, run `./manage.sh status`

**"Cron not installing"**
→ Is gateway running? `openclaw gateway status`

**"Agent not waking up"**
→ Check schedule: `openclaw cron list`
→ Manually trigger: `openclaw sessions send --session agent:role:name --message test`

**"Backend connection failed"**
→ Is backend running? (SQLite: check db file exists, Convex: check `npx convex dev`)

## Customization Points

1. **Edit template** → Change all agents of that type
2. **Edit SOUL.md** → Change one specific agent
3. **Edit AGENTS.md** → Change operating manual for one agent
4. **Edit squad.yaml** → Add/remove agents, change schedules
5. **Edit deploy.sh** → Change deployment behavior

## Example Squads to Build

**Trading Squad:**
```yaml
agents:
  - name: alpha      # squad-lead
  - name: quant      # researcher + analyst
  - name: builder    # developer  
  - name: writer     # writer (research reports)
```

**Marketing Squad:**
```yaml
agents:
  - name: cm        # squad-lead + social-media
  - name: design    # designer
  - name: content   # writer
  - name: growth    # social-media
  - name: data      # analyst
```

**Product Squad:**
```yaml
agents:
  - name: pm        # squad-lead
  - name: research  # researcher
  - name: design    # designer
  - name: dev       # developer
  - name: qa        # researcher (testing focus)
  - name: docs      # support (documentation)
```

---
Full docs: README.md, SETUP.md
CLI help: ./manage.sh --help, ./deploy.sh --help
