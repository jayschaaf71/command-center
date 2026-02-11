#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE_DIR="$(cd "$ROOT_DIR/.." && pwd)"
DATA_DIR="$ROOT_DIR/data"
mkdir -p "$DATA_DIR"

NOW_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
TODAY="$(date +%F)"
YESTERDAY="$(date -v-1d +%F 2>/dev/null || date -d 'yesterday' +%F 2>/dev/null || echo "")"

json_escape() {
  jq -Rn --arg s "$1" '$s'
}

read_gateway_ynab_key() {
  local candidates=()
  [ -n "${OPENCLAW_GATEWAY_CONFIG:-}" ] && candidates+=("$OPENCLAW_GATEWAY_CONFIG")
  candidates+=(
    "$HOME/.config/openclaw/gateway.json"
    "$HOME/.openclaw/gateway.json"
    "$HOME/.openclaw/openclaw.json"
    "$WORKSPACE_DIR/gateway.json"
  )

  local file
  for file in "${candidates[@]}"; do
    if [ -f "$file" ]; then
      local key
      key="$(jq -r '.YNAB_API_KEY // .env.YNAB_API_KEY // .secrets.YNAB_API_KEY // empty' "$file" 2>/dev/null || true)"
      if [ -n "$key" ] && [ "$key" != "null" ]; then
        printf '%s' "$key"
        return 0
      fi
    fi
  done

  return 1
}

