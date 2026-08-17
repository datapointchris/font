#!/usr/bin/env bash
# Split the gist's single history.jsonl into one file per machine.
#
# Usage: scripts/split-gist-history.sh [--apply]
#        (prints the split without writing unless --apply is given)
#
# Run once, from a machine whose local history holds every machine's records.
# Seeding every machine's file here — not just this one's — is the point: a
# machine that has not updated yet writes nothing under the new names, and an
# updated machine reads only those, so any machine left unseeded would vanish
# from every other machine's rankings until it updated.
#
# The pre-split history.jsonl is left in place. A machine on an older release
# still reads and writes it, and its rows arrive under the new scheme when that
# machine updates and pushes its own file for the first time.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/storage.sh"

APPLY=false
[[ "${1:-}" == "--apply" ]] && APPLY=true

GIST_ID=$(jq -r '.gist_id // empty' "${FONT_STATE_DIR}/sync-state.json")
if [[ -z "$GIST_ID" ]]; then
  echo "No gist configured. Run: font sync init" >&2
  exit 1
fi

REMOTE=$(gh gist view "$GIST_ID" --filename history.jsonl --raw 2>/dev/null || true)
if [[ -z "$REMOTE" ]]; then
  echo "Gist $GIST_ID has no history.jsonl to split" >&2
  exit 1
fi

# Both sides, normalized, so a machine whose label drifted lands in one file
# rather than two.
MERGED=$(
  {
    [[ -f "$FONT_HISTORY_FILE" ]] && cat "$FONT_HISTORY_FILE"
    echo "$REMOTE"
  } | jq -s -c "
    flatten |
    map(select(. != null and . != {} and type == \"object\")) |
    map($_JQ_NORMALIZE_FONT_NAMES | $_JQ_NORMALIZE_MACHINE) |
    unique_by([.ts, .machine, .font, .action]) |
    sort_by(.ts) | .[]
  "
)

MACHINES=$(echo "$MERGED" | jq -r '.machine' | sort -u)

echo "Gist:     $GIST_ID"
echo "Records:  $(echo "$MERGED" | wc -l | xargs)"
echo ""

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

EXISTING=$(gh gist view "$GIST_ID" --files 2>/dev/null || true)

while IFS= read -r machine; do
  [[ -z "$machine" ]] && continue
  filename="history-${machine}.jsonl"
  echo "$MERGED" | jq -c --arg m "$machine" 'select(.machine == $m)' >"$TMPDIR/$filename"
  printf '  %-28s %s records\n' "$filename" "$(wc -l <"$TMPDIR/$filename" | xargs)"

  if $APPLY; then
    if grep -qxF "$filename" <<<"$EXISTING"; then
      gh gist edit "$GIST_ID" --filename "$filename" "$TMPDIR/$filename"
    else
      gh gist edit "$GIST_ID" --add "$TMPDIR/$filename"
    fi
  fi
done <<<"$MACHINES"

echo ""
if $APPLY; then
  echo "✓ Written. history.jsonl left in place for machines on an older release."
else
  echo "Dry run. Re-run with --apply to write these to the gist."
fi
