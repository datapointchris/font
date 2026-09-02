# Font - Claude Code Instructions

## Dev vs Prod Data (CRITICAL)

**direnv sets `FONT_ENV=development` in this repo directory.** This means any `font` command run from here (or by Claude Code whose cwd is this repo) reads/writes `.dev-data/`, NOT the real history at `~/.local/state/font/`.

- To test against **prod data**: run `FONT_ENV= font <command>` or run from outside this directory
- To test against **dev data**: just run normally from this directory
- `.dev-data/` is gitignored. Regenerate a realistic fixture (managed font names, months of history for the sparkline/discovery, both divergence cases, a rejected font) with `scripts/seed-dev-data.sh`
- The installed prod binary is at `~/.local/bin/font` -> `~/.local/share/font/bin/font`
- Prod uses git tag checkout (not main), so `font update` only gets tagged releases

If rank/history/current looks wrong, check which data directory you're hitting first.

## The Gist holds one history file per machine

A union merge cannot express a deletion. Every machine may assert every row, so a row removed here is put back by the next machine to sync from a copy that still holds it.

Each machine writes only `history-<machine>.jsonl`. `_sync_merge_histories` takes every other machine's file as authoritative and keeps only this machine's rows from the local file, so removing a row you wrote is an ordinary edit no peer can undo. The machine normalizer runs on both sides, because ownership is decided by `.machine` and 306 real records spell this fleet's Mac `macos-Macmini`.

The pre-split `history.jsonl` is left in the Gist and never read: a machine on an older release still writes the whole merged set there, and its rows arrive under the new name the first time it pushes after updating. `scripts/split-gist-history.sh` is the one-time split, and it seeds *every* machine's file rather than only the one it runs on — an unseeded machine would vanish from the others' rankings until it updated.

The local `history.jsonl` does not change shape. It stays one merged file and `lib/storage.sh` never learns the Gist holds more than one.

## A value that starts with a dash is read as a flag

Three places got this wrong at once, and one help request tripped all three.

- **Never `| xargs` to trim.** With no command `xargs` runs `echo`, so a ghostty `font-family` of `--help` reads back as `Usage: echo [SHORT-OPTION]... [STRING]...`, and that string was written into history as a font name. It also strips quotes and fails on an unmatched one. `font_trim` in `lib/lib.sh` is the replacement, and `lib/terminal.sh` sources `lib.sh` to get it. The surviving `wc -l | xargs` calls trim a count and are safe.
- **`grep -F -- "$pattern"`.** Without the separator `grep -Fxq --help` prints grep's help and exits 0 on GNU grep, so `font apply --help` validated and applied a font named `--help`.
- **Every verb answers `--help` before dispatch.** The rating verbs read their message as `"$*"`, so the flag became the reason and `font reject --help` hid a real font.

`tests/flag-arguments.bats` pins all three.

## Tests are bats; `tests/test` is not what CI runs

CI runs `bats -r tests`. `tests/test` is a separate hand-rolled runner it never executes, so a check that has to gate a merge belongs in a `.bats` file using `tests/helpers.bash`.

## `font random` weights by recency, and every managed font stays reachable

`compute_font_weights` scores each candidate from days since its last apply, and `weighted_random_choice` samples that distribution. Apply count is the wrong axis: measured 2026-08-19, the 11 managed fonts spanned 17 to 33 applies with eight of them level on 17, while days since last use spanned the full range.

Narrowing the draw to the minimum-count set makes a newly added font the only thing `random` can return until it catches the pack up. `list_fonts_active` is what the draw reads, and it goes through `get_history` — every font in `_JQ_NORMALIZE_FONT_NAMES` is named one way in the registry and another in the history, so a raw read compares `Fira Code Nerd Font` against a rejection filed as `FiraCode Nerd Font` and finds nothing.
