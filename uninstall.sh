#!/usr/bin/env bash
# Obsidian MD Opener uninstaller.
#
# Usage: ./uninstall.sh [--purge-vault] [--yes]
#   --purge-vault    also delete the External vault and unregister it from Obsidian
#   --yes            do not ask before quitting Obsidian
# Environment: EXTERNAL_VAULT, APP_DIR (same defaults as install.sh)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$ROOT/scripts/lib.sh"

PURGE=0
for arg in "$@"; do
    case "$arg" in
        --purge-vault) PURGE=1 ;;
        --yes) ASSUME_YES=1 ;;
        *) die "unknown option: $arg" ;;
    esac
done
EXTERNAL_VAULT="${EXTERNAL_VAULT:-$HOME/Documents/External}"
APP_DIR="${APP_DIR:-$HOME/Applications}"
APP="$APP_DIR/$APP_NAME.app"

# restore the previous default handler for .md (saved by install.sh)
if [ "$(current_handler)" = "$BUNDLE_ID" ]; then
    restore="$(cat "$STATE_DIR/previous-handler" 2>/dev/null || true)"
    restore="${restore:-${RESTORE_BUNDLE_ID:-com.microsoft.VSCode}}"
    info "Restoring default .md handler: $restore"
    set_handler "$restore" || warn "could not restore the handler; set it in Finder > Get Info"
fi

if [ -d "$APP" ]; then
    info "Removing $APP"
    "$LSREGISTER" -u "$APP" || true
    rm -rf "${APP:?}"
fi

if [ "$PURGE" = 1 ]; then
    case "$EXTERNAL_VAULT" in ""|"/"|"$HOME") die "refusing to delete $EXTERNAL_VAULT" ;; esac
    [ -d "$EXTERNAL_VAULT/_links" ] || die "$EXTERNAL_VAULT does not look like the External vault"
    info "Removing vault $EXTERNAL_VAULT"
    quit_obsidian
    if [ "$(vault_cfg check "$OBSIDIAN_CFG" "$EXTERNAL_VAULT")" = "yes" ]; then
        cp "$OBSIDIAN_CFG" "$OBSIDIAN_CFG.bak-$(date +%Y%m%d%H%M%S)"
        vault_cfg remove "$OBSIDIAN_CFG" "$EXTERNAL_VAULT" >/dev/null
    fi
    rm -rf "${EXTERNAL_VAULT:?}"
    [ "$OBSIDIAN_WAS_RUNNING" = 1 ] && open -a Obsidian
fi

rm -rf "${STATE_DIR:?}"
rm -f "$HOME/Library/Logs/ObsidianMDOpener.log"
info "Uninstalled."
