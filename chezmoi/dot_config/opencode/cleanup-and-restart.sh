#!/bin/bash
# OpenCode Cleanup & Restart Script
# Clears bloated log files then restarts the opencode service.
# Usage: ~/.config/opencode/cleanup-and-restart.sh

set -euo pipefail

LOG_DIR="$HOME/.local/share/opencode/log"
SERVE_LOG="$HOME/.local/share/opencode/serve.log"

echo "🔍 Current log usage:"
du -sh "$LOG_DIR" 2>/dev/null || echo "  No log dir found"
du -sh "$SERVE_LOG" 2>/dev/null || echo "  No serve.log found"

echo ""
echo "🗑️  Removing logs..."
rm -f "$LOG_DIR"/*.log
: > "$SERVE_LOG" 2>/dev/null || true   # truncate serve.log instead of deleting

echo "✅ Logs cleared"

echo ""
echo "🔄 Restarting opencode service..."
launchctl kickstart -k "gui/$(id -u)/com.opencode.serve"

sleep 2
echo ""
echo "📊 Disk status:"
df -h / | awk 'NR==1 || /\/$/'
