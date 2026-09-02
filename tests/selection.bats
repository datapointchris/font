#!/usr/bin/env bats
# What `font random` draws from, and how the draw is weighted.
#
# Two properties carry the whole design. Every managed font is reachable on any
# draw, and a rejected font is reachable on none. Anything that narrows the draw
# to a subset — the lowest apply count, the newest arrival — reads as a broken
# shuffle: the tool keeps returning the same few fonts and the rest of the
# library is unreachable until that subset changes.

load "$HOME/.local/lib/bats-support/load.bash"
load "$HOME/.local/lib/bats-assert/load.bash"

setup() {
  load "$BATS_TEST_DIRNAME/helpers.bash"
  isolate_font_state
  source_font_libs
}

# Weights are measured against the clock, so the recent end of a fixture has to
# be written relative to now. The distant end does not: any timestamp older than
# FONT_RECENCY_CAP_DAYS clamps to the cap and stays put.
#
# Takes a signed day offset, because one test needs a timestamp in the future.
at_days_offset() {
  date -u -d "$1 days" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -v "${1}d" +%Y-%m-%dT%H:%M:%SZ
}

@test "list_fonts_active drops a rejected font" {
  use_fixture_font_registry "Keeper Mono" "Dropped Mono"
  add_history_record "2025-01-01T00:00:00Z" "Dropped Mono" reject "unreadable italics"

  run list_fonts_active
  assert_output "Keeper Mono"
}

@test "list_fonts_active restores a font whose last action is unreject" {
  use_fixture_font_registry "Restored Mono"
  add_history_record "2025-01-01T00:00:00Z" "Restored Mono" reject "unreadable italics"
  add_history_record "2025-02-01T00:00:00Z" "Restored Mono" unreject

  run list_fonts_active
  assert_output "Restored Mono"
}

@test "compute_font_weights gives a never-applied font the capped weight" {
  run pipeline 'echo "Unseen Mono" | compute_font_weights'
  assert_output "Unseen Mono	$((1 + FONT_RECENCY_CAP_DAYS / FONT_RECENCY_SCALE_DAYS))"
}

@test "compute_font_weights carries a name containing spaces through intact" {
  # Every managed font is named with spaces, and the pipe into the picker is
  # tab-separated for exactly that reason.
  add_history_record "2020-01-01T00:00:00Z" "Iosevka Term Slab Nerd Font" apply

  run pipeline 'echo "Iosevka Term Slab Nerd Font" | compute_font_weights | cut -f1'
  assert_output "Iosevka Term Slab Nerd Font"
}

@test "compute_font_weights weighs a long-unused font above a recent one" {
  add_history_record "2020-01-01T00:00:00Z" "Stale Mono" apply
  add_history_record "$(at_days_offset 0)" "Fresh Mono" apply

  local stale_weight fresh_weight
  stale_weight=$(echo "Stale Mono" | compute_font_weights | cut -f2)
  fresh_weight=$(echo "Fresh Mono" | compute_font_weights | cut -f2)

  run awk -v a="$stale_weight" -v b="$fresh_weight" 'BEGIN { print (a > b) ? "yes" : "no" }'
  assert_output "yes"
}

@test "compute_font_weights floors a future-dated apply at the minimum weight" {
  # Another machine with a skewed clock dates an apply ahead of now, which
  # subtracts to a negative age and would otherwise weigh below every peer.
  add_history_record "$(at_days_offset +30)" "Skewed Mono" apply

  run pipeline 'echo "Skewed Mono" | compute_font_weights | cut -f2'
  assert_output "1"
}

@test "weighted_random_choice returns the only candidate" {
  run pipeline "printf 'Solo Mono\t1\n' | weighted_random_choice"
  assert_output "Solo Mono"
}

@test "weighted_random_choice fails on empty input" {
  run pipeline "printf '' | weighted_random_choice"
  assert_failure
}

@test "weighted_random_choice never returns a zero-weight candidate" {
  for _ in $(seq 20); do
    run pipeline "printf 'Live Mono\t1\nZero Mono\t0\n' | weighted_random_choice"
    assert_output "Live Mono"
  done
}

@test "weighted_random_choice reaches every candidate" {
  # Also pins the seeding: awk's bare srand() takes the clock in whole seconds,
  # so a loop this fast would return one name 40 times and leave two of the
  # three unreached.
  local drawn
  drawn=$(for _ in $(seq 40); do
    printf 'One Mono\t1\nTwo Mono\t1\nThree Mono\t1\n' | weighted_random_choice
  done | sort -u | wc -l)

  assert_equal "$drawn" 3
}

@test "weighted_random_choice favours the heavier candidate" {
  local heavy=0
  for _ in $(seq 40); do
    [[ "$(printf 'Heavy Mono\t9\nLight Mono\t1\n' | weighted_random_choice)" == "Heavy Mono" ]] && heavy=$((heavy + 1))
  done

  # 9:1 over 40 draws; a fair sampler clears half by a margin no seed explains.
  run awk -v n="$heavy" 'BEGIN { print (n > 20) ? "yes" : "no" }'
  assert_output "yes"
}
