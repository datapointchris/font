# font

`font` sets the terminal font on every terminal on the machine at once. It logs every apply, like,
dislike, note and rejection, and its rankings come out of that log. Which font you prefer is read
from how long you kept each one, not only from what you said about it. Sync shares one history
across machines through a GitHub Gist.

Each terminal keeps its own config. `font` owns one small file per app, holding the font family and
size, and your config includes that file. Nothing else in your config is rewritten.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/datapointchris/font/main/install.sh | bash
```

Or from a clone, which runs the same installer without piping it:

```bash
git clone https://github.com/datapointchris/font.git ~/.local/share/font
bash ~/.local/share/font/install.sh
```

The installer clones font into `~/.local/share/font`, moves it to its newest release tag, and links
`~/.local/bin/font`. `FONT_INSTALL_DIR` and `FONT_BIN_DIR` move either path. It also clones
[`bashselfupdate`](https://github.com/datapointchris/bashselfupdate) into `~/.local/lib`. A failure
there is not fatal: every command still runs, and only `font update` and the update notice need it.
Re-running the installer moves an existing checkout to the newest tag rather than cloning again.

`font update` moves the checkout to the newest release tag. It refuses a checkout that is not
sitting on a tag, because that is a development clone and git is the tool for moving it.

font also checks once a day and prints one line when a newer release exists:

```text
font <newer> available (running <current>) — run `font update`
```

It never installs anything and never prints an error. A failed check is recorded and swallowed,
because an update notice must not break the command you typed. Nothing is printed when either
stream is not a terminal, under CI, from a checkout that is not sitting on a release tag, or within
the interval. Set `NO_AUTO_UPDATE` or `FONT_NO_AUTO_UPDATE` to turn it off, and
`FONT_AUTO_UPDATE_INTERVAL=6h` to change the cadence.

### Requirements

- `bash` 4 or newer. On macOS that means Homebrew's, since the system bash is 3.2.
- `jq` — every read of the history and the registry
- `fzf` — `change`, `info` and `unreject`
- `git` — the installer, version reporting and `font update`
- `gh` — `font install` downloads through it, and `font sync` stores history with it
- `bashselfupdate` — `font update` and the daily notice; the installer installs it
- fontconfig — `font install` refreshes the font cache on Linux and WSL
- `bat` *(optional)* — colorizes `font log`

## Starting from scratch

```bash
curl -fsSL https://raw.githubusercontent.com/datapointchris/font/main/install.sh | bash  # font, at its newest release
gh auth login                  # install downloads through gh, and sync keeps history on your account
font install --check           # which curated families this machine already has; installs nothing
font install                   # unpack the curated archive into your user font directory

echo 'include fonts/current.conf' >>~/.config/kitty/kitty.conf          # kitty reads font's file
echo 'config-file = ?fonts/current.conf' >>~/.config/ghostty/config     # ghostty reads it too
echo 'gtk-custom-css = ?fonts/current.css' >>~/.config/ghostty/config   # and its tab labels, on Linux

