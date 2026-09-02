#!/usr/bin/env bash
# Shared helpers. Sourced by every .bats file.
#
# tests/test is a separate hand-rolled runner and is not what CI executes — CI
# runs `bats -r tests`, so a check that has to gate a merge belongs in a .bats
# file using these.

FONT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export FONT_ROOT

# Points every path the libraries derive at a sandbox, and MUST run before any
# library is sourced. storage.sh reads FONT_ENV and HOME at *source* time to
# decide where state lives, so overriding them afterwards moves nothing.
#
# FONT_ENV is the one that bites. .envrc sets it to "development" through direnv,
# so a suite inheriting a developer's shell writes into the repo's .dev-data and
# passes while editing state a later manual run reads back.
isolate_font_state() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  unset FONT_ENV

  # Overriding HOME alone does not isolate anything reading an XDG variable, and
  # a developer's shell exports them as absolute paths.
  export XDG_CONFIG_HOME="$HOME/.config"
  export XDG_DATA_HOME="$HOME/.local/share"
  export XDG_STATE_HOME="$HOME/.local/state"
  export XDG_CACHE_HOME="$HOME/.cache"

  # bin/font resolves bashselfupdate through this one, and an exported absolute
  # path reaches the developer's real installation, which checks a remote for a
  # release on every command a test runs.
  export XDG_LIB_HOME="$HOME/.local/lib"
}

# Sources the libraries the way bin/font does. terminal.sh pulls in lib.sh for
# font_trim; the redundant order here mirrors the CLI so the source guard stays
# covered.
source_font_libs() {
  source "$FONT_ROOT/lib/lib.sh"
  source "$FONT_ROOT/lib/storage.sh"
  source "$FONT_ROOT/lib/terminal.sh"
  source "$FONT_ROOT/lib/sync.sh"
}

# Points font discovery at a sandbox registry holding only the names given.
# FONT_REGISTRY_FILE is computed from lib.sh's own location, so without this a
# listing test reads the repo's real registry and its assertions move whenever a
# font is added.
#
# Exported, because a test that runs bin/font rather than calling a library
# function gets a fresh process, and lib.sh takes the exported value over the
# path it derives.
#
# Usage: use_fixture_font_registry "Fixture One" "Fixture Two"
use_fixture_font_registry() {
  export FONT_REGISTRY_FILE="$BATS_TEST_TMPDIR/font-registry.json"

  printf '%s\n' "$@" | jq -R -s '
    split("\n") | map(select(length > 0)) |
    map({key: ., value: {managed: true}}) | from_entries
  ' >"$FONT_REGISTRY_FILE"
}

# Appends one history record. Timestamps are arguments, never generated: the
# ranking and usage-time functions sort and subtract on .ts, so a suite calling
# `date` would assert against a moving target.
#
# printf rather than jq — every value here is a literal the test chose, and one
# process per record is a large fraction of a suite's runtime.
#
# Usage: add_history_record <ts> <font> <action> [message] [machine]
add_history_record() {
  local ts="$1" font="$2" action="$3" message="${4:-}" machine="${5:-archlinux}"
  mkdir -p "$(dirname "$FONT_HISTORY_FILE")"

  if [[ -n "$message" ]]; then
    printf '{"ts":"%s","machine":"%s","terminal":"ghostty","font":"%s","action":"%s","message":"%s"}\n' \
      "$ts" "$machine" "$font" "$action" "$message" >>"$FONT_HISTORY_FILE"
  else
    printf '{"ts":"%s","machine":"%s","terminal":"ghostty","font":"%s","action":"%s"}\n' \
      "$ts" "$machine" "$font" "$action" >>"$FONT_HISTORY_FILE"
  fi
}

# Runs a pipeline in the shell the test is already in, so `run` can capture it.
#
# bats' `run` takes a command, not a pipeline, and `run bash -c "..."` spawns a
# shell with none of the libraries sourced — so a library function called that
# way is simply not found, and the test asserts against an empty output.
#
# Usage: run pipeline "get_history | jq -r '.[].font'"
pipeline() {
  eval "$*"
}
