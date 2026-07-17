# font

Font testing and management with data-driven rankings. Every time you apply, like, dislike, or note a font, it is logged — and rankings emerge from your actual usage rather than opinion. Applies fonts to Ghostty and Neovim in one step, with an interactive picker that shows each font's stats and history as you browse.

## Features

- **Interactive picker** showing per-font stats, history, and metadata (`fzf`)
- **Usage tracking**: like / dislike / note / reject, logged per platform
- **Data-driven rankings** aggregated across all your machines
- **Cross-machine sync** via GitHub Gist
- **Curated font installation** from a GitHub Release
- **Ghostty + Neovim integration**: `apply` updates both and auto-logs the change

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/datapointchris/font/main/install.sh | bash
```

Or manually:

```bash
git clone https://github.com/datapointchris/font.git ~/.local/share/font
ln -sf ~/.local/share/font/bin/font ~/.local/bin/font
```

`font upgrade` (or re-running `install.sh`) pulls the latest version.

### Requirements

- `jq` — JSON history/ranking processing
- `fzf` — interactive picker
- `gh` — GitHub CLI (sync feature and curated-font install)

## Usage

### Viewing

```bash
font current              # Show the active font
font info                 # Browse fonts and view detailed history
font list                 # List all available font families
font rank                 # Fonts ranked by likes/dislikes
font log                  # Complete history with file locations
```

### Applying

```bash
font change               # Interactive picker (shows per-font stats)
font apply <font>         # Apply a font by name (auto-logs)
font random               # Apply a random font
font last                 # Toggle back to the previous font
font size-up              # Increase font size by 1
font size-down            # Decrease font size by 1
```

### Tracking

```bash
font like [message]       # Like the current font, optional reason
font dislike [message]    # Dislike the current font, optional reason
font note <message>       # Add a note to the current font (message required)
font reject <message>     # Reject a font so it stops resurfacing (reason required)
font rejected             # List rejected fonts with reasons
font unreject             # Restore a rejected font (fzf picker with history)
```

### Sync (cross-machine)

```bash
font sync init            # Set up sync via a private GitHub Gist
font sync status          # Show sync status
font sync push            # Force push local history to the gist
font sync pull            # Force pull from the gist
font sync on | off        # Enable / disable auto-sync
```

### Maintenance

```bash
font install              # Install curated fonts from the GitHub Release
font install --check      # Show which curated fonts are missing
font upgrade              # Update font to the latest release
```

## How it works

Each tracking action appends a timestamped JSON record (UTC) to a per-platform history file:

```json
{"ts":"2026-01-04T17:24:03+00:00","platform":"macos","font":"Fira Code","action":"like","message":"Great ligatures"}
```

Rankings aggregate likes and dislikes into a score:

```text
Score = (total likes) − (total dislikes)
```

Fonts are sorted by score descending, then by most recent usage. Rejected fonts are hidden from
`font list` and the picker so you don't keep rediscovering ones you already ruled out.

## Data and sync

History and rankings live in `~/.config/font/`:

```text
~/.config/font/
├── history-<platform>.jsonl     # append-only action log, one file per platform
├── rejected-fonts-<platform>.json
└── font-info.json
```

Each platform writes only its own history and rejection files, so there are **zero merge conflicts**
across machines. `font rank` combines every platform's data to show what you like everywhere. Deleted
history files are recreated automatically on next use. `font sync` mirrors these files through a
private GitHub Gist so a fresh machine inherits your history.
