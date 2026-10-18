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

bats_require_minimum_version 1.5.0

setup() {
  load "$BATS_TEST_DIRNAME/helpers.bash"
  isolate_font_state
  source_font_libs
}

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

@test "every verb on the help screen answers --help and -h with its own rows, without acting" {
  local verbs verb help rows
  verbs=$(help_screen_verbs)
  [[ -n "$verbs" ]] || fail "the help screen yielded no verbs"

  while read -r verb; do
    run "$FONT_ROOT/bin/font" "$verb" --help
    [[ "$status" -eq 0 ]] || fail "font $verb --help exited $status: $output"
    help="$output"
    # The synopsis is the block under "Usage:", up to the first blank line.
    rows=$(awk '/^Usage:$/ { u = 1; next } u && /^$/ { exit } u' <<<"$help")
    [[ -n "$rows" ]] || fail "font $verb --help printed no synopsis: $help"
    if grep -v -E -- "^  font $verb( |\$)" <<<"$rows"; then
      fail "font $verb --help printed a row for another verb"
    fi

    run "$FONT_ROOT/bin/font" "$verb" -h
    [[ "$status" -eq 0 && "$output" == "$help" ]] || fail "font $verb -h differs from --help: $output"
    assert_no_history
  done <<<"$verbs"
}

@test "a mistyped command exits 2 with its error on stderr and nothing on stdout" {
  run --separate-stderr "$FONT_ROOT/bin/font" nonsense
  assert_failure 2
  assert_output ""
  assert_stderr --partial "Unknown command: nonsense"
}
