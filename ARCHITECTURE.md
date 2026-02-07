# Architecture Guide — Agent Squad Pattern

## The Core Insight: Two Communication Layers

This pattern separates **human communication** from **agent coordination** for reliability and flexibility.

```
┌─────────────────────────────────────────────────────────────────┐
│  HUMAN LAYER (Discord/Telegram)                                 │
│  └── You talk to Squad Lead only                                │
│  └── Squad Lead mirrors key events for transparency             │
└─────────────────────────────────────────────────────────────────┘
                              ↕
┌─────────────────────────────────────────────────────────────────┐
│  SQUAD LEAD (Bridge Agent)                                      │
│  └── Session: agent:squad-lead:alpha                            │
│  └── Reads/writes SQLite (agent coordination)                   │
│  └── Posts to Discord (human transparency)                      │
└─────────────────────────────────────────────────────────────────┘
                              ↕
┌─────────────────────────────────────────────────────────────────┐
│  AGENT COORDINATION LAYER (SQLite/Convex)                       │
│  └── All agents read/write here (source of truth)               │
│  └── Tasks, messages, activities stored here                    │
│  └── Works even if Discord is down                              │
└─────────────────────────────────────────────────────────────────┘
```

**Key principle:** Agents never depend on Discord. Discord is purely for human convenience.

**Key principle for backends:** Agents use standard SQL. SQLite, PostgreSQL, and Convex (with SQL-like queries) all work interchangeably from the agent's perspective.

---

## Communication Flow: Example

### Scenario: You request BTC research

**Step 1 — You (Discord):**
> "@Alpha Research BTC momentum for 90 days"

**Step 2 — Squad Lead (Alpha) receives via Discord:**
- Parses your request
- Writes to SQLite: `INSERT INTO tasks (title, status) VALUES ('BTC momentum research', 'inbox')`
- Assigns to Scout (researcher)
- Posts to Discord: "📋 Created task #7, assigned to Scout"

**Step 3 — Scout wakes (next :02 heartbeat):**
- Queries SQLite: `SELECT * FROM tasks WHERE assigned_to_me`
- Finds task #7
- Does research (web search, analysis)
- Posts to SQLite: `INSERT INTO messages (task_id, content) VALUES (7, 'Found X...')`
- Updates task: `UPDATE tasks SET status = 'review' WHERE id = 7`
- Goes back to sleep

**Step 4 — Squad Lead wakes (next :00 heartbeat):**
- Sees Scout posted findings
- Mirrors to Discord: "📊 Scout completed BTC analysis, ready for review"

**Step 5 — You (Discord):**
- Read summary
- Reply: "@Alpha looks good, create a backtest"

---

## Why This Separation Matters

| Concern | With Separation | Without (Discord-only) |
|---------|-----------------|------------------------|
| **Discord outage** | Squad keeps working, queue builds up | Complete halt |
| **Rate limits** | SQLite is free/unlimited | Discord API limits |
| **History** | Full queryable history in SQL | Lost in scrollback |
| **Agents** | N agents = N SQLite connections | N agents = N Discord bots |
| **Testing** | Test with local SQLite | Need live Discord |
| **Debugging** | Query SQL to see state | Scroll through channels |

---

## Backend Decision Guide: SQLite vs PostgreSQL vs Convex

### When to Choose SQLite

**Best for:**
- ✅ Single-machine setups (your laptop, one VPS)
- ✅ Getting started (fastest to set up)
- ✅ 2-5 agents (light load)
- ✅ Prototyping and learning
- ✅ When you want zero external dependencies

**Limits:**
- One writer at a time (agents queue up)
- No real-time sync (poll every 30s)
- Single point of failure (file on disk)
- Harder to share across machines

**Setup:**
```bash
cd shared-state/sqlite
./init.sh  # Done. Ready.
```

---

### When to Choose Convex

**Best for:**
- ✅ Production, long-running squads
- ✅ Real-time sync (instant updates)
- ✅ 5+ agents (concurrent writes)
- ✅ Multiple humans viewing dashboard
- ✅ When you want hosted/managed backend

**Benefits over SQLite:**
- Real-time subscriptions (live UI updates)
- Concurrent writes (no locking issues)
- Hosted (backups, scaling)
- Better for building a web UI

**Setup:**
```bash
cd shared-state/convex
npm install
npx convex dev  # Gets you a URL + deploy key
```

**Convex free tier:**
- 1M function calls/month
- 500MB storage
- More than enough for personal squads

---

### When to Choose PostgreSQL

**Best for:**
- ✅ Production, long-running squads
- ✅ Multi-machine setups (agents on different VPS)
- ✅ 5+ agents (concurrent writes, no locking)
- ✅ SQL standard compliance
- ✅ When you want to own your data (self-hosted)