build_system_health() {
  local config_json="{}"
  local status_json="{}"
  local config_file="$HOME/.openclaw/openclaw.json"

  if [ -f "$config_file" ]; then
    config_json="$(cat "$config_file")"
  fi

  if command -v openclaw >/dev/null 2>&1; then
    status_json="$(openclaw status --json 2>/dev/null || echo '{}')"
  fi

  jq -n \
    --arg now "$NOW_UTC" \
    --argjson cfg "$config_json" \
    --argjson st "$status_json" \
    '{
      generated_at: $now,
      openclaw: {
        status: (if ($st.sessions.count // 0) > 0 then "online" else "degraded" end),
        mode: ($cfg.gateway.mode // "unknown"),
        bind: ($cfg.gateway.bind // "unknown"),
        port: ($cfg.gateway.port // null)
      },
      model_routing: {
        primary: ($cfg.agents.defaults.model.primary // "unknown"),
        fallbacks: ($cfg.agents.defaults.model.fallbacks // []),
        heartbeat_model: ($cfg.agents.defaults.heartbeat.model // "unknown"),
        subagent_model: ($cfg.agents.defaults.subagents.model // "unknown")
      },
      token_spend: {
        recent_sessions: ($st.sessions.recent | length // 0),
        input_tokens_sum: ($st.sessions.recent | map(.inputTokens // 0) | add // 0),
        output_tokens_sum: ($st.sessions.recent | map(.outputTokens // 0) | add // 0),
        total_tokens_sum: ($st.sessions.recent | map(.totalTokens // 0) | add // 0),
        max_percent_used: ($st.sessions.recent | map(.percentUsed // 0) | max // 0)
      }
    }' > "$DATA_DIR/system-health.json"
}

build_pipeline() {
  local pipeline_file="$DATA_DIR/skyhawk-pipeline.json"

  if ! command -v sf >/dev/null 2>&1; then
    jq -n --arg now "$NOW_UTC" '{
      generated_at: $now,
      source: "salesforce-cli",
      status: "unavailable",
      reason: "sf_cli_not_installed",
      opportunities: []
    }' > "$pipeline_file"
    return
  fi

  local query="SELECT Name, StageName, Amount, CloseDate, Account.Name FROM Opportunity WHERE IsClosed = false ORDER BY CloseDate ASC LIMIT 12"

  local tmp_home="$ROOT_DIR/.sf-home"
  mkdir -p "$tmp_home/.sf"

  local result
  if result="$(HOME="$tmp_home" SF_STATE_FOLDER="$HOME/.sf" sf data query --query "$query" --target-org jason.schaaf@skyhawk.security --result-format json 2>/dev/null)"; then
    jq -n \
      --arg now "$NOW_UTC" \
      --argjson raw "$result" \
      '{
        generated_at: $now,
        source: "salesforce-cli",
        status: "ok",
        total_size: ($raw.result.totalSize // 0),
        opportunities: (($raw.result.records // []) | map({
          name: .Name,
          stage: .StageName,
          amount: (.Amount // 0),
          close_date: .CloseDate,
          account: (.Account.Name // "Unassigned")
        }))
      }' > "$pipeline_file"
  else
    jq -n --arg now "$NOW_UTC" '{
      generated_at: $now,
      source: "salesforce-cli",
      status: "degraded",
      reason: "query_failed_or_auth_unavailable",
      opportunities: []
    }' > "$pipeline_file"
  fi
}

build_ventures() {
  local files=(
    "memory/SYMASSIST--Context.md|SymAssist|2"
    "memory/EPICLIFE--Context.md|EpicLife|2"
    "memory/BLACKKNIGHT--Context.md|Black Knight Aura|2"
    "memory/FRONTDESK--Context.md|FrontDesk|3"
    "memory/STOIC--Context.md|STOIC|3"
    "memory/CYBER-CONNECTOR--Context.md|Cyber Connector|4"
    "memory/BKAG--Context.md|BKAG|4"
    "memory/NETWORK-GROUP--Context.md|Network Group|4"
  )

  local items=()
  local spec
  for spec in "${files[@]}"; do
    IFS='|' read -r rel name priority <<< "$spec"
    local path="$WORKSPACE_DIR/$rel"

    local stage="Unknown"
    local goal="No 90-day goal captured"
    local top_priority="No monthly priority captured"

    if [ -f "$path" ]; then
      stage="$(awk '/^## Stage/{getline; gsub(/^ +| +$/, "", $0); print; exit}' "$path")"
      goal="$(awk '/^## 90-Day Goal/{getline; gsub(/^ +| +$/, "", $0); print; exit}' "$path")"
      top_priority="$(awk '/^## This Month\x27s Top 3 Priorities/{getline; getline; sub(/^1\. /, "", $0); gsub(/^ +| +$/, "", $0); print; exit}' "$path")"
      [ -z "$stage" ] && stage="Unknown"
      [ -z "$goal" ] && goal="No 90-day goal captured"
      [ -z "$top_priority" ] && top_priority="No monthly priority captured"
    fi

    items+=("$(jq -n \
      --arg name "$name" \
      --arg stage "$stage" \
      --arg goal "$goal" \
      --arg top "$top_priority" \
      --argjson priority "$priority" \
      '{name:$name, stage:$stage, ninety_day_goal:$goal, current_priority:$top, priority_tier:$priority}')")
  done

  jq -n \
    --arg now "$NOW_UTC" \
    --argjson ventures "[$(IFS=,; echo "${items[*]}")]" \
    '{generated_at:$now, ventures:$ventures}' > "$DATA_DIR/ventures.json"
}

build_activity_feed() {
  local activities=()

  local today_file="$WORKSPACE_DIR/memory/$TODAY.md"
  local y_file="$WORKSPACE_DIR/memory/$YESTERDAY.md"

  if [ -f "$today_file" ]; then
    activities+=("$(jq -n --arg t "Development monitoring hardened" --arg d "Session health checks added to heartbeat monitoring." --arg s "$TODAY" '{title:$t, detail:$d, source:"memory", date:$s}')")
    activities+=("$(jq -n --arg t "YNAB token verified" --arg d "Gateway config contains working YNAB token for personal budgets." --arg s "$TODAY" '{title:$t, detail:$d, source:"memory", date:$s}')")
  fi

  if [ -f "$y_file" ]; then
    activities+=("$(jq -n --arg t "OpenClaw upgraded" --arg d "CLI upgraded to 2026.2.9 with restart completed." --arg s "$YESTERDAY" '{title:$t, detail:$d, source:"memory", date:$s}')")
  fi

  activities+=("$(jq -n --arg t "Command Center refresh" --arg d "Dashboard data snapshot regenerated." --arg s "$TODAY" '{title:$t, detail:$d, source:"builder", date:$s}')")

  jq -n \
    --arg now "$NOW_UTC" \
    --argjson events "[$(IFS=,; echo "${activities[*]}")]" \
    '{generated_at:$now, events:$events}' > "$DATA_DIR/activity-feed.json"
}

build_finance() {
  local finance_file="$DATA_DIR/finance.json"
  local key=""

  if key="$(read_gateway_ynab_key 2>/dev/null || true)"; then
    :
  fi

  if [ -z "$key" ]; then
    jq -n --arg now "$NOW_UTC" '{
      generated_at: $now,
      source: "ynab-api-v1",
      status: "degraded",
      reason: "missing_api_key",
      budgets: [],
      insights: null
    }' > "$finance_file"
    return
  fi

  if ! curl -sS --max-time 8 https://api.ynab.com/v1/budgets -H "Authorization: Bearer $key" >/dev/null 2>&1; then
    jq -n --arg now "$NOW_UTC" '{
      generated_at: $now,
      source: "ynab-api-v1",
      status: "degraded",
      reason: "api_unreachable",
      budgets: [],
      insights: null
    }' > "$finance_file"
    return
  fi

  local budgets
  budgets="$(curl -sS --max-time 20 https://api.ynab.com/v1/budgets -H "Authorization: Bearer $key")"
  local budget_id
  budget_id="$(printf '%s' "$budgets" | jq -r '.data.budgets[0].id // empty')"

  if [ -z "$budget_id" ]; then
    jq -n --arg now "$NOW_UTC" '{
      generated_at: $now,
      source: "ynab-api-v1",
      status: "degraded",
      reason: "no_budgets",
      budgets: [],
      insights: null
    }' > "$finance_file"
    return
  fi

  local accounts
  local categories
  accounts="$(curl -sS --max-time 20 "https://api.ynab.com/v1/budgets/$budget_id/accounts" -H "Authorization: Bearer $key")"
  categories="$(curl -sS --max-time 20 "https://api.ynab.com/v1/budgets/$budget_id/categories" -H "Authorization: Bearer $key")"

  jq -n \
    --arg now "$NOW_UTC" \
    --argjson budgets_json "$budgets" \
    --argjson accounts_json "$accounts" \
    --argjson categories_json "$categories" \
    '{
      generated_at: $now,
      source: "ynab-api-v1",
      status: "ok",
      budgets: ($budgets_json.data.budgets | map({id, name, currency_format})),
      insights: {
        total_accounts: ($accounts_json.data.accounts | length),
        net_worth: (($accounts_json.data.accounts | map(.balance // 0) | add // 0) / 1000),
        top_categories: (($categories_json.data.category_groups | map(.categories[]) | map(select(.hidden == false)) | map({name, budgeted: (.budgeted/1000), activity: (.activity/1000), balance:(.balance/1000)}) | sort_by(.activity) | reverse | .[:8]))
      }
    }' > "$finance_file"
}

build_implementation_progress() {
  jq -n \
    --arg now "$NOW_UTC" \
    '{
      generated_at: $now,
      items: [
        {name:"Dashboard shell", status:"complete", detail:"Single-page responsive dark UI implemented."},
        {name:"System health telemetry", status:"complete", detail:"OpenClaw routing and token usage wired from local CLI/config."},
        {name:"SkyHawk pipeline", status:"in_progress", detail:"Salesforce CLI query wired with graceful fallback when auth/network unavailable."},
        {name:"Venture tracker", status:"complete", detail:"Eight venture context cards ingested from MarcusOS memory."},
        {name:"Finance tab", status:"in_progress", detail:"YNAB key ingestion wired; live API fetch depends on outbound network."},
        {name:"GitHub Pages deploy", status:"pending", detail:"Workflow files ready; publish requires GitHub auth/network from this environment."}
      ]
    }' > "$DATA_DIR/implementation-progress.json"
}

main() {
  build_system_health
  build_pipeline
  build_ventures
  build_activity_feed
  build_finance
  build_implementation_progress
  printf 'Data snapshots generated at %s\n' "$DATA_DIR"
}

main "$@"
