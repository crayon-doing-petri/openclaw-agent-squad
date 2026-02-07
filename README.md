# Agent Squad Pattern

A reusable template for building multi-agent teams with OpenClaw.

Based on the Mission Control architecture by @pbteja1998 (SiteGPT), adapted for OpenClaw.

## Quick Start

```bash
# 1. Clone the pattern repo (keep as reference)
git clone https://github.com/crayon-doing-petri/openclaw-agent-squad.git
cd openclaw-agent-squad

# 2. Copy to your new squad directory
cp -r ./ ~/Projects/my-first-squad

# 3. Enter your squad and initialize it
cd ~/Projects/my-first-squad
git init
git add . && git commit -m "init: my first squad"

# 4. Configure and deploy
cp squad.yaml.example squad.yaml
# ...edit squad.yaml...
./deploy.sh

# 5. Add more agents over time
./manage.sh add researcher2 researcher --specialty "competitive intel"
./deploy.sh --agent researcher2
```

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    OpenClaw Gateway                     │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐       │
│  │ Agent 1 │ │ Agent 2 │ │ Agent 3 │ │ Agent N │       │
│  │ Session │ │ Session │ │ Session │ │ Session │       │
│  │ + SOUL  │ │ + SOUL  │ │ + SOUL  │ │ + SOUL  │       │
│  └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘       │
│       │           │           │           │             │
│       └───────────┴─────┬─────┴───────────┘             │
│                         │                               │
│                    Shared State                         │
│              (Convex / SQLite / Files)                  │
└─────────────────────────────────────────────────────────┘
```

## Incremental Agent Management

Start small, grow as needed:

```bash
# Start with 2 agents
./deploy.sh

# Add 1 agent later
./manage.sh add quant researcher --specialty "BTC/SPX strategies"
./deploy.sh --agent quant

# Add via interactive wizard
./manage.sh wizard

# Check status anytime
./manage.sh status

# Remove an agent
./manage.sh remove quant --yes
```

## Directory Structure

```
agent-squad/
├── README.md                # This file
├── SETUP.md                 # Detailed setup guide
├── squad.yaml              # Define your agents here
├── deploy.sh               # Deploy all or single agent
├── manage.sh               # Add/remove/clone agents
├── agents/                 # Generated agent configs
│   ├── jarvis/
│   │   ├── SOUL.md
│   │   ├── AGENTS.md
│   │   └── memory/
│   └── ...
├── templates/              # 8 SOUL templates
│   ├── squad-lead.md       # Coordinator
│   ├── researcher.md       # Deep research
│   ├── analyst.md          # Data analysis
│   ├── writer.md           # Content creation
│   ├── developer.md        # Code/scripts
│   ├── designer.md         # Visual design
│   ├── social-media.md     # Social/growth
│   └── support.md          # Help/documentation
├── shared-state/           # Backend options
│   ├── convex/
│   ├── sqlite/
│   └── filesystem/
└── tools/                  # Shared utilities
    ├── notify.sh
    └── standup.sh
```

## How It Works

1. **Define agents in `squad.yaml`** — name, role, personality, schedule
2. **Deploy creates:**
   - Individual OpenClaw sessions for each agent
   - Custom SOUL.md for each role (from templates)
   - Staggered cron jobs for heartbeats
   - Shared state backend (Convex recommended)
3. **Agents run on schedule**, check shared state for tasks/messages
4. **Notification daemon** delivers @mentions to sleeping agents
5. **Daily standup** compiles activity and sends summary

## Core Concepts

### Session Keys
Each agent gets a unique session key:
```
agent:{role}:{name}  →  agent:researcher:fury
```

### Heartbeat System
- Agents wake every N minutes via cron
- Check shared state for @mentions, assigned tasks
- Do work or report `HEARTBEAT_OK`
- Go back to sleep (isolated sessions terminate)

### Memory Stack
- **Session memory:** OpenClaw built-in (conversation history)
- **WORKING.md:** Current task state (read on every wake)
- **Daily notes:** Raw logs of activity
- **MEMORY.md:** Long-term curated knowledge

## Next Steps

See `SETUP.md` for detailed installation instructions.

See `squad.yaml.example` for configuration reference.
