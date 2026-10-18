#!/usr/bin/env bats
# size-up and size-down move this machine's chosen size, and each font draws
# that choice scaled to its digit height. Reading a scaled size back as the
# choice would compound it on every apply.

load "$HOME/.local/lib/bats-support/load.bash"
load "$HOME/.local/lib/bats-assert/load.bash"

setup() {
  load "$BATS_TEST_DIRNAME/helpers.bash"
  isolate_font_state
  export FONT_REGISTRY_FILE="$BATS_TEST_TMPDIR/font-registry.json"
  jq -n '{
    "Half Height": {managed: true, digit_height: 0.37},
    "Reference Height": {managed: true, digit_height: 0.74}
  }' >"$FONT_REGISTRY_FILE"
  source_font_libs
}

# Apply and size-up reload every running Ghostty and kitty, which here would be
# the developer's own. ghostty_reload asks pgrep first.
pgrep() { return 1; }
pkill() { :; }

ghostty_written_size() {
  font_trim "$(grep '^font-size' "$GHOSTTY_CONFIG_FILE" | cut -d= -f2)"
}

@test "a size-up holds across font changes, scaled to each font" {
  ghostty_set_font "Half Height"
  assert_equal "$(ghostty_written_size)" 34

  run change_font_size 1
  assert_success
  assert_output "17 → 18, which Half Height draws at 36"
  assert_equal "$(ghostty_written_size)" 36

  ghostty_set_font "Reference Height"
  assert_equal "$(ghostty_written_size)" 18
  ghostty_set_font "Half Height"
  assert_equal "$(ghostty_written_size)" 36
}
