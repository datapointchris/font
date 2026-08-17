#!/usr/bin/env bats
# `font <verb> --help`, at every level of the command tree.
#
# The verbs carrying free text read it as "$*", so a --help reaching one becomes
# the message rather than a request for help: `font reject --help` hides the
# current font with "--help" as the reason, and `like`/`dislike`/`note` write a
# history record saying the same. main() answers the flag before dispatch.
#
# The verb list is read out of the help screen rather than written here, so a
# command added to the table is covered without a new test.

load "$HOME/.local/lib/bats-support/load.bash"
load "$HOME/.local/lib/bats-assert/load.bash"

setup() {
  load "$BATS_TEST_DIRNAME/helpers.bash"
  isolate_font_state
  source_font_libs
}

# The plain fallback screen is what a sandboxed HOME gets, since the formatting
# library is not there to load.
help_screen_verbs() {
  "$FONT_ROOT/bin/font" help \
    | sed -n '/^Commands$/,/^Examples$/p' \
    | awk '/^  [a-z]/ { print $1 }' | sort -u
}

assert_no_history() {
  [[ ! -s "$FONT_HISTORY_FILE" ]] || {
    echo "history written by a help request:" >&2
    cat "$FONT_HISTORY_FILE" >&2
    return 1
  }
}

@test "the help screen lists every verb the table carries" {
  run help_screen_verbs
  assert_success
  assert_line "reject"
  assert_line "apply"
  assert_line "sync"
  assert_line "install"
}

@test "every verb on the help screen answers --help without acting" {
  local verb
  while read -r verb; do
    run "$FONT_ROOT/bin/font" "$verb" --help
    [[ "$status" -eq 0 ]] || fail "font $verb --help exited $status: $output"
    [[ -n "$output" ]] || fail "font $verb --help printed nothing"
    assert_no_history
  done < <(help_screen_verbs)
}

@test "every verb answers -h the same way" {
  local verb
  while read -r verb; do
    run "$FONT_ROOT/bin/font" "$verb" -h
    [[ "$status" -eq 0 ]] || fail "font $verb -h exited $status: $output"
    assert_no_history
  done < <(help_screen_verbs)
}

@test "a flat verb gets its own synopsis, not the whole screen" {
  run "$FONT_ROOT/bin/font" reject --help
  assert_success
  assert_line "  font reject <message>     Mark current font as rejected (avoids rediscovery)"
  refute_line "Font Management"
}

@test "a verb with several rows prints all of them" {
  run "$FONT_ROOT/bin/font" sync --help
  assert_success
  assert_line "  font sync init            Set up cross-machine sync via GitHub Gist"
  assert_line "  font sync on              Re-enable auto-sync"
}

@test "an unknown verb falls back to the full screen" {
  run "$FONT_ROOT/bin/font" nonsense --help
  assert_success
  assert_output --partial "Font Management"
}

@test "font apply --help does not reach the font-name check" {
  # Without the guard this passed a grep that read the flag as its own, applied a
  # font called "--help", and wrote it into the terminal config.
  run "$FONT_ROOT/bin/font" apply --help
  assert_success
  assert_output --partial "font apply <font>"
  assert_no_history
}

@test "font help still renders the commands and the examples" {
  run "$FONT_ROOT/bin/font" help
  assert_success
  assert_line "Commands"
  assert_line "Examples"
  assert_line "  reject <message>     Mark current font as rejected (avoids rediscovery)"
}
