# Font - Claude Code Instructions

## Dev vs Prod Data (CRITICAL)

**direnv sets `FONT_ENV=development` in this repo directory.** This means any `font` command run from here (or by Claude Code whose cwd is this repo) reads/writes `.dev-data/`, NOT the real history at `~/.local/state/font/`.

- To test against **prod data**: run `FONT_ENV= font <command>` or run from outside this directory
- To test against **dev data**: just run normally from this directory
- The installed prod binary is at `~/.local/bin/font` -> `~/.local/share/font/bin/font`
- Prod uses git tag checkout (not main), so `font upgrade` only gets tagged releases

If rank/history/current looks wrong, check which data directory you're hitting first.
