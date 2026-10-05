# Obsidian MD Opener

Make **Obsidian the default app for `.md` files on macOS**, for files anywhere on your Mac, not only inside a vault.

## Why

Obsidian works on vaults, not on single files, and it does not register as a Markdown handler:
it is greyed out in Finder's *Open With* list, and if you force it, it opens but ignores the file.

This project installs a tiny macOS app that becomes the default `.md` handler and routes every file to Obsidian.

## How it works

```
double-click note.md
        │
        ▼
 Obsidian MD Opener.app
        │
        ├── file is inside a vault ──────────▶ obsidian://open?path=<file>
        │
        ├── file is anywhere else ──▶ symlink in the "External" vault ──▶ obsidian://open?path=<symlink>
        │
        └── anything goes wrong ─────────────▶ fallback editor (VS Code by default)
```

- Symlinks live in a dedicated helper vault, `~/Documents/External/_links/`. Edits go **straight to the original file**: no copies, no duplicates.
- Vaults are read from Obsidian's own config, so every vault you have is recognised automatically.
- A built-in **cleaner** removes stale symlinks (details below).

## Install

Requires macOS (tested on macOS 26) and Obsidian, launched at least once.

```bash
git clone https://github.com/Sn0w4all/obsidian-md-opener.git
cd obsidian-md-opener
./install.sh
```

The installer:

1. creates the `External` vault and registers it in Obsidian (Obsidian is quit once for this; `--yes` skips the prompt and it is reopened afterwards),
2. builds `~/Applications/Obsidian MD Opener.app`,
3. sets it as the default app for `.md` files and remembers the previous default.

Options (environment variables):

| Variable | Default | Meaning |
|---|---|---|
| `EXTERNAL_VAULT` | `~/Documents/External` | helper vault that holds the symlinks (keep it outside iCloud-synced folders) |
| `FALLBACK_APP` | `Visual Studio Code` | editor used when Obsidian cannot be used |
| `APP_DIR` | `~/Applications` | where the app is installed |

## Usage

Just double-click any `.md` file. Double-clicking the app itself runs the cleaner and opens Obsidian.

## Cleaner

Runs on file open (at most once an hour) and on a manual launch. It removes only symlinks inside `External/_links/<hash>/`:

- not opened for **14 days**, or
- whose target is gone and that are older than a day.

It never removes symlinks of files that are open in a tab, links to files on a currently unmounted volume (until they are 14 days old), regular files, or anything outside `_links/`. A removed link is recreated the next time you open the file.

## Uninstall

```bash
./uninstall.sh                 # remove the app, restore the previous .md handler
./uninstall.sh --purge-vault   # also delete the External vault and unregister it from Obsidian
```

## Notes

- Log: `~/Library/Logs/ObsidianMDOpener.log`.
- Opening a new file reuses the active tab of the `External` window (standard Obsidian behaviour).
- If a file lives in a protected folder (Desktop, Documents, Downloads, external disks), Obsidian may ask for access once.
- If you move or delete an original file, its symlink breaks and is cleaned up after a day.
- Only `.md`, `.markdown` and `.mdown` files are handled.
- **Double-click in Finder does nothing?** A long-running Finder can get stuck and stop opening *any* file (check: does a plain `.txt` open in TextEdit?). Relaunch it: hold Option, right-click the Finder icon in the Dock, choose *Relaunch*, or run `killall Finder`. If `open note.md` works in Terminal, the app is fine.
- Related: [ObsidianOpener](https://github.com/Fletcher-Alderton/ObsidianOpener) solves the same problem by *copying* outside files into a vault; this project symlinks them so the original is edited.

## Layout

```
├── install.sh          # create vault, register it, build app, set default handler
├── uninstall.sh        # remove app, restore previous handler, optionally purge the vault
├── scripts/lib.sh      # helpers shared by the two scripts
└── src/opener.js       # the app logic (JavaScript for Automation, compiled by osacompile)
```

## License

[MIT](LICENSE)
