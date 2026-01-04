#!/usr/bin/env bash
# One-time migration script for font history data
# Migrates from ~/.config/font/ to ~/.local/state/font/
#
# Changes:
# - Single unified history.jsonl (not per-platform)
# - Adds terminal context fields (null for migrated records)
# - Converts rejected-fonts-*.json to reject action records
# - Moves preview cache to ~/.cache/font/previews/

set -euo pipefail

OLD_CONFIG_DIR="$HOME/.config/font"
NEW_STATE_DIR="$HOME/.local/state/font"
NEW_CACHE_DIR="$HOME/.cache/font/previews"
OLD_PREVIEW_CACHE="/tmp/font-preview"

info() { echo "[info] $*"; }
success() { echo "[ok] $*"; }
warn() { echo "[warn] $*"; }
error() { echo "[error] $*" >&2; }

if [[ -f "$NEW_STATE_DIR/history.jsonl" ]]; then
  error "Migration already completed: $NEW_STATE_DIR/history.jsonl exists"
  echo "To re-run migration, first remove: rm -rf $NEW_STATE_DIR"
  exit 1
fi

if [[ ! -d "$OLD_CONFIG_DIR" ]]; then
  error "Source directory not found: $OLD_CONFIG_DIR"
  exit 1
fi

MACHINE_ID="$(uname -s | tr '[:upper:]' '[:lower:]')-$(hostname -s)"
info "Machine ID: $MACHINE_ID"

info "Creating new directories..."
mkdir -p "$NEW_STATE_DIR"
mkdir -p "$NEW_CACHE_DIR"

info "Migrating history files..."
HISTORY_COUNT=0

for history_file in "$OLD_CONFIG_DIR"/history-*.jsonl; do
  [[ -f "$history_file" ]] || continue

  platform=$(basename "$history_file" .jsonl | sed 's/history-//')
  info "  Processing history-${platform}.jsonl..."

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    migrated=$(echo "$line" | jq -c \
      --arg machine "$MACHINE_ID" \
      '. + {
        machine: $machine,
        terminal: "ghostty",
        in_tmux: null,
        cols: null,
        rows: null,
        resolution: null,
        font_size: null
      }')

    echo "$migrated" >> "$NEW_STATE_DIR/history.jsonl"
    HISTORY_COUNT=$((HISTORY_COUNT + 1))
  done < "$history_file"
done

success "Migrated $HISTORY_COUNT history records"

info "Converting rejected fonts to reject actions..."
REJECT_COUNT=0

for rejected_file in "$OLD_CONFIG_DIR"/rejected-fonts-*.json; do
  [[ -f "$rejected_file" ]] || continue

  platform=$(basename "$rejected_file" .json | sed 's/rejected-fonts-//')
  info "  Processing rejected-fonts-${platform}.json..."

  jq -c --arg machine "$MACHINE_ID" --arg platform "$platform" '
    to_entries[] | {
      ts: .value.rejected_date,
      machine: $machine,
      platform: $platform,
      terminal: "ghostty",
      font: .key,
      action: "reject",
      message: .value.reason,
      in_tmux: null,
      cols: null,
      rows: null,
      resolution: null,
      font_size: null
    }
  ' "$rejected_file" >> "$NEW_STATE_DIR/history.jsonl"

  REJECT_COUNT=$(jq 'keys | length' "$rejected_file")
done

success "Converted $REJECT_COUNT rejected fonts to reject actions"

info "Sorting history by timestamp..."
TEMP_FILE=$(mktemp)
jq -s 'sort_by(.ts)' "$NEW_STATE_DIR/history.jsonl" | jq -c '.[]' > "$TEMP_FILE"
mv "$TEMP_FILE" "$NEW_STATE_DIR/history.jsonl"
success "History sorted"

if [[ -d "$OLD_PREVIEW_CACHE" ]] && [[ -n "$(ls -A "$OLD_PREVIEW_CACHE" 2>/dev/null)" ]]; then
  info "Moving preview cache..."
  mv "$OLD_PREVIEW_CACHE"/* "$NEW_CACHE_DIR/" 2>/dev/null || true
  PREVIEW_COUNT=$(ls -1 "$NEW_CACHE_DIR" 2>/dev/null | wc -l | xargs)
  success "Moved $PREVIEW_COUNT preview images to $NEW_CACHE_DIR"
else
  info "No preview cache to migrate"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Migration Complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "New locations:"
echo "  History:  $NEW_STATE_DIR/history.jsonl"
echo "  Cache:    $NEW_CACHE_DIR/"
echo ""
echo "Record counts:"
TOTAL_RECORDS=$(wc -l < "$NEW_STATE_DIR/history.jsonl" | xargs)
echo "  Total records: $TOTAL_RECORDS"
echo ""
echo "Next steps:"
echo "  1. Verify: head -5 $NEW_STATE_DIR/history.jsonl"
echo "  2. Update storage.sh to use new paths"
echo "  3. Remove old symlinks from dotfiles"
echo "  4. Delete old data: rm -rf $OLD_CONFIG_DIR"
echo ""
warn "Do NOT delete old data until storage.sh is updated and tested!"
