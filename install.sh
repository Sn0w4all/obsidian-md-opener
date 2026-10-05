#!/usr/bin/env bash
# Obsidian MD Opener installer.
#
# Usage: ./install.sh [--yes]
#   --yes            do not ask before quitting Obsidian (needed once to register the vault)
# Environment:
#   EXTERNAL_VAULT   vault that holds the symlinks   (default: ~/Documents/External)
#   FALLBACK_APP     editor used if anything fails   (default: Visual Studio Code)
#   APP_DIR          where the app is installed      (default: ~/Applications)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$ROOT/scripts/lib.sh"

[ "${1:-}" = "--yes" ] && ASSUME_YES=1
EXTERNAL_VAULT="${EXTERNAL_VAULT:-$HOME/Documents/External}"
FALLBACK_APP="${FALLBACK_APP:-Visual Studio Code}"
APP_DIR="${APP_DIR:-$HOME/Applications}"
APP="$APP_DIR/$APP_NAME.app"

# --- checks ---------------------------------------------------------------
[ "$(uname)" = "Darwin" ] || die "macOS only"
command -v osacompile >/dev/null || die "osacompile not found"
open -Ra Obsidian 2>/dev/null || die "Obsidian.app not found"
[ -f "$OBSIDIAN_CFG" ] || die "Obsidian config not found: open Obsidian once, then run again"
case "$EXTERNAL_VAULT" in /*) ;; *) die "EXTERNAL_VAULT must be an absolute path" ;; esac
case "$EXTERNAL_VAULT$FALLBACK_APP" in
    *\'*|*\\*|*\|*|*\&*) die "EXTERNAL_VAULT and FALLBACK_APP must not contain ' \\ | &" ;;
esac
open -Ra "$FALLBACK_APP" 2>/dev/null || warn "fallback app '$FALLBACK_APP' not found; files will open in the default text editor on failure"

# --- External vault ---------------------------------------------------------
info "Creating vault: $EXTERNAL_VAULT"
mkdir -p "$EXTERNAL_VAULT/.obsidian" "$EXTERNAL_VAULT/_links"
[ -f "$EXTERNAL_VAULT/.obsidian/app.json" ] || cat > "$EXTERNAL_VAULT/.obsidian/app.json" <<'EOF'
{
  "alwaysUpdateLinks": false,
  "promptDelete": false
}
EOF
[ -f "$EXTERNAL_VAULT/README.md" ] || cat > "$EXTERNAL_VAULT/README.md" <<'EOF'
# External

Helper vault managed by Obsidian MD Opener. `_links/` holds symlinks to Markdown
files from all over your Mac; edits go to the original files. Do not keep real notes here.
EOF

if [ "$(vault_cfg check "$OBSIDIAN_CFG" "$EXTERNAL_VAULT")" = "no" ]; then
    info "Registering vault in Obsidian"
    quit_obsidian
    cp "$OBSIDIAN_CFG" "$OBSIDIAN_CFG.bak-$(date +%Y%m%d%H%M%S)"
    vault_cfg add "$OBSIDIAN_CFG" "$EXTERNAL_VAULT" "$(openssl rand -hex 8)" >/dev/null
fi

# --- build the app ----------------------------------------------------------
info "Building $APP"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP:?}"' EXIT
sed -e "s|@EXTERNAL_VAULT@|$EXTERNAL_VAULT|" -e "s|@FALLBACK_APP@|$FALLBACK_APP|" \
    "$ROOT/src/opener.js" > "$TMP/opener.js"

mkdir -p "$APP_DIR"
osacompile -l JavaScript -o "$APP" "$TMP/opener.js"
PLIST="$APP/Contents/Info.plist"
plutil -replace CFBundleDocumentTypes -json '[{"CFBundleTypeName":"Markdown","CFBundleTypeRole":"Editor","LSHandlerRank":"Owner","LSItemContentTypes":["net.daringfireball.markdown"],"CFBundleTypeExtensions":["md","markdown","mdown"]}]' "$PLIST"
plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$PLIST"
plutil -replace LSUIElement -bool true "$PLIST"
plutil -replace OSAAppletStayOpen -bool true "$PLIST"
codesign --force --deep -s - "$APP" 2>/dev/null
"$LSREGISTER" -f "$APP"

# --- make it the default for .md --------------------------------------------
previous="$(current_handler)"
if [ -n "$previous" ] && [ "$previous" != "$BUNDLE_ID" ]; then
    mkdir -p "$STATE_DIR"
    printf '%s' "$previous" > "$STATE_DIR/previous-handler"
fi
set_handler "$BUNDLE_ID"
for _ in 1 2 3 4 5 6 7 8 9 10; do   # LaunchServices applies the change asynchronously
    [ "$(current_handler)" = "$BUNDLE_ID" ] && break
    sleep 1
done
[ "$(current_handler)" = "$BUNDLE_ID" ] || warn "default handler not applied; set it in Finder > Get Info > Open with > Change All"

[ "$OBSIDIAN_WAS_RUNNING" = 1 ] && open -a Obsidian

info "Done. Double-click any .md file to try it."
echo "    Log: ~/Library/Logs/ObsidianMDOpener.log"
echo "    If double-clicking a file in Finder does nothing, relaunch Finder: killall Finder"
