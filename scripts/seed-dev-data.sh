#!/usr/bin/env bash
# Populate .dev-data/history.jsonl with a realistic fixture built from the
# current managed font names, so dev mode (FONT_ENV=development, set by direnv
# in this repo) exercises `font rank`, the preview footer, and `font stats`.
#
# The committed .dev-data is gitignored, so this generator is the durable
# artifact — regenerate any time with: scripts/seed-dev-data.sh
#
# Records use the current schema: `machine` is a bare lowercased hostname and
# `platform` is its own field. Data is spread across ~11 months so the monthly
# sparkline and the discovery timeline have something to show, and it includes
# the two divergence cases (used-but-unrated, liked-but-unused) plus a rejected
# font so `font stats` renders every section.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REGISTRY="$APP_DIR/data/font-registry.json"
DATA_DIR="$APP_DIR/.dev-data"
HISTORY="$DATA_DIR/history.jsonl"

# Day-of-month used for each month's events, so different fonts' first-tried
# months stay distinct in the discovery timeline.
DAY="15"

emit() { # ts font action machine platform terminal size [message]
  local ts="$1" font="$2" action="$3" machine="$4" platform="$5" terminal="$6" size="$7" msg="${8:-}"
  jq -nc \
    --arg ts "$ts" --arg font "$font" --arg action "$action" \
    --arg machine "$machine" --arg platform "$platform" --arg terminal "$terminal" \
    --argjson size "$size" --arg msg "$msg" \
    '{
      terminal: $terminal, machine: $machine, platform: $platform,
      in_tmux: true, cols: 120, rows: 40, resolution: "3840x2160",
      font_size: $size, ts: $ts, font: $font, action: $action
    } + (if $msg == "" then {} else {message: $msg} end)' >> "$HISTORY"
}

# seed_applies font machine platform terminal size  month:count ...
seed_applies() {
  local font="$1" machine="$2" platform="$3" terminal="$4" size="$5"
  shift 5
  local seq=0 spec month count i hh mm
  for spec in "$@"; do
    month="${spec%%:*}"
    count="${spec##*:}"
    for ((i = 0; i < count; i++)); do
      hh=$((9 + seq % 8))
      mm=$((5 + (i * 7) % 50))
      seq=$((seq + 1))
      emit "$(printf '%s-%sT%02d:%02d:00Z' "$month" "$DAY" "$hh" "$mm")" \
        "$font" apply "$machine" "$platform" "$terminal" "$size"
    done
  done
}

# rate font machine platform terminal size month action count [message]
rate() {
  local font="$1" machine="$2" platform="$3" terminal="$4" size="$5" month="$6" action="$7" count="$8" msg="${9:-}"
  local i
  for ((i = 0; i < count; i++)); do
    emit "$(printf '%s-%sT1%d:30:00Z' "$month" "$DAY" "$i")" \
      "$font" "$action" "$machine" "$platform" "$terminal" "$size" "$msg"
  done
}

# Guard against registry drift: every font named below must still be managed.
assert_managed() {
  local font="$1"
  jq -e --arg f "$font" '.[$f].managed == true' "$REGISTRY" >/dev/null \
    || { echo "Not a managed font: $font" >&2; exit 1; }
}

mkdir -p "$DATA_DIR"
: > "$HISTORY"

# Fira Code — the heavily-used, well-liked favorite. Applied across many months.
assert_managed "Fira Code Nerd Font"
seed_applies "Fira Code Nerd Font" macmini macos ghostty 14 \
  2025-09:3 2025-11:5 2026-01:6 2026-04:4 2026-07:7
rate "Fira Code Nerd Font" macmini macos ghostty 14 2025-09 like 5 "great ligatures"
rate "Fira Code Nerd Font" macmini macos ghostty 14 2025-09 note 2 "good for prose"

# JetBrains Mono — used a lot but never rated (used_not_liked divergence).
assert_managed "JetBrains Mono Nerd Font"
seed_applies "JetBrains Mono Nerd Font" mbp macos ghostty 15 \
  2025-10:4 2025-12:6 2026-02:8 2026-05:5 2026-06:6

# Iosevka — liked but barely used (liked_not_used divergence).
assert_managed "Iosevka Nerd Font"
seed_applies "Iosevka Nerd Font" macmini macos ghostty 16 2025-11:1 2026-01:1
rate "Iosevka Nerd Font" macmini macos ghostty 16 2025-11 like 4 "beautiful"

# Monaspice Ne — liked, moderate use on the laptop.
assert_managed "Monaspice Ne Nerd Font"
seed_applies "Monaspice Ne Nerd Font" mbp macos ghostty 15 2026-03:5 2026-06:4
rate "Monaspice Ne Nerd Font" mbp macos ghostty 15 2026-03 like 3

# Hack — mixed reception on the arch box.
assert_managed "Hack Nerd Font"
seed_applies "Hack Nerd Font" archlinux archlinux kitty 14 2025-12:3 2026-05:4
rate "Hack Nerd Font" archlinux archlinux kitty 14 2025-12 like 2
rate "Hack Nerd Font" archlinux archlinux kitty 14 2025-12 dislike 1 "too wide"
rate "Hack Nerd Font" archlinux archlinux kitty 14 2025-12 note 1 "decent at 14px"

# Meslo LGM — a little use, one like.
assert_managed "Meslo LGM Nerd Font"
seed_applies "Meslo LGM Nerd Font" macmini macos ghostty 13 2026-02:2
rate "Meslo LGM Nerd Font" macmini macos ghostty 13 2026-02 like 1

# Roboto Mono — disliked.
assert_managed "Roboto Mono Nerd Font"
seed_applies "Roboto Mono Nerd Font" macmini macos ghostty 14 2025-10:1 2025-11:1
rate "Roboto Mono Nerd Font" macmini macos ghostty 14 2025-10 dislike 2 "not for me"

# Comic Mono — neutral, tried briefly.
assert_managed "Comic Mono Nerd Font"
seed_applies "Comic Mono Nerd Font" mbp macos ghostty 16 2026-05:2

# Iosevka Term Slab — the most recent addition on arch.
assert_managed "Iosevka Term Slab Nerd Font"
seed_applies "Iosevka Term Slab Nerd Font" archlinux archlinux kitty 15 2026-07:3

# Comic Shanns Mono — tried, then rejected.
assert_managed "Comic Shanns Mono Nerd Font"
seed_applies "Comic Shanns Mono Nerd Font" macmini macos ghostty 14 2026-04:2
rate "Comic Shanns Mono Nerd Font" macmini macos ghostty 14 2026-04 dislike 2 "too playful"
emit "2026-04-20T12:00:00Z" "Comic Shanns Mono Nerd Font" reject macmini macos ghostty 14 "too clownish for daily use"

# Sort chronologically (history is otherwise append-order; readers sort anyway).
tmp="$(mktemp)"
jq -s -c 'sort_by(.ts) | .[]' "$HISTORY" > "$tmp"
mv "$tmp" "$HISTORY"

echo "Seeded $(wc -l < "$HISTORY" | tr -d ' ') records to $HISTORY"
