#!/usr/bin/env bats
# The picker verbs from a script. fzf on a stdin that is not a terminal waits
# for input that never comes, so each picker exits 2 instead, and every one has
# a form that takes the font as an argument.

load "$HOME/.local/lib/bats-support/load.bash"
load "$HOME/.local/lib/bats-assert/load.bash"

setup() {
  load "$BATS_TEST_DIRNAME/helpers.bash"
  isolate_font_state
  source_font_libs
  use_fixture_font_registry "Roboto Mono" "Hack Nerd Font"
}

@test "change, info and unreject exit 2 on a stdin that is not a terminal, and write nothing" {
  add_history_record "2026-01-01T00:00:00Z" "Hack Nerd Font" "reject" "too wide"
  local before verb
  before=$(cat "$FONT_HISTORY_FILE")

  for verb in change info unreject; do
    run timeout 10 "$FONT_ROOT/bin/font" "$verb" </dev/null
    [[ "$status" -eq 2 ]] || fail "font $verb on a closed stdin exited $status: $output"
  done
  [[ "$(cat "$FONT_HISTORY_FILE")" == "$before" ]] || fail "history written: $(cat "$FONT_HISTORY_FILE")"
}

@test "unreject with a font name records the unreject, and refuses a font that is not rejected" {
  add_history_record "2026-01-01T00:00:00Z" "Hack Nerd Font" "reject" "too wide"

  run "$FONT_ROOT/bin/font" --no-input unreject "Roboto Mono"
  assert_failure 2

  run "$FONT_ROOT/bin/font" --no-input unreject "Hack Nerd Font"
  assert_success
  run get_rejected_font_ids
  assert_output ""
  [[ "$(tail -n 1 "$FONT_HISTORY_FILE" | jq -r '.action + " " + .font')" == "unreject Hack Nerd Font" ]] \
    || fail "last record: $(tail -n 1 "$FONT_HISTORY_FILE")"
}
