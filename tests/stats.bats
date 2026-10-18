#!/usr/bin/env bats
# What `font rank`, `font stats` and the per-font page read out of the history.
#
# Usage time is reconstructed from the gap to the next apply, and the open-ended
# last apply counts only for the font on screen. No fixture applies the font the
# sandbox reads as current, so every duration here is closed.

load "$HOME/.local/lib/bats-support/load.bash"
load "$HOME/.local/lib/bats-assert/load.bash"

setup() {
  load "$BATS_TEST_DIRNAME/helpers.bash"
  isolate_font_state
  source_font_libs
}

# Font names in the order `font rank` prints them, both sections in turn.
rank_order() {
  "$FONT_ROOT/bin/font" rank \
    | sed $'s/\e\[[0-9;]*m//g' \
    | awk '/^ *[0-9]+\. / { print $2, $3 }'
}

@test "font rank sorts by likes and by hours apart, over curated unrejected fonts" {
  use_fixture_font_registry "Liked Mono" "Used Mono" "Rejected Mono"
  add_history_record "2025-01-01T00:00:00Z" "Used Mono" apply
  add_history_record "2025-01-03T00:00:00Z" "Liked Mono" apply
  add_history_record "2025-01-03T01:00:00Z" "Liked Mono" like
  add_history_record "2025-01-03T02:00:00Z" "Used Mono" apply
  add_history_record "2025-01-04T02:00:00Z" "Liked Mono" apply
  add_history_record "2025-01-05T00:00:00Z" "Rejected Mono" like
  add_history_record "2025-01-05T00:00:01Z" "Rejected Mono" like
  add_history_record "2025-01-05T00:00:02Z" "Rejected Mono" reject "too thin"
  add_history_record "2025-01-05T00:00:03Z" "Stray Mono" like
  add_history_record "2025-01-05T00:00:04Z" "Stray Mono" like

  run rank_order
  assert_success
  assert_output "Liked Mono
Used Mono
Used Mono
Liked Mono"
}

@test "back-to-back applies of one font are one session" {
  add_history_record "2026-01-01T10:00:00Z" "Session Mono" apply
  add_history_record "2026-01-01T11:00:00Z" "Session Mono" apply
  add_history_record "2026-01-01T12:00:00Z" "Other Mono" apply
  add_history_record "2026-01-01T13:00:00Z" "Session Mono" apply

  run pipeline "get_font_usage_stats 'Session Mono' | jq -c '[.sessions, .usage_seconds]'"
  assert_success
  assert_output "[2,7200]"
}

@test "discovery counts a font in the month it was first applied, never again" {
  add_history_record "2026-01-05T10:00:00Z" "First Mono" apply
  add_history_record "2026-01-20T10:00:00Z" "Second Mono" apply
  add_history_record "2026-02-10T10:00:00Z" "First Mono" apply
  add_history_record "2026-03-01T10:00:00Z" "Third Mono" apply

  run pipeline "get_stats_discovery | jq -c 'map([.month, .count])'"
  assert_success
  assert_output '[["2026-01",2],["2026-03",1]]'
}
