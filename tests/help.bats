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

# The bare words a command starts with, before its first flag or placeholder:
# `list --status <s>` is `list`, `sync init` is `sync init`.
leading_words() {
  awk '{ out = ""; for (i = 1; i <= NF && $i ~ /^[a-z][a-z-]*$/; i++) out = out (out ? " " : "") $i; print out }'
}

# Each command the help screen's table names. A row's synopsis ends at the
# first run of two spaces, where its description starts.
help_screen_commands() {
  "$FONT_ROOT/bin/font" help \
    | sed -n '/^Commands$/,/^Examples$/p' \
    | grep '^  [a-z]' | sed -E 's/^  //; s/  .*//' | leading_words | sort -u
}

# Each command a hint tells the reader to run: quoted as 'font ...' in the
# source, or passed to require_picker for its no-terminal error.
hinted_commands() {
  {
    grep -ho "'font [^']*'" "$FONT_ROOT/bin/font" "$FONT_ROOT"/lib/*.sh | tr -d "'"
    grep -ho 'require_picker "font [^"]*"' "$FONT_ROOT/bin/font" \
      | sed 's/^require_picker //' | tr -d '"'
  } | sed 's/^font //' | leading_words | sort -u
}

assert_no_history() {
  [[ ! -s "$FONT_HISTORY_FILE" ]] || {
    echo "history written by a help request:" >&2
    cat "$FONT_HISTORY_FILE" >&2
    return 1
  }
}

@test "every command on the help screen answers --help with its own rows without acting, and -h matches it" {
  local commands verb rows words
  commands=$(help_screen_commands)
  [[ -n "$commands" ]] || fail "the help screen yielded no commands"

  # A subverb such as `sync push` is read as two words.
  while read -r -a words; do
    verb="${words[*]}"
    run "$FONT_ROOT/bin/font" "${words[@]}" --help
    [[ "$status" -eq 0 ]] || fail "font $verb --help exited $status: $output"
    # The synopsis is the block under "Usage:", up to the first blank line.
    rows=$(awk '/^Usage:$/ { u = 1; next } u && /^$/ { exit } u' <<<"$output")
    [[ -n "$rows" ]] || fail "font $verb --help printed no synopsis: $output"
    if grep -v -E -- "^  font $verb( |\$)" <<<"$rows"; then
      fail "font $verb --help printed a row for another verb"
    fi
    assert_no_history
  done <<<"$commands"

  # main() matches -h and --help in one case arm, so one verb proves -h.
  local help
  help=$("$FONT_ROOT/bin/font" reject --help)
  run "$FONT_ROOT/bin/font" reject -h
  [[ "$status" -eq 0 && "$output" == "$help" ]] || fail "font reject -h differs from --help: $output"
  assert_no_history
}

@test "every command a hint names is a command on the help screen" {
  local commands hinted missing
  commands=$(help_screen_commands)
  hinted=$(hinted_commands)
  [[ -n "$hinted" ]] || fail "no hint was found in the source"

  missing=$(comm -23 <(echo "$hinted") <(echo "$commands"))
  [[ -z "$missing" ]] || fail "hints name commands the help screen does not list: $missing"
}

@test "a mistyped command exits 2 with its error on stderr and nothing on stdout" {
  run --separate-stderr "$FONT_ROOT/bin/font" nonsense
  assert_failure 2
  assert_output ""
  assert_stderr --partial "Unknown command: nonsense"
}

@test "a mistyped command suggests the verbs it is near" {
  run "$FONT_ROOT/bin/font" rnak
  assert_failure 2
  local suggested
  suggested=$(printf '%s\n' "$output" | sed -n '/^Did you mean:$/,/^$/p' | awk '/^  / { print $1 }')
  [[ "$suggested" == "rank" ]] || fail "suggested: $suggested"
}