**Benefits over SQLite:**
- Concurrent writes (no single-writer lock)
- Network accessible (multiple machines)
- Better backup tools (pg_dump)
- Replication options (read replicas)
- Production-grade reliability

**Tradeoffs:**
- Requires PostgreSQL installation
- Need to create DB, user, set permissions
- Network configuration if remote

**Setup:**
```bash
cd shared-state/postgres
./init.sh  # Creates DB, user, applies schema
```

**Or manual:**
```bash
sudo -u postgres psql -c "CREATE DATABASE agent_squad;"
psql -U squad_user -d agent_squad -f schema.sql
```

---

### Decision Matrix

| Situation | Choose | Why |
|-----------|--------|-----|
| "Just trying this out" | SQLite | 30 seconds to setup |
| "Running on my laptop" | SQLite | No install needed |
| "Single VPS, 2-5 agents" | SQLite | Simple, sufficient |
| "Production, single VPS" | PostgreSQL | Do it right from start |
| "Multi-machine agents" | PostgreSQL | Network accessible |
| "5+ agents, concurrent writes" | PostgreSQL | No locking issues |
| "Want hosted/managed" | Convex | Zero ops |
| "Real-time sync critical" | Convex | Push subscriptions |
| "Serverless/functions" | Convex | HTTP API |

---

## Discord Integration: Three Modes

### Mode 1: Squad Lead Bridge (Default)

**What:** Only Squad Lead posts to Discord.

**Best for:** Small squads (2-5 agents), simplicity.

**Flow:**
```
You → Discord → Squad Lead SQLite → Squad Lead Discord summary
```

**Config:**
```yaml
discord:
  enabled: true
  mode: "squad-lead"
  channel: "trading-squad"
```

**Pros:** Simple, one point of control. **Cons:** If Squad Lead busy, updates delayed.

---

### Mode 2: Discord Relay Agent

**What:** Dedicated agent only does mirroring. Full transparency.

**Best for:** Teams wanting complete visibility.

**Flow:**
```
All agents → SQLite → Relay Agent → Discord (every 30s)
```

**Config:**
```yaml
discord:
  enabled: true
  mode: "relay"
  channel: "trading-squad"

agents:
  - name: relay
    role: reporter
    schedule: "*/2 * * * *"  # Checks DB every 2 min
```

**Pros:** Complete history, always current. **Cons:** More Discord traffic.

---

### Mode 3: No Discord

**What:** SQLite only. Query directly or build your own UI.

**Best for:** Privacy, custom dashboards, API-only use.

**Config:**
```yaml
discord:
  enabled: false
```

**Access data:**
```bash
sqlite3 shared-state/sqlite/squad.db "SELECT * FROM tasks;"
```

---

## File: Communication Layers

### Session Memory (OpenClaw)
- What: Conversation history with each agent
- Where: `~/.openclaw/agents/main/sessions/*.jsonl`
- Use: Agent recalls what you told them
- Limit: Cleared on session reset

### WORKING.md
- What: Current task state
- Where: `agents/{name}/memory/WORKING.md`
- Use: Agent reads on every wake to resume work
- Written by: Agent itself

### SQLite/Convex (Shared State)
- What: Tasks, messages, activities, notifications
- Where: `shared-state/sqlite/squad.db` or Convex cloud
- Use: Agent-to-agent coordination
- Written by: All agents

### Discord/Telegram
- What: Human interface, notifications
- Where: Discord channels
- Use: You talk to squad, see updates
- Written by: Squad Lead or Relay only

---

## Scaling Considerations

### 2-3 Agents
- Backend: SQLite
- Discord: Squad Lead bridge
- Simple, fast, no external deps

### 5-10 Agents
- Backend: Convex
- Discord: Optional relay agent
- Consider: Daily standup reports

### 10+ Agents
- Backend: Convex
- Discord: Relay agent + web dashboard
- Consider: Specialized sub-squads

---

## Debugging Architecture

**"Agent not seeing tasks"**
```bash
# Check database directly
sqlite3 shared-state/sqlite/squad.db "SELECT * FROM tasks WHERE status='inbox';"

# Check agent can read
openclaw sessions send --session agent:researcher:scout --message "Read SQLite, what tasks are assigned to you?"
```

**"Discord not getting updates"**
```bash
# Check if mode is set correctly
grep "mode:" squad.yaml

# For relay mode, check relay agent is deployed
./manage.sh status | grep relay

# Check relay can post
cd discord-bridge && ./run.sh once
```

**"SQLite locked"**
- Normal with many agents (SQLite is single-writer)
- Switch to Convex for concurrent access

---

See SETUP.md for implementation steps.
