#!/usr/bin/env bash
# Font sync layer - transparent GitHub Gist synchronization
# Keeps history synced across machines without user intervention

set -euo pipefail

_SYNC_APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Sync state file (alongside history)
FONT_SYNC_STATE_FILE="${FONT_STATE_DIR:-$HOME/.local/state/font}/sync-state.json"
FONT_GIST_DESCRIPTION="font-preferences"

# Check if gh CLI is installed and authenticated
_sync_check_gh() {
  if ! command -v gh &>/dev/null; then
    echo "Error: GitHub CLI (gh) not installed" >&2
    echo "Install with: brew install gh" >&2
    return 1
  fi

  if ! gh auth status &>/dev/null 2>&1; then
    echo "Error: Not authenticated with GitHub" >&2
    echo "Run: gh auth login" >&2
    return 1
  fi

  return 0
}

# Check if sync is enabled (disabled in dev mode)
is_sync_enabled() {
  _is_dev_mode && return 1
  [[ -f "$FONT_SYNC_STATE_FILE" ]] && \
    jq -e '.enabled == true' "$FONT_SYNC_STATE_FILE" &>/dev/null
}

# Get gist ID from state
_sync_get_gist_id() {
  if [[ -f "$FONT_SYNC_STATE_FILE" ]]; then
    jq -r '.gist_id // empty' "$FONT_SYNC_STATE_FILE"
  fi
}

# Update sync state
_sync_update_state() {
  local gist_id="$1"
  local enabled="${2:-true}"

  mkdir -p "$(dirname "$FONT_SYNC_STATE_FILE")"

  local timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  jq -n \
    --arg gist_id "$gist_id" \
    --arg last_sync "$timestamp" \
    --argjson enabled "$enabled" \
    '{gist_id: $gist_id, last_sync: $last_sync, enabled: $enabled}' \
    > "$FONT_SYNC_STATE_FILE"
}

# Find existing gist by description
_sync_find_gist() {
  gh gist list --limit 100 2>/dev/null | \
    grep -F "$FONT_GIST_DESCRIPTION" | \
    head -1 | \
    awk '{print $1}' || true
}

# Create new gist with initial history
_sync_create_gist() {
  local history_file="$FONT_HISTORY_FILE"

  if [[ ! -f "$history_file" ]] || [[ ! -s "$history_file" ]]; then
    echo "{}" > /tmp/font-history-init.jsonl
    history_file="/tmp/font-history-init.jsonl"
  fi

  local gist_url
  gist_url=$(gh gist create "$history_file" \
    --desc "$FONT_GIST_DESCRIPTION" \
    --filename "history.jsonl" 2>/dev/null)

  # Extract gist ID from URL
  echo "$gist_url" | grep -oE '[a-f0-9]{32}' | head -1

  rm -f /tmp/font-history-init.jsonl
}

# Fetch gist content
_sync_fetch_gist() {
  local gist_id="$1"

  gh gist view "$gist_id" --filename "history.jsonl" --raw 2>/dev/null
}

# Merge two history streams (deduplication by ts+machine+font+action)
_sync_merge_histories() {
  local local_file="$1"
  local remote_content="$2"

  # Combine local and remote, dedupe, sort by timestamp
  {
    [[ -f "$local_file" ]] && cat "$local_file"
    echo "$remote_content"
  } | jq -s '
    flatten |
    map(select(. != null and . != {} and type == "object")) |
    unique_by([.ts, .machine, .font, .action]) |
    sort_by(.ts)
  ' | jq -c '.[]'
}

# Initialize sync - set up gist and do initial sync
sync_init() {
  if _is_dev_mode; then
    echo "✗ Sync is disabled in dev mode" >&2
    return 1
  fi

  echo "Initializing font sync..."

  if ! _sync_check_gh; then
    return 1
  fi

  # Check for existing gist
  local gist_id
  gist_id=$(_sync_find_gist)

  if [[ -n "$gist_id" ]]; then
    echo "Found existing gist: $gist_id"

    # Pull and merge with local
    echo "Merging with local history..."
    if sync_pull; then
      echo "✓ Merged remote history"
    fi
  else
    echo "Creating new gist..."
    gist_id=$(_sync_create_gist)

    if [[ -z "$gist_id" ]]; then
      echo "Error: Failed to create gist" >&2
      return 1
    fi

    echo "Created gist: $gist_id"
  fi

  # Save state
  _sync_update_state "$gist_id" true

  echo ""
  echo "✓ Sync initialized!"
  echo "  Gist ID: $gist_id"
  echo "  History will sync automatically."
}