font change                    # pick a font in fzf and apply it, each one's record previewed beside it
font current                   # the font this terminal's file names, with its record — proof it landed
```

`font install` uses `~/fonts.tar.xz` when one exists and downloads nothing. That is the route for a
machine that cannot reach GitHub. Otherwise it downloads `fonts.tar.xz` from this repository's
`fonts-v1` release. It unpacks into `~/Library/Fonts` on macOS and `~/.local/share/fonts` on Linux.
On WSL it unpacks into the Windows user's font directory and registers each font with Windows.

The include lines are the one edit your config needs. Any font command creates either file when it
is missing, naming `monospace` at size 17. The leading `?` tells Ghostty that a missing file is not
an error. Waybar, Hyprlock and dunst on Arch take their own lines, listed under `apply` below.

`apply` reloads Kitty, and Ghostty on Linux, so their open windows redraw in the new font. It
restarts Waybar, and stops dunst so it reads the drop-in when it next starts. Waybar is restarted
rather than signaled, because Waybar's mpris module can crash on its reload signal. Ghostty on macOS
shows the font after a config reload or in a new window, and `apply` says so there.

Every verb answers `font <verb> --help` with its own synopsis. `font help` lists them all.

## `apply`, `change`, `random`, `last` — one font written to every app at once, and logged

```bash
font apply "Fira Code Nerd Font"   # by name; an unknown name lists the curated names that contain it
font change                        # the fzf picker
font random                        # weighted toward the font you have gone longest without
font last                          # back to the font applied before this one
font size-up                       # one point larger in every terminal; size-down is the reverse
```

Each apply writes every app below that is present, whichever terminal you typed it in:

| App | font writes | Your config adds |
| --- | --- | --- |
| Ghostty | `~/.config/ghostty/fonts/current.conf`, and `current.css` beside it | `config-file = ?fonts/current.conf` and `gtk-custom-css = ?fonts/current.css` |
| Kitty | `~/.config/kitty/fonts/current.conf` | `include fonts/current.conf` |
| Windows Terminal, on WSL | its `settings.json`, after copying it to `settings.json.backup` | nothing |
| Waybar, on Arch | `~/.config/waybar/fonts/current.css` | `@import "fonts/current.css";` in `style.css` |
| Hyprlock, on Arch | `~/.config/hypr/fonts/current.conf` | `source = ~/.config/hypr/fonts/current.conf`, then `font_family = $font` |
| dunst, on Arch | `~/.config/dunst/dunstrc.d/99-font.conf` | nothing, since it is a drop-in |

The Ghostty and Kitty files are written whether or not either terminal is installed. The Arch apps
are written only when their config directory exists. An include file keeps a config you track in
version control clean: font rewrites its own file whole and edits nothing around it. Windows
Terminal is the exception, and its `settings.json` is edited in place with a backup beside it.

Every action appends one record to the history, carrying the context it happened in:

```json
{"terminal":"ghostty","in_tmux":false,"cols":212,"rows":58,"resolution":"3440x1440","font_size":17,"machine":"laptop","platform":"macos","ts":"2026-01-04T17:24:03Z","font":"Fira Code Nerd Font","action":"apply","trigger":"manual"}
```

An apply's `trigger` says who made it: `manual` for one you typed, `schedule` for one the timer
made. A row with no `trigger` predates the field and was applied by hand. A scheduled apply runs
with no terminal, so its row carries the machine, platform, time, font and trigger and nothing else.

`random` draws from the curated families, minus the rejected ones and the font already on screen.
A font's weight grows with the days since it was last applied, up to a cap, and a font never applied
starts at the cap. Apply count is the wrong axis. Counts bunch together and separate nothing, and a
font added at zero applies would be the only thing a count-based draw returned until it caught up.

`last` toggles between the two fonts most recently applied on this machine.

## `like`, `dislike`, `note`, `reject` — opinions about the font on screen, in the same log

```bash
font like "great ligatures"      # the reason is optional
font dislike "too wide"
font note "good for prose"       # a note needs its message
font reject "zero has no slash"  # out of random and the rankings; the reason is required
font unreject                    # pick a rejected font in fzf, its history beside it
font list --status rejected      # the rejected families; active and all are the other two states
```

These act on the font of the terminal you type them in, read from that terminal's own file. font
knows Ghostty, Kitty and Windows Terminal by their environment variables. In any other terminal
there is no current font, and these four refuse.

Rejection is a logged action, not a separate list. A font is rejected when `reject` is the later of
its `reject` and `unreject` records, so there is no second file to keep in step. A rejected font
leaves `font random` and both rankings. It stays in `font list`, `change`, `info` and `font apply`,
so it is never unreachable.

`font list --status` takes `active`, `rejected` or `all`, and defaults to `all`. The curated set is
small enough that both halves stay worth seeing. `font apply` accepts every name in it, so a
narrower default would hide a name the tool still takes. Why a font sits where it does reads per
font: `font current` and `font info` render its history, rejection reason included.

## `rank`, `stats`, `current`, `info`, `log` — what you said and what you used, kept apart

```bash
font current   # this terminal's font: description, history, stats and a 12-month usage sparkline
font info      # the same page for any curated font, chosen in fzf
font rank      # one ranking by likes and one by hours used, then each font's scheduled turns
font stats     # where the two signals disagree, how fast you try fonts, each machine's favorite
font log       # every record, with the machine and terminal it came from
```

font keeps two signals and never blends them:

- **Stated preference** is likes minus dislikes.
- **Revealed preference** is how long each font was active. It is reconstructed from the gap
  between consecutive `apply` records on the same machine, and the font on screen counts up to
  now. Another machine's apply says nothing about this screen, so it ends nothing here. Another
  machine's latest apply counts for nothing until that machine applies again, since nothing here
  knows when it ended.

`font rank` shows the two as separate lists, because a font you keep reaching for is a different
signal from one you liked once. Both lists rank only curated fonts that are not rejected. Under
them, the fonts the schedule has applied show how often each kept the screen until the next
scheduled change.
`font stats` reads the whole history: fonts used more than average but never rated, fonts liked
but used less than average, how many fonts you first tried each month, and the most-used font on
each machine.

## `sync` — one history across machines, each machine writing only its own file

```bash
font sync init     # find the gist by its description, or create a secret one; run once per machine
font sync status   # whether sync is on, the gist id, the last sync, whether gh is signed in
font sync pull     # merge every other machine's rows in now
font sync push     # pull, then upload this machine's rows now
font sync off      # stop syncing; sync on resumes it and syncs at once
```

Sync runs by itself once initialized. Every logged action pushes in the background, and `change`
and `info` pull before they open. `init` looks for a gist described as `font-preferences`, so a
second machine joins the first one's history rather than starting its own. The gist it creates is
secret: unlisted, but readable by anyone holding its URL. Each record carries a hostname, a terminal
and a screen resolution.

The gist holds one file per machine, `history-<host>.jsonl`, named for the lowercased short
hostname. Each machine writes only its own file. A pull takes every other machine's file as it
stands, and takes this machine's rows from the local history. A union of every machine's rows
cannot express a deletion: a row removed on one machine comes back from the next one still holding
it. With one writer per file, deleting a row you wrote is an ordinary edit to the local history,
and no other machine can put it back. Merged rows are deduplicated on timestamp, machine, font and
action, then sorted by time.

## `schedule` — a timer changes the font while you are at the machine

```bash
font schedule on       # install the timer: a systemd user timer on Linux, a launchd agent on macOS
font schedule status   # whether it is on, the font on screen, when the next change is due, the last check
font schedule off      # remove the timer
font schedule run      # one check, which is what the timer runs
```

The timer checks every five minutes. A font the schedule applied keeps the screen for six hours, and
one you applied by hand keeps it for twelve. A due change waits until you are at the machine, so it
lands while you are using it. On macOS that means input within the last ten minutes. On Linux it
means logind marks your display session neither idle nor locked. The draw is `font random`'s.

Every scheduled apply is logged with `"trigger":"schedule"`. So the history shows which fonts you
switched away from and which stayed on until the timer replaced them. `font rank` counts both for
each font under `SCHEDULED TURNS`:

```text
SCHEDULED TURNS
 1. Hack Nerd Font                   1/1 kept   0 switched
 2. Iosevka Term Slab Nerd Font      1/2 kept   1 switched after 1h 30m
 3. JetBrains Mono Nerd Font         0/1 kept   1 switched after 20m
