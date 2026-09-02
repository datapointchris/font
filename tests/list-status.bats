#!/usr/bin/env bats
# `font list --status`, the filter that carries rejection.
#
# Rejection is a lifecycle state, so it is a value the listing takes rather than
# a verb of its own — cli-design.md § "A lifecycle is one `--status` enum,
# spelled in the field's own words". The two properties that make it an enum
# rather than a pair of separate listings: the halves partition, and a value
# outside the enum is a usage error rather than an empty list.
#
# These run bin/font rather than the library, because the flag parsing and the
# refusals are the thing under test and they live in the CLI.

load "$HOME/.local/lib/bats-support/load.bash"
load "$HOME/.local/lib/bats-assert/load.bash"

setup() {
  load "$BATS_TEST_DIRNAME/helpers.bash"
  isolate_font_state
  source_font_libs

  use_fixture_font_registry "Keeper Mono" "Dropped Mono"
  add_history_record "2025-01-01T00:00:00Z" "Dropped Mono" reject "unreadable italics"
}

font() {
  "$FONT_ROOT/bin/font" "$@"
}

@test "font list shows the whole registry by default" {
  # The curated registry is bounded, so neither half outgrows the other and both
  # stay worth seeing. `font apply` also validates against the whole registry,
  # so a narrowed default would hide a name the tool still accepts.
  run font list
  assert_success
  assert_line "Keeper Mono"
  assert_line "Dropped Mono"
}

@test "font list --status active drops a rejected font" {
  run font list --status active
  assert_success
  assert_output "Keeper Mono"
}

@test "font list --status rejected keeps only the rejected font" {
  run font list --status rejected
  assert_success
  assert_output "Dropped Mono"
}

@test "font list --status all is the default spelled out" {
  run font list --status all
  assert_success
  assert_line "Keeper Mono"
  assert_line "Dropped Mono"
}

@test "active and rejected partition all" {
  local all halves
  all=$(font list --status all | sort)
  halves=$(
    font list --status active
    font list --status rejected
  )
  halves=$(printf '%s\n' "$halves" | sort)

  [[ "$halves" == "$all" ]] || fail "halves: $halves / all: $all"
}

@test "font list --status=rejected takes the joined form" {
  run font list --status=rejected
  assert_success
  assert_output "Dropped Mono"
}

@test "a font unrejected since is active again" {
  add_history_record "2025-02-01T00:00:00Z" "Dropped Mono" unreject

  run font list --status rejected
  assert_success
  assert_output ""

  run font list --status active
  assert_success
  assert_line "Dropped Mono"
}

@test "a status outside the enum is a usage error, not an empty list" {
  run font list --status nonsense
  assert_failure 2
  assert_output --partial "no such status 'nonsense'"
  assert_output --partial "active|rejected|all"
}

@test "--status with no value is a usage error" {
  run font list --status
  assert_failure 2
  assert_output --partial "--status needs a value"
}

@test "a bare argument to list is a usage error" {
  run font list rejected
  assert_failure 2
  assert_output --partial "takes no argument"
}

@test "rejected is not a verb" {
  run font rejected
  assert_failure
  assert_output --partial "Unknown command: rejected"
}
