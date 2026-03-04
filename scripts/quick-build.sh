#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="$ROOT_DIR/data"
NOW_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo "🔄 Quick Command Center build started..."

# System Health (fast)
echo "📊 Building system health..."
openclaw status --json > "$DATA_DIR/system-health.json" 2>/dev/null || echo '{"status":"offline","error":"openclaw unavailable"}' > "$DATA_DIR/system-health.json"

# Ventures (from local files)
echo "🏢 Building ventures data..."
cat > "$DATA_DIR/ventures.json" << 'EOF'
{
  "generated_at": "TIMESTAMP_PLACEHOLDER",
  "ventures": [
    {"name": "SkyHawk Security", "priority": 1, "status": "active", "role": "CRO"},
    {"name": "SymAssist", "priority": 2, "status": "active", "role": "Co-Founder"},
    {"name": "My Epic Life", "priority": 2, "status": "active", "role": "Co-Founder"},
    {"name": "BlackKnight AI", "priority": 2, "status": "active", "role": "Founder"},
    {"name": "STOIC Timepieces", "priority": 3, "status": "dormant", "role": "Founder"}
  ]
}
EOF
sed -i '' "s/TIMESTAMP_PLACEHOLDER/$NOW_UTC/" "$DATA_DIR/ventures.json"

# Activity Feed (recent events)
echo "📰 Building activity feed..."
cat > "$DATA_DIR/activity-feed.json" << EOF
{
  "generated_at": "$NOW_UTC",
  "events": [
    {"timestamp": "$NOW_UTC", "type": "system", "message": "Command Center rebuild completed"},
    {"timestamp": "$NOW_UTC", "type": "build", "message": "Data refresh in progress"}
  ]
}
EOF

# Implementation Progress
echo "🚧 Building implementation progress..."
cat > "$DATA_DIR/implementation-progress.json" << EOF
{
  "generated_at": "$NOW_UTC",
  "status": "active",
  "completion": 75,
  "current_phase": "Remote Access Deployment",
  "next_milestone": "Full YNAB Integration"
}
EOF

# Simplified Pipeline (without hanging Salesforce calls)
echo "💼 Building SkyHawk pipeline..."
cat > "$DATA_DIR/skyhawk-pipeline.json" << EOF
{
  "generated_at": "$NOW_UTC",
  "status": "limited_access",
  "message": "Salesforce data unavailable during remote build"
}
EOF

# Basic Finance (will enhance later)
echo "💰 Building finance data..."
cat > "$DATA_DIR/finance.json" << EOF
{
  "generated_at": "$NOW_UTC",
  "status": "connecting",
  "message": "YNAB integration in progress"
}
EOF

echo "✅ Quick build complete! Dashboard ready for deployment."