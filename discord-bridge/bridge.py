#!/usr/bin/env python3
"""
Discord Bridge for Agent Squad
Mirrors SQLite/Convex activity to Discord for transparency
"""

import sqlite3
import json
import os
import time
from datetime import datetime
from pathlib import Path

# Configuration from environment or config
DB_PATH = os.getenv("SQUAD_DB", "../shared-state/sqlite/squad.db")
DISCORD_CHANNEL = os.getenv("DISCORD_CHANNEL", "agent-squad")
POLL_INTERVAL = int(os.getenv("POLL_INTERVAL", "30"))
LAST_CHECK_FILE = Path(".last_check")

def get_db_connection():
    """Get SQLite connection"""
    return sqlite3.connect(DB_PATH)

def get_last_check():
    """Get timestamp of last check"""
    if LAST_CHECK_FILE.exists():
        return float(LAST_CHECK_FILE.read_text().strip())
    return 0

def set_last_check(timestamp):
    """Save timestamp of last check"""
    LAST_CHECK_FILE.write_text(str(timestamp))

def fetch_new_activities(since):
    """Fetch activities since last check"""
    conn = get_db_connection()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    
    cursor.execute("""
        SELECT a.*, ag.name as agent_name, ag.role as agent_role
        FROM activities a
        JOIN agents ag ON a.agent_id = ag.id
        WHERE a.created_at > ?
        AND (a.posted_to_discord = 0 OR a.posted_to_discord IS NULL)
        ORDER BY a.created_at ASC
    """, (since * 1000,))  # Assuming created_at is milliseconds
    
    activities = cursor.fetchall()
    conn.close()
    return activities

def fetch_new_tasks(since):
    """Fetch new tasks since last check"""
    conn = get_db_connection()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    
    cursor.execute("""
        SELECT t.*, GROUP_CONCAT(a.name) as assignee_names
        FROM tasks t
        LEFT JOIN task_assignees ta ON t.id = ta.task_id
        LEFT JOIN agents a ON ta.agent_id = a.id
        WHERE t.created_at > ?
        AND (t.posted_to_discord = 0 OR t.posted_to_discord IS NULL)
        GROUP BY t.id
        ORDER BY t.created_at ASC
    """, (since * 1000,))
    
    tasks = cursor.fetchall()
    conn.close()
    return tasks

def fetch_new_messages(since):
    """Fetch new messages that mention humans or are significant"""
    conn = get_db_connection()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    
    cursor.execute("""
        SELECT m.*, a.name as agent_name, t.title as task_title
        FROM messages m
        JOIN agents a ON m.from_agent_id = a.id
        JOIN tasks t ON m.task_id = t.id
        WHERE m.created_at > ?
        AND (m.posted_to_discord = 0 OR m.posted_to_discord IS NULL)
        AND (
            m.content LIKE '%@human%' OR
            m.content LIKE '%@guillermo%' OR
            m.content LIKE '%needs review%' OR
            m.content LIKE '%ready for%' OR
            m.content LIKE '%completed%'
        )
        ORDER BY m.created_at ASC
    """, (since * 1000,))
    
    messages = cursor.fetchall()
    conn.close()
    return messages

def format_activity(activity):
    """Format activity for Discord"""
    agent = activity['agent_name']
    emoji = {
        'task_created': '📋',
        'task_assigned': '👤',
        'task_completed': '✅',
        'message_sent': '💬',
        'document_created': '📝',
        'agent_blocked': '🚫',
        'agent_active': '▶️'
    }.get(activity['type'], '•')
    
    return f"{emoji} **{agent}**: {activity['message']}"

def format_task(task):
    """Format task for Discord"""
    status_emoji = {
        'inbox': '📥',
        'assigned': '👤',
        'in_progress': '🔧',
        'review': '👀',
        'done': '✅',
        'blocked': '🚫'
    }.get(task['status'], '📋')
    
    assignees = task['assignee_names'] or 'Unassigned'
    return f"📋 **New Task**: {task['title']}\n   Status: {status_emoji} {task['status']} | Assigned: {assignees}"

def format_message(msg):
    """Format message for Discord"""
    # Truncate long messages
    content = msg['content']
    if len(content) > 200:
        content = content[:200] + "..."
    
    return f"💬 **{msg['agent_name']}** in *{msg['task_title']}*:\n> {content}"

def send_to_discord(content):
    """Send message to Discord via OpenClaw"""
    # This will be implemented to use the message tool
    # For now, write to a file that can be picked up
    import subprocess
    
    try:
        # Use OpenClaw CLI to send message
        result = subprocess.run(
            ['openclaw', 'message', 'send', 
             '--channel', 'discord',
             '--target', DISCORD_CHANNEL,
             '--message', content],
            capture_output=True,
            text=True,
            timeout=10
        )
        return result.returncode == 0
    except Exception as e:
        print(f"Failed to send to Discord: {e}")
        return False

def mark_as_posted(table, ids):
    """Mark items as posted to Discord"""
    if not ids:
        return
    
    conn = get_db_connection()
    cursor = conn.cursor()
    
    placeholders = ','.join('?' * len(ids))
    cursor.execute(f"""
        UPDATE {table} 
        SET posted_to_discord = 1 
        WHERE id IN ({placeholders})
    """, tuple(ids))
    
    conn.commit()
    conn.close()

def run_bridge_cycle():
    """Run one cycle of the bridge"""
    since = get_last_check()
    now = time.time()
    
    # Fetch new items
    activities = fetch_new_activities(since)
    tasks = fetch_new_tasks(since)
    messages = fetch_new_messages(since)
    
    posted_ids = {
        'activities': [],
        'tasks': [],
        'messages': []
    }
    
    # Post activities
    for activity in activities:
        content = format_activity(activity)
        if send_to_discord(content):
            posted_ids['activities'].append(activity['id'])
            print(f"Posted activity: {activity['type']} by {activity['agent_name']}")
    
    # Post tasks
    for task in tasks:
        content = format_task(task)
        if send_to_discord(content):
            posted_ids['tasks'].append(task['id'])
            print(f"Posted task: {task['title']}")
    
    # Post messages
    for msg in messages:
        content = format_message(msg)
        if send_to_discord(content):
            posted_ids['messages'].append(msg['id'])
            print(f"Posted message from {msg['agent_name']}")
    
    # Mark as posted
    mark_as_posted('activities', posted_ids['activities'])
    mark_as_posted('tasks', posted_ids['tasks'])
    mark_as_posted('messages', posted_ids['messages'])
    
    # Update last check
    set_last_check(now)
    
    # Summary
    total = sum(len(v) for v in posted_ids.values())
    if total > 0:
        print(f"[{datetime.now().isoformat()}] Posted {total} items to Discord")

def main():
    """Main loop"""
    print(f"Discord Bridge started")
    print(f"Database: {DB_PATH}")
    print(f"Channel: {DISCORD_CHANNEL}")
    print(f"Poll interval: {POLL_INTERVAL}s")
    print("-" * 50)
    
    while True:
        try:
            run_bridge_cycle()
        except Exception as e:
            print(f"Error in cycle: {e}")
        
        time.sleep(POLL_INTERVAL)

if __name__ == "__main__":
    main()
