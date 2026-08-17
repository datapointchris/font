#!/usr/bin/env bats
# Values that start with a dash, and the commands that read them as their own
# flags.
#
# Three places got this wrong at once, and one help request tripped all three:
# `font apply --help` passed a `grep -Fxq "$2"` that read the flag as grep's,
# applied a font named "--help", and wrote it into the ghostty config. The
# getters trimmed that config value with a bare `xargs`, which is `xargs echo`,
# so the current font read back as "Usage: echo [SHORT-OPTION]... [STRING]...".
# The rating verbs then recorded that string as a font name, with "--help" as
# the reason, and the reject hid a real font.

load "$HOME/.local/lib/bats-support/load.bash"
load "$HOME/.local/lib/bats-assert/load.bash"

setup() {
  load "$BATS_TEST_DIRNAME/helpers.bash"
  isolate_font_state
  source_font_libs
}

@test "font_trim keeps a value that starts with a dash" {
  # `xargs` runs echo, so this came back as echo's usage text.
  run font_trim "--help"
  assert_success
  assert_output "--help"
}

@test "font_trim keeps a lone -n rather than swallowing it" {
  # echo -n prints nothing at all, so the value vanished without an error.
  run font_trim "-n"
  assert_success
  assert_output "-n"
}

@test "font_trim survives an apostrophe" {
  # xargs fails outright on an unmatched quote, taking the lookup down with it.
  run font_trim "It's Mono"
  assert_success
  assert_output "It's Mono"
}

@test "font_trim strips surrounding whitespace and nothing else" {
  run font_trim "   Roboto Mono Nerd Font   "
  assert_success
  assert_output "Roboto Mono Nerd Font"
}

@test "font_trim leaves inner spacing alone" {
  run font_trim "  Fira  Code  "
  assert_success
  assert_output "Fira  Code"
}

@test "ghostty_get_font reads back a dash-leading family verbatim" {
  # The whole chain: what apply wrote is what the getter returns.
  mkdir -p "$(dirname "$GHOSTTY_CONFIG_FILE")"
  printf 'font-family = "--help"\n' >"$GHOSTTY_CONFIG_FILE"

  run ghostty_get_font
  assert_success
  assert_output "--help"
  refute_output --partial "Usage: echo"
}

@test "kitty_get_font reads back a dash-leading family verbatim" {
  mkdir -p "$(dirname "$KITTY_CONFIG_FILE")"
  printf 'font_family --help\n' >"$KITTY_CONFIG_FILE"

  run kitty_get_font
  assert_success
  assert_output "--help"
  refute_output --partial "Usage: echo"
}

@test "a font-name check separates the pattern from grep's own flags" {
  # `grep -Fxq --help` prints grep's help and exits 0 on GNU grep, so the name
  # validated and the apply went ahead.
  run bash -c 'printf "Roboto Mono\n" | grep -Fxq -- "--help"'
  assert_failure
}