```

A turn starts at a scheduled apply and ends at the next apply of another font on the same machine.
It was kept when the schedule made that apply, and switched when you did. Re-applying the same font
ends nothing, and a turn still running is not counted.

hypridle does not set logind's idle hint by itself. This listener in `hypridle.conf` does:

```text
listener {
    timeout = 600
    on-timeout = busctl call org.freedesktop.login1 /org/freedesktop/login1/session/auto org.freedesktop.login1.Session SetIdleHint b true
    on-resume = busctl call org.freedesktop.login1 /org/freedesktop/login1/session/auto org.freedesktop.login1.Session SetIdleHint b false
}
```

On Linux the timer runs in the systemd user manager, which carries only the environment your session
gave it. A change needs `WAYLAND_DISPLAY` or `DISPLAY`, and under Hyprland its
`HYPRLAND_INSTANCE_SIGNATURE`. Without them a check is recorded as blocked and changes nothing. A
session that does not export them runs this at login:

```bash
systemctl --user import-environment WAYLAND_DISPLAY DISPLAY HYPRLAND_INSTANCE_SIGNATURE
```

`on` writes `~/.config/systemd/user/font-schedule.service` and `.timer`, or
`~/Library/LaunchAgents/com.datapointchris.font-schedule.plist`. Each check records its outcome in
`schedule.json`: waiting, away, blocked, applied or failed. A check counts as applied only when the
history holds the row the apply wrote, whatever the apply's exit status. `status` warns when no
check has run for fifteen minutes.

A scheduled change redraws open Kitty windows, and open Ghostty windows on Linux. On macOS Ghostty
shows it after a config reload or in a new window, the same as a font applied by hand. WSL has no
display session to read, so the schedule does not run there.

## Where it writes — one history file, merged from every machine

```text
~/.local/state/font/
├── history.jsonl      # the action log, one JSON record per line, merged from every machine
├── sync-state.json    # gist id, last sync time, whether sync is on
└── schedule.json      # the outcome of the last scheduled check
```

A deleted history file is recreated empty by the next command. A font name recorded under an older
spelling is read under the name the registry uses.

The curated families and their metadata live in the checkout at `data/font-registry.json`: a
description, creator, year, license and URL for each. Only families marked `managed` appear in
`font list`, the pickers, the rankings and `font install --check`. `font list` prints them.

`FONT_ENV=development` moves all of the state above into a gitignored `.dev-data/` inside the
checkout and turns sync off, so working on font never touches real history. The repository's
`.envrc` sets it through direnv. `scripts/seed-dev-data.sh` fills `.dev-data/` with a realistic
fixture. `bats tests/` runs the suite, and every test points `HOME` at a temporary directory.
