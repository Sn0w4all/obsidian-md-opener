# Shared helpers for install.sh and uninstall.sh. Sourced, not executed.

OBSIDIAN_CFG="$HOME/Library/Application Support/obsidian/obsidian.json"
MD_UTI="net.daringfireball.markdown"
BUNDLE_ID="local.obsidian-md-opener"
APP_NAME="Obsidian MD Opener"
STATE_DIR="$HOME/Library/Application Support/ObsidianMDOpener"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
OBSIDIAN_WAS_RUNNING=0

info() { echo "==> $*"; }
warn() { echo "warning: $*" >&2; }
die()  { echo "error: $*" >&2; exit 1; }

obsidian_running() { pgrep -f "Obsidian.app/Contents/MacOS/Obsidian" >/dev/null; }

# Obsidian rewrites obsidian.json on exit, so it must be closed before we edit it.
quit_obsidian() {
    obsidian_running || return 0
    if [ "${ASSUME_YES:-0}" != 1 ]; then
        read -r -p "Obsidian must be closed to edit its vault list. Quit it now? [y/N] " answer
        [[ "$answer" =~ ^[Yy]$ ]] || die "aborted: close Obsidian and run again"
    fi
    osascript -e 'tell application "Obsidian" to quit'
    for _ in $(seq 1 30); do
        if ! obsidian_running; then OBSIDIAN_WAS_RUNNING=1; return 0; fi
        sleep 1
    done
    die "Obsidian did not quit"
}

# vault_cfg check|add|remove <config> <vault-path> [<new-id>]
# Edits obsidian.json with JXA (always available on macOS, no extra dependencies).
vault_cfg() {
    osascript -l JavaScript -e '
ObjC.import("Foundation");
function run(a) {
    var mode = a[0], cfg = a[1], vault = a[2], id = a[3];
    var s = $.NSString.stringWithContentsOfFileEncodingError($(cfg), $.NSUTF8StringEncoding, null);
    var data = JSON.parse(ObjC.unwrap(s));
    data.vaults = data.vaults || {};
    var found = Object.keys(data.vaults).filter(function (k) { return data.vaults[k].path === vault; });
    if (mode === "check") return found.length ? "yes" : "no";
    if (mode === "add" && !found.length) data.vaults[id] = { path: vault, ts: Date.now() };
    if (mode === "remove") found.forEach(function (k) { delete data.vaults[k]; });
    $(JSON.stringify(data)).writeToFileAtomicallyEncodingError($(cfg), true, $.NSUTF8StringEncoding, null);
    return "ok";
}' -- "$@"
}

current_handler() {
    osascript -l JavaScript -e "ObjC.import('CoreServices');
var r = \$.LSCopyDefaultRoleHandlerForContentType(\$('$MD_UTI'), \$.kLSRolesAll);
r ? ObjC.unwrap(ObjC.castRefToObject(r)) : ''" 2>/dev/null || true
}

set_handler() {
    osascript -l JavaScript -e "ObjC.import('CoreServices');
\$.LSSetDefaultRoleHandlerForContentType(\$('$MD_UTI'), \$.kLSRolesAll, \$('$1'))" >/dev/null
}
