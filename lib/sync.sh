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
  [[ -f "$FONT_SYNC_STATE_FILE" ]] \
    && jq -e '.enabled == true' "$FONT_SYNC_STATE_FILE" &>/dev/null
}

# Why is_sync_enabled said no, on stderr, for the commands a person types. The
# automatic callers check is_sync_enabled first and stay quiet.
_sync_explain_disabled() {
  if _is_dev_mode; then
    echo "Error: sync is disabled in dev mode" >&2
  elif [[ ! -f "$FONT_SYNC_STATE_FILE" ]]; then
    echo "Error: sync is not set up. Run 'font sync init'." >&2
  else
    echo "Error: sync is off. Run 'font sync on' to resume it." >&2
  fi
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
    >"$FONT_SYNC_STATE_FILE"
}

# Find existing gist by description
_sync_find_gist() {
  gh gist list --limit 100 2>/dev/null \
    | grep -F "$FONT_GIST_DESCRIPTION" \
    | head -1 \
    | awk '{print $1}' || true
}

# The gist holds one file per machine, and a machine writes only its own.
#
# A union merge cannot express a deletion: every machine may assert every row, so
# a row removed here is put back by the next machine to sync from a copy that
# still holds it. One writer per file makes removing a row you wrote an ordinary
# edit, and no other machine has standing to undo it.
_sync_history_filename() {
  echo "history-$(get_machine_id).jsonl"
}

# The per-machine files, which is deliberately not the pre-split "history.jsonl".
# A machine on an older release still writes the whole merged set to that name —
# reading it back would restore the union this replaces.
#
# Fails when the gist cannot be read, so an unreachable gist is never mistaken
# for one that holds no machine's file yet.
_sync_remote_files() {
  local gist_id="$1"
  local listing

  if ! listing=$(gh gist view "$gist_id" --files 2>/dev/null); then
    echo "Error: could not read gist $gist_id. 'font sync status' checks gh." >&2
    return 1
  fi

  grep -E '^history-.+\.jsonl$' <<<"$listing" || true
}

_sync_fetch_file() {
  local gist_id="$1"
  local filename="$2"

  if ! gh gist view "$gist_id" --filename "$filename" --raw 2>/dev/null; then
    echo "Error: could not read $filename from gist $gist_id" >&2
    return 1
  fi
}

# This machine's rows, normalized and sorted — what its file in the gist holds.
_sync_own_records() {
  local machine_id="$1"

  get_history_raw | jq -c --arg me "$machine_id" 'select(.machine == $me)'
}

# Create new gist seeded with this machine's file
_sync_create_gist() {
  local tmpdir seed
  tmpdir=$(mktemp -d)
  seed="$tmpdir/$(_sync_history_filename)"

  _sync_own_records "$(get_machine_id)" >"$seed"
  [[ -s "$seed" ]] || echo "{}" >"$seed"

  local gist_url
  gist_url=$(gh gist create "$seed" --desc "$FONT_GIST_DESCRIPTION" 2>/dev/null)

  # Extract gist ID from URL
  echo "$gist_url" | grep -oE '[a-f0-9]{32}' | head -1

  rm -rf "$tmpdir"
}

