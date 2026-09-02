# font

Font testing and management with data-driven rankings. Every time you apply, like, dislike, note, or
reject a font it is logged — and rankings emerge from your actual usage rather than opinion. A single
`apply` updates every terminal on the machine at once (Ghostty, Kitty, Windows Terminal, plus
Arch-specific apps), and an interactive picker shows each font's stats, history, and a usage
sparkline as you browse.

## Features

- **Interactive picker** showing per-font stats, rank position, usage sparkline, and metadata (`fzf`)
- **Usage tracking**: apply / like / dislike / note / reject, logged with full terminal context
- **Data-driven rankings** — one list by likes, one by hours actually used
- **Portfolio stats** — where stated and revealed preference diverge, discovery pace, per-machine favorites
- **Multi-terminal apply**: one command writes Ghostty, Kitty, Windows Terminal (WSL), and Arch apps
- **Cross-machine sync** via a private GitHub Gist
- **Curated font installation** from a GitHub Release

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/datapointchris/font/main/install.sh | bash
```

Or manually:

```bash
git clone https://github.com/datapointchris/font.git ~/.local/share/font
ln -sf ~/.local/share/font/bin/font ~/.local/bin/font
```

`font update` (or re-running `install.sh`) moves the checkout to the latest tagged release.

font also checks once a day and prints one line when a newer release exists:

```text
font v3.2.0 available (running v3.1.0) — run `font update`
```

It never installs anything and never prints an error — a failed check is
recorded and swallowed, because an update notice must not break the command you
typed. Nothing is printed when either stream is not a terminal, under CI, from a
checkout that is not sitting on a release tag, or within the interval. Set
`NO_AUTO_UPDATE` or `FONT_NO_AUTO_UPDATE` to turn it off, and
`FONT_AUTO_UPDATE_INTERVAL=6h` to change the cadence.

### Requirements

- `jq` — JSON history/ranking processing
- `fzf` — interactive picker
- `git` — version reporting and `font update`
- [`bashselfupdate`](https://github.com/datapointchris/bashselfupdate) — `font update` and the
  daily notice; `install.sh` installs it
- `gh` — GitHub CLI (sync and curated-font install)
- `bat` *(optional)* — colorizes `font log` output when present

## Usage

### Viewing

```bash
font current              # Show the active font with its full stats
font info                 # Browse fonts and view detailed history (fzf)
font list                 # List all curated font families
font list --status <s>    # Narrow to one state: active, rejected, all
font rank                 # Two rankings: by likes and by hours used
font stats                # Portfolio dashboard (divergence, discovery, machines)
font log                  # Complete history with terminal context
```

### Applying

```bash
font change               # Interactive picker (rich per-font preview)
font apply <font>         # Apply a font by name (auto-logs)
font random               # Apply a random font, weighted by time since last use
font last                 # Toggle back to the previous font
font size-up              # Increase font size by 1 (all terminals)
font size-down            # Decrease font size by 1 (all terminals)
```

`apply`, `change`, `random`, and `last` all write **every** terminal config on the machine — Ghostty,
Kitty, Windows Terminal (on WSL), and waybar / hyprlock / dunst on Arch — then log the change with the
terminal, machine, size, and screen context it was applied in. Restart the terminal to see all changes.

### Tracking

```bash
font like [message]       # Like the current font, optional reason
font dislike [message]    # Dislike the current font, optional reason
font note <message>       # Add a note to the current font (message required)
font reject <message>     # Reject a font so it stops resurfacing (reason required)
font unreject             # Restore a rejected font (fzf picker with history)
```

Rejection is a state rather than a command of its own, so the rejected families read as `font list
--status rejected`. The flag takes `active`, `rejected` or `all`, and defaults to `all` — the
curated registry is small enough that both halves stay worth seeing, and `font apply` accepts every
name in it. Why a particular font sits where it does reads per font: `font current` and `font info`
render its history, rejection reason included.

### Sync (cross-machine)

```bash
font sync init            # Set up sync via a private GitHub Gist
font sync status          # Show sync status
font sync push            # Force push local history to the gist
font sync pull            # Force pull and merge from the gist
font sync on | off        # Enable / disable auto-sync
```

### Maintenance

```bash
font install              # Install curated fonts from the GitHub Release
font install --check      # Show which curated fonts are missing
font update               # Update font to the latest release
```

## How it works

Each tracking action appends one timestamped JSON record (UTC) to a single history file, capturing the
terminal context it happened in:

```json
{"ts":"2026-01-04T17:24:03Z","font":"Fira Code Nerd Font","action":"apply","terminal":"ghostty","machine":"macmini","platform":"macos","in_tmux":false,"cols":212,"rows":58,"resolution":"3440x1440","font_size":17}
```

The tool tracks two kinds of signal and keeps them separate rather than blending them:

- **Stated preference** — likes and dislikes, aggregated into a score (`likes − dislikes`).
- **Revealed preference** — how long each font was actually active, reconstructed by diffing
  consecutive `apply` timestamps (the current font counts up to now).

`font rank` shows both as separate lists — one **by likes**, one **by hours used** — because a font you
keep reaching for is a different signal than one you clicked "like" on once. `font stats` is a portfolio
dashboard built on the same data: where the two signals diverge (used a lot but never rated, or liked
but rarely used), how many new fonts you try each month, and your most-used font on each machine.

Rejection is itself just a logged action. `reject` and `unreject` append to the same history, and a
font counts as rejected when `reject` is its most recent of the two — so rejected fonts drop out of
`font list`, the picker, and the rankings without a separate state file to keep in sync.

## Data and sync

History lives in a single file under `~/.local/state/font/`:

```text
~/.local/state/font/
├── history.jsonl      # append-only action log (one JSON record per line)
└── sync-state.json    # gist id, last-sync time, enabled flag
```

The curated font families and their metadata (description, creator, license, links) live in the repo at
`data/font-registry.json`; only families flagged `managed` appear in `font list`, the picker, and
`font install`.

`font sync` mirrors `history.jsonl` through a private GitHub Gist. Because every record carries its own
machine and timestamp, pulling merges the two streams by deduplicating on `ts + machine + font + action`
and re-sorting by time — so concurrent edits from different machines combine cleanly with no manual
conflict resolution. Legacy font names are normalized on read, and a deleted history file is recreated
on next use. In this repo, `FONT_ENV=development` (set via direnv) redirects all of the above to a
gitignored `.dev-data/` fixture and disables sync, so testing never touches real history.
