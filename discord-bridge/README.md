# Discord Bridge

Mirrors SQLite/Convex activity to Discord for transparency.

## Architecture

```
SQLite/Convex (Source of Truth)
         ↓
   Discord Bridge
   (monitors DB, posts to Discord)
         ↓
     Discord Channel
   (transparency for humans)
```

## Modes

### Option 1: Squad Lead Bridge
Only Squad Lead has Discord access. Mirrors key events.

**squad.yaml:**
```yaml
discord:
  enabled: true
  mode: "squad-lead"
  channel: "trading-squad"
```

### Option 2: Discord Relay (Recommended)
Dedicated relay agent provides full transparency.

**squad.yaml:**
```yaml
discord:
  enabled: true
  mode: "relay"
  channel: "trading-squad"

agents:
  - name: relay
    display_name: "Squad Feed"
    role: reporter
    template: relay
    schedule: "*/2 * * * *"  # Checks every 2 min
```

### Option 3: No Discord
SQLite only. Query directly:
```bash
sqlite3 shared-state/sqlite/squad.db "SELECT * FROM tasks;"
```

## Usage

```bash
# Run once (test)
cd discord-bridge && ./run.sh once

# Run as daemon
./run.sh daemon

# With tmux
tmux new-session -d -s discord-bridge "./run.sh"

# Environment variables
export DISCORD_CHANNEL="my-channel"
export SQUAD_DB="../shared-state/sqlite/squad.db"
export POLL_INTERVAL="30"
./run.sh
```

## What Gets Posted

| Event | Emoji | Example |
|-------|-------|---------|
| New task | 📋 | "📋 Task #42: BTC momentum research created" |
| Task completed | ✅ | "✅ Task #38 completed by Quant" |
| Task in review | 👀 | "👀 Task #35 ready for review" |
| Agent blocked | 🚫 | "🚫 Builder blocked on API keys" |
| @mention human | 💬 | "💬 Quant asks: @guillermo which timeframe?" |

## Database Schema Additions

For tracking what was relayed:

```sql
-- Add to tasks table
ALTER TABLE tasks ADD COLUMN posted_to_discord INTEGER DEFAULT 0;

-- Add to activities table  
ALTER TABLE activities ADD COLUMN posted_to_discord INTEGER DEFAULT 0;

-- Add to messages table
ALTER TABLE messages ADD COLUMN posted_to_discord INTEGER DEFAULT 0;
```

See `../shared-state/sqlite/init.sql` for full schema.
