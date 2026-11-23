#!/usr/bin/env bats
# `font current show --json`, which a desktop binding runs with no terminal around it.

load "$HOME/.local/lib/bats-support/load.bash"
load "$HOME/.local/lib/bats-assert/load.bash"

bats_require_minimum_version 1.5.0

setup() {
  load "$BATS_TEST_DIRNAME/helpers.bash"
  # uvx keeps check-jsonschema in these, and isolate_font_state moves HOME away from them.
  if command -v uv &>/dev/null; then
    UV_CACHE_DIR=$(uv cache dir) UV_PYTHON_INSTALL_DIR=$(uv python dir)
    export UV_CACHE_DIR UV_PYTHON_INSTALL_DIR
  fi
  isolate_font_state
  source_font_libs
  unset GHOSTTY_RESOURCES_DIR KITTY_WINDOW_ID WT_SESSION
}

@test "font current show --json reads this machine's latest apply outside a terminal" {
  add_apply_record "2026-11-01T10:00:00Z" "Hack Nerd Font" "schedule" "$(get_machine_id)"
  add_apply_record "2026-11-02T10:00:00Z" "JetBrains Mono" "manual" "another-machine"
  set_terminal_base_size 15

  run --separate-stderr "$FONT_ROOT/bin/font" current show --json
  assert_success
  assert_equal "$(jq -c '[.family, .size, .applied_at, .trigger]' <<<"$output")" \
    '["Hack Nerd Font",15,"2026-11-01T10:00:00Z","schedule"]'

  command -v uvx &>/dev/null || fail "uvx validates the output against its schema, and it is not on PATH"
  printf '%s\n' "$output" >"$BATS_TEST_TMPDIR/current-show.json"
  run uvx check-jsonschema@0.39.0 \
    --schemafile "$FONT_ROOT/schemas/current-show.schema.json" "$BATS_TEST_TMPDIR/current-show.json"
  assert_success
}