# Every other machine's file as it stands in the gist, plus this machine's own
# rows from the local file.
#
# Taking the remote as authoritative for the others is what lets a deletion made
# on another machine arrive here. Keeping local for this machine is what lets one
# made here survive until the next push.
#
# The machine normalizer runs on both sides. Ownership is decided by .machine, so
# a legacy "macos-laptop" record would otherwise belong to no machine at all.
#
# Args: <local_file> <machine_id> [remote_content]
_sync_merge_histories() {
  local local_file="$1"
  local machine_id="$2"
  local remote_content="${3:-}"

  {
    if [[ -f "$local_file" ]]; then
      jq -s -c --arg me "$machine_id" "
        map($_JQ_NORMALIZE_FONT_NAMES | $_JQ_NORMALIZE_MACHINE) |
        map(select(.machine == \$me)) | .[]
      " "$local_file"
    fi

    if [[ -n "$remote_content" ]]; then
      printf '%s\n' "$remote_content" | jq -s -c --arg me "$machine_id" "
        flatten |
        map(select(. != null and . != {} and type == \"object\")) |
        map($_JQ_NORMALIZE_FONT_NAMES | $_JQ_NORMALIZE_MACHINE) |
        map(select(.machine != \$me)) | .[]
      "
    fi
    # unique_by survives the split. A machine whose id drifts writes a second
    # file, and both then carry the same rows under one normalized name.
  } | jq -s -c 'unique_by([.ts, .machine, .font, .action]) | sort_by(.ts) | .[]'
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

    # Saved before the pull, which reads the gist id from the state file and
    # does nothing while sync is not enabled.
    _sync_update_state "$gist_id" true

    echo "Merging with local history..."
    if sync_pull; then
      echo "✓ Merged remote history"
    else
      echo "✗ Could not merge remote history. Sync is on, and the next pull retries." >&2
      return 1
    fi
  else
    echo "Creating new gist..."
    gist_id=$(_sync_create_gist)

    if [[ -z "$gist_id" ]]; then
      echo "Error: Failed to create gist" >&2
      return 1
    fi

    echo "Created gist: $gist_id"
    _sync_update_state "$gist_id" true
  fi

  echo ""
  echo "✓ Sync initialized!"
  echo "  Gist ID: $gist_id"
  echo "  History will sync automatically."
}

# Pull from gist and merge. Fails, leaving the local history as it was, when
# sync is off or any machine's file cannot be read.
sync_pull() {
  if ! is_sync_enabled; then
    _sync_explain_disabled
    return 1
  fi

  local gist_id
  gist_id=$(_sync_get_gist_id)

  if [[ -z "$gist_id" ]]; then
    echo "Error: no gist id in $FONT_SYNC_STATE_FILE. Run 'font sync init'." >&2
    return 1
  fi

  local machine_id own_file remote_files
  machine_id=$(get_machine_id)
  own_file=$(_sync_history_filename)
  remote_files=$(_sync_remote_files "$gist_id") || return 1

  # Every machine's file but this one's. This machine's rows come from local,
  # which is what lets a row written since the last push survive a pull.
  #
  # A file that cannot be fetched fails the whole pull. Merging without it
  # would drop that machine's rows from the local history.
  local remote_content="" filename content
  while IFS= read -r filename; do
    [[ -z "$filename" || "$filename" == "$own_file" ]] && continue
    content=$(_sync_fetch_file "$gist_id" "$filename") || return 1
    remote_content+="$content"$'\n'
  done <<<"$remote_files"

  local merged
  if ! merged=$(_sync_merge_histories "$FONT_HISTORY_FILE" "$machine_id" "$remote_content"); then
    echo "Error: could not merge gist $gist_id into $FONT_HISTORY_FILE" >&2
    return 1
  fi

  # Written only when the merge holds rows, so no failure that leaves it empty
  # can truncate the history.
  if [[ -n "$merged" ]]; then
    echo "$merged" >"$FONT_HISTORY_FILE"
  fi

  # Update last sync time
  if [[ -f "$FONT_SYNC_STATE_FILE" ]]; then
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local state
    state=$(cat "$FONT_SYNC_STATE_FILE")
    echo "$state" | jq --arg ts "$timestamp" '.last_sync = $ts' >"$FONT_SYNC_STATE_FILE"
  fi

  return 0
}

# Pull, then upload this machine's rows to its own file in the gist. Fails when
# sync is off, the gist cannot be read, or the upload is refused.
sync_push() {
  if ! is_sync_enabled; then
    _sync_explain_disabled
    return 1
  fi

  local gist_id
  gist_id=$(_sync_get_gist_id)

  if [[ -z "$gist_id" ]]; then
    echo "Error: no gist id in $FONT_SYNC_STATE_FILE. Run 'font sync init'." >&2
    return 1
  fi

  if [[ ! -f "$FONT_HISTORY_FILE" ]] || [[ ! -s "$FONT_HISTORY_FILE" ]]; then
    return 0
  fi

  sync_pull || return 1

  local own_file tmpdir slice
  own_file=$(_sync_history_filename)
  tmpdir=$(mktemp -d)
  slice="$tmpdir/$own_file"
  _sync_own_records "$(get_machine_id)" >"$slice"

  if [[ ! -s "$slice" ]]; then
    rm -rf "$tmpdir"
    return 0
  fi

  local remote_files
  if ! remote_files=$(_sync_remote_files "$gist_id"); then
    rm -rf "$tmpdir"
    return 1
  fi

  # --filename replaces a file the gist already has; --add is the only way to
  # create one, and it names it after the local file's basename.
  local -a edit_args
  if grep -qxF "$own_file" <<<"$remote_files"; then
    edit_args=(--filename "$own_file" "$slice")
  else
    edit_args=(--add "$slice")
  fi

  local gh_error
  if ! gh_error=$(gh gist edit "$gist_id" "${edit_args[@]}" 2>&1 >/dev/null); then
    rm -rf "$tmpdir"
    echo "Error: could not write $own_file to gist $gist_id: $gh_error" >&2
    return 1
  fi
  rm -rf "$tmpdir"

  if [[ -f "$FONT_SYNC_STATE_FILE" ]]; then
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local state
    state=$(cat "$FONT_SYNC_STATE_FILE")
    echo "$state" | jq --arg ts "$timestamp" '.last_sync = $ts' >"$FONT_SYNC_STATE_FILE"
  fi
  return 0
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
    entry_count=$(wc -l <"$FONT_HISTORY_FILE" | xargs)
    echo "Local entries: $entry_count"
  fi
}

# Disable sync
sync_off() {
  if [[ -f "$FONT_SYNC_STATE_FILE" ]]; then
    local state
    state=$(cat "$FONT_SYNC_STATE_FILE")
    echo "$state" | jq '.enabled = false' >"$FONT_SYNC_STATE_FILE"
    echo "✓ Sync disabled"
    echo ""
    echo "Run 'font sync on' to resume it."
  else
    echo "Sync was not initialized."
  fi
}

# Re-enable sync
sync_on() {
  if [[ -f "$FONT_SYNC_STATE_FILE" ]]; then
    local state
    state=$(cat "$FONT_SYNC_STATE_FILE")
    echo "$state" | jq '.enabled = true' >"$FONT_SYNC_STATE_FILE"
    echo "✓ Sync enabled"

    if ! sync_pull || ! sync_push; then
      echo "✗ The first sync failed. Sync stays on, and the next action retries." >&2
      return 1
    fi
  else
    echo "Sync was not initialized."
    echo "Run 'font sync init' first."
  fi
}

# Auto-sync wrapper for commands that modify history, called after log_action.
# The push runs in the background, so its result is never known here and the
# line says it started rather than that it succeeded.
sync_after_action() {
  if is_sync_enabled; then
    echo "Syncing to GitHub Gist in the background"
    sync_push &>/dev/null &
    disown 2>/dev/null || true
  fi
}

# Auto-sync wrapper for the pickers, called before they read history. A failed
# pull leaves the local history as it was, and the picker opens on that.
sync_before_read() {
  if is_sync_enabled; then
    if sync_pull &>/dev/null; then
      echo "✓ Synced via GitHub Gist"
    else
      echo "✗ Could not sync with GitHub Gist; showing local history" >&2
    fi
  fi
}
