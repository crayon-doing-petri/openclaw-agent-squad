# Agent Squad Pattern

A reusable template for building multi-agent teams with OpenClaw.

Based on the Mission Control architecture by @pbteja1998 (SiteGPT), adapted for OpenClaw.

## Quick Start

```bash
# 1. Clone this pattern
cp -r agent-squad-pattern ~/Projects/my-squad
cd ~/Projects/my-squad

# 2. Configure your squad (edit squad.yaml)
# 3. Deploy agents
./deploy.sh
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

## Directory Structure

```
agent-squad-pattern/
├── README.md                 # This file
├── squad.yaml               # Define your agents here
├── deploy.sh                # One-command deployment
├── agents/                  # Generated agent configs
│   ├── jarvis/
│   │   ├── SOUL.md
│   │   ├── AGENTS.md
│   │   └── cron.sh
│   ├── shuri/
│   └── ...
├── templates/               # Reusable SOUL templates
│   ├── squad-lead.md
│   ├── researcher.md
│   ├── writer.md
│   └── developer.md
├── shared-state/            # Task/message backend
│   ├── convex/             # Recommended: Convex backend
│   ├── sqlite/             # Lightweight file-based
│   └── filesystem/         # Simple file-based
└── tools/                   # Shared utilities
    ├── notify.sh           # @mention notifications
    ├── standup.sh          # Daily standup generator
    └── heartbeat-check.sh  # Agent health monitor
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