# Pull from gist and merge
sync_pull() {
  if ! is_sync_enabled; then
    return 0
  fi

  local gist_id
  gist_id=$(_sync_get_gist_id)

  if [[ -z "$gist_id" ]]; then
    return 1
  fi

  # Fetch remote content
  local remote_content
  if ! remote_content=$(_sync_fetch_gist "$gist_id" 2>/dev/null); then
    # Network error - silently continue with local
    return 0
  fi

  # Skip if remote is empty or just "{}"
  if [[ -z "$remote_content" ]] || [[ "$remote_content" == "{}" ]]; then
    return 0
  fi

  # Merge with local
  local merged
  merged=$(_sync_merge_histories "$FONT_HISTORY_FILE" "$remote_content")

  # Write merged result
  if [[ -n "$merged" ]]; then
    echo "$merged" > "$FONT_HISTORY_FILE"
  fi

  # Update last sync time
  if [[ -f "$FONT_SYNC_STATE_FILE" ]]; then
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local state
    state=$(cat "$FONT_SYNC_STATE_FILE")
    echo "$state" | jq --arg ts "$timestamp" '.last_sync = $ts' > "$FONT_SYNC_STATE_FILE"
  fi

  return 0
}

# Push local history to gist
sync_push() {
  if ! is_sync_enabled; then
    return 0
  fi

  local gist_id
  gist_id=$(_sync_get_gist_id)

  if [[ -z "$gist_id" ]]; then
    return 1
  fi

  if [[ ! -f "$FONT_HISTORY_FILE" ]] || [[ ! -s "$FONT_HISTORY_FILE" ]]; then
    return 0
  fi

  # First pull to get any remote changes
  sync_pull

  # Push merged history
  if gh gist edit "$gist_id" --filename "history.jsonl" "$FONT_HISTORY_FILE" &>/dev/null; then
    # Update last sync time
    if [[ -f "$FONT_SYNC_STATE_FILE" ]]; then
      local timestamp
      timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      local state
      state=$(cat "$FONT_SYNC_STATE_FILE")
      echo "$state" | jq --arg ts "$timestamp" '.last_sync = $ts' > "$FONT_SYNC_STATE_FILE"
    fi
    return 0
  else
    # Network error - silently continue
    return 0
  fi
}

# Show sync status
sync_status() {
  echo ""
  echo "Font Sync Status"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  if _is_dev_mode; then
    echo "Status: Disabled (dev mode)"
    echo ""
    echo "Sync is disabled in development mode to prevent"
    echo "test data from polluting production history."
    return
  fi

  if [[ ! -f "$FONT_SYNC_STATE_FILE" ]]; then
    echo "Status: Not initialized"
    echo ""
    echo "Run 'font sync init' to set up sync."
    return
  fi

  local state
  state=$(cat "$FONT_SYNC_STATE_FILE")

  local enabled
  enabled=$(echo "$state" | jq -r '.enabled // false')

  local gist_id
  gist_id=$(echo "$state" | jq -r '.gist_id // "none"')

  local last_sync
  last_sync=$(echo "$state" | jq -r '.last_sync // "never"')

  if [[ "$enabled" == "true" ]]; then
    echo "Status: Enabled ✓"
  else
    echo "Status: Disabled"
  fi

  echo "Gist ID: $gist_id"
  echo "Last sync: $last_sync"
  echo ""

  # Check gh status
  if _sync_check_gh &>/dev/null; then
    echo "GitHub CLI: Authenticated ✓"
  else
    echo "GitHub CLI: Not authenticated"
  fi

  # Show local history stats
  if [[ -f "$FONT_HISTORY_FILE" ]]; then
    local entry_count
    entry_count=$(wc -l < "$FONT_HISTORY_FILE" | xargs)
    echo "Local entries: $entry_count"
  fi
}

# Disable sync
sync_off() {
  if [[ -f "$FONT_SYNC_STATE_FILE" ]]; then
    local state
    state=$(cat "$FONT_SYNC_STATE_FILE")
    echo "$state" | jq '.enabled = false' > "$FONT_SYNC_STATE_FILE"
    echo "✓ Sync disabled"
    echo ""
    echo "Run 'font sync init' to re-enable."
  else
    echo "Sync was not initialized."
  fi
}

# Re-enable sync
sync_on() {
  if [[ -f "$FONT_SYNC_STATE_FILE" ]]; then
    local state
    state=$(cat "$FONT_SYNC_STATE_FILE")
    echo "$state" | jq '.enabled = true' > "$FONT_SYNC_STATE_FILE"
    echo "✓ Sync enabled"

    # Do an immediate sync
    sync_pull
    sync_push
  else
    echo "Sync was not initialized."
    echo "Run 'font sync init' first."
  fi
}

# Auto-sync wrapper for commands that modify history
# Call this after log_action to push changes
sync_after_action() {
  if is_sync_enabled; then
    echo "✓ Synced via GitHub Gist"
    sync_push &>/dev/null &
    disown 2>/dev/null || true
  fi
}

# Auto-sync wrapper for commands that read history
# Call this before showing font list or rankings
sync_before_read() {
  if is_sync_enabled; then
    sync_pull &>/dev/null || true
    echo "✓ Synced via GitHub Gist"
  fi
}
