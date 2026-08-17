#!/usr/bin/env bats
# The merge rule, which is the whole reason the gist holds one file per machine.
#
# A union merge cannot express a deletion. Every machine may assert every row, so
# a row removed on one machine is restored by the next machine to sync from a
# copy that still holds it. One writer per file makes a removal an ordinary edit.
#
# Nothing here reaches the network: _sync_merge_histories takes the remote files'
# contents as a string, which is exactly what sync_pull assembles from them.

load "$HOME/.local/lib/bats-support/load.bash"
load "$HOME/.local/lib/bats-assert/load.bash"

setup() {
  load "$BATS_TEST_DIRNAME/helpers.bash"
  isolate_font_state
  source_font_libs
}

record() {
  local ts="$1" machine="$2" font="$3" action="$4"
  printf '{"ts":"%s","machine":"%s","terminal":"ghostty","font":"%s","action":"%s"}' \
    "$ts" "$machine" "$font" "$action"
}

@test "a row this machine deleted stays deleted when another machine still has it" {
  # The failure the split exists to prevent. Under a union merge the peer's copy
  # re-asserts the row on every sync, forever.
  add_history_record "2025-01-01T00:00:00Z" "Fira Code" apply "" archlinux

  local peer
  peer="$(record 2025-01-02T00:00:00Z macmini "Iosevka" apply)
$(record 2025-01-03T00:00:00Z macmini "Fira Code" reject)"

  run _sync_merge_histories "$FONT_HISTORY_FILE" archlinux "$peer"
  assert_success
  assert_equal "${#lines[@]}" 3

  : >"$FONT_HISTORY_FILE"
  run _sync_merge_histories "$FONT_HISTORY_FILE" archlinux "$peer"
  assert_success
  assert_equal "${#lines[@]}" 2
  refute_output --partial '"font":"Fira Code","action":"apply"'
}

@test "a row another machine deleted disappears from here too" {
  add_history_record "2025-01-01T00:00:00Z" "Fira Code" apply "" archlinux
  add_history_record "2025-01-02T00:00:00Z" "Iosevka" apply "" macmini

  run _sync_merge_histories "$FONT_HISTORY_FILE" archlinux "$(record 2025-01-05T00:00:00Z macmini "Monaspice Ne Nerd Font" apply)"
  assert_success
  assert_equal "${#lines[@]}" 2
  refute_output --partial '"font":"Iosevka"'
  assert_output --partial '"font":"Monaspice Ne Nerd Font"'
}

@test "this machine's own rows come from local, never from its remote file" {
  # sync_pull skips this machine's own file for exactly this reason. A row
  # written since the last push lives only in the local file.
  add_history_record "2025-01-09T00:00:00Z" "Fira Code" apply "" archlinux

  run _sync_merge_histories "$FONT_HISTORY_FILE" archlinux ""
  assert_success
  assert_equal "${#lines[@]}" 1
  assert_output --partial '"font":"Fira Code"'
}

@test "a row in a peer's file claiming this machine is ignored" {
  : >"$FONT_HISTORY_FILE"

  run _sync_merge_histories "$FONT_HISTORY_FILE" archlinux "$(record 2025-01-02T00:00:00Z archlinux "Fira Code" reject)"
  assert_success
  assert_output ""
}

@test "the merge normalizes the machine before deciding whose row it is" {
  # 306 records in the real history spell this machine "macos-Macmini". Without
  # normalization they belong to no machine and vanish from every file.
  add_history_record "2025-01-01T00:00:00Z" "Fira Code" apply "" "macos-Macmini"

  run _sync_merge_histories "$FONT_HISTORY_FILE" macmini ""
  assert_success
  assert_equal "${#lines[@]}" 1
  assert_output --partial '"machine":"macmini"'
}

@test "the merge normalizes font names on both sides" {
  add_history_record "2025-01-01T00:00:00Z" "RobotoMono Nerd Font" apply "" archlinux

  run _sync_merge_histories "$FONT_HISTORY_FILE" archlinux ""
  assert_success
  assert_output --partial '"font":"Roboto Mono Nerd Font"'
}

@test "the merged output is sorted by timestamp and free of duplicates" {
  add_history_record "2025-01-05T00:00:00Z" "Fira Code" apply "" archlinux

  local peer
  peer="$(record 2025-01-01T00:00:00Z macmini "Iosevka" apply)
$(record 2025-01-01T00:00:00Z macmini "Iosevka" apply)"

  run _sync_merge_histories "$FONT_HISTORY_FILE" archlinux "$peer"
  assert_success
  assert_equal "${#lines[@]}" 2
  assert_line --index 0 --partial '2025-01-01'
  assert_line --index 1 --partial '2025-01-05'
}

@test "the pre-split history.jsonl is not one of the per-machine files" {
  # A machine on an older release still writes the whole merged set to that name.
  run grep -E '^history-.+\.jsonl$' <<<"history.jsonl"
  assert_failure

  run grep -E '^history-.+\.jsonl$' <<<"history-archlinux.jsonl"
  assert_success
}

@test "the filename carries this machine's id" {
  run _sync_history_filename
  assert_success
  assert_output "history-$(get_machine_id).jsonl"
}

@test "_sync_own_records emits only this machine's rows, sorted" {
  add_history_record "2025-01-03T00:00:00Z" "Fira Code" apply "" archlinux
  add_history_record "2025-01-01T00:00:00Z" "Iosevka" apply "" macmini
  add_history_record "2025-01-02T00:00:00Z" "Monaspice Ne Nerd Font" apply "" archlinux

  run _sync_own_records archlinux
  assert_success
  assert_equal "${#lines[@]}" 2
  assert_line --index 0 --partial '"font":"Monaspice Ne Nerd Font"'
  assert_line --index 1 --partial '"font":"Fira Code"'
}
