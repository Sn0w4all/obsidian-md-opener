// Obsidian MD Opener: macOS handler for .md files.
//
//   file inside any Obsidian vault -> obsidian://open?path=...
//   file anywhere else             -> symlink in the "External" vault -> obsidian://open
//   any failure                    -> fallback editor (nothing is ever lost)
//
// The cleaner only ever deletes symlinks in <External>/_links/<hash10>/ (see cleanLinks).
// @EXTERNAL_VAULT@ and @FALLBACK_APP@ are substituted by install.sh at build time.
ObjC.import('Foundation');
ObjC.import('stdlib');

var app = Application.currentApplication();
app.includeStandardAdditions = true;

var HOME = ObjC.unwrap($.NSHomeDirectory());
var EXT_VAULT = '@EXTERNAL_VAULT@';
var FALLBACK_APP = '@FALLBACK_APP@';
var OBSIDIAN_CFG = HOME + '/Library/Application Support/obsidian/obsidian.json';
var LINKS_DIR = EXT_VAULT + '/_links';
var STAMP = LINKS_DIR + '/.last-clean';
var LOG = HOME + '/Library/Logs/ObsidianMDOpener.log';

var STALE_DAYS = 14;         // symlink not opened for this long -> remove
var BROKEN_DAYS = 1;         // target is gone and symlink is older than this -> remove
var CLEAN_EVERY_SEC = 3600;  // throttle for the cleaner on regular opens
var NEW_LINK_DELAY_SEC = 1;  // give Obsidian's file watcher time to see a new symlink
var IDLE_QUIT_SEC = 10;      // stay alive briefly so rapid successive opens are not lost

var lastActivity = Date.now() / 1000;
var fm = $.NSFileManager.defaultManager;

function sh(cmd) { return app.doShellScript(cmd); }

function q(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }

function touchActivity() { lastActivity = Date.now() / 1000; }

function log(msg) {
    try { sh("printf '%s\\n' " + q(new Date().toISOString() + ' ' + msg) + ' >> ' + q(LOG)); } catch (e) {}
}

function std(p) { return ObjC.unwrap($(p).stringByStandardizingPath); }

function realp(p) { return ObjC.unwrap($(p).stringByResolvingSymlinksInPath); }

function under(p, dir) { return p.indexOf(dir + '/') === 0; }

function readText(p) {
    try {
        var s = $.NSString.stringWithContentsOfFileEncodingError($(p), $.NSUTF8StringEncoding, null);
        return s ? (ObjC.unwrap(s) || '') : '';
    } catch (e) { return ''; }
}

function listDir(p) {
    try { return ObjC.deepUnwrap(fm.contentsOfDirectoryAtPathError($(p), null)) || []; } catch (e) { return []; }
}

// lstat-style attributes: for a symlink they describe the link itself, not its target
function attrs(p) {
    try {
        var d = fm.attributesOfItemAtPathError($(p), null);
        return {
            type: ObjC.unwrap(d.objectForKey('NSFileType')),
            mtime: d.objectForKey('NSFileModificationDate').timeIntervalSince1970
        };
    } catch (e) { return null; }
}

function loadVaults() {
    try {
        var v = JSON.parse(readText(OBSIDIAN_CFG)).vaults || {};
        var list = Object.keys(v).map(function (k) { return std(v[k].path); });
        return list.concat(list.map(realp));
    } catch (e) {
        log('obsidian.json read failed: ' + e);
        return [];
    }
}

function inVault(p, vaults) {
    if (/\/\.(obsidian|trash)\//.test(p)) return false;
    return vaults.some(function (v) { return under(p, v); });
}

function openInObsidian(path) {
    sh('open ' + q('obsidian://open?path=' + encodeURIComponent(path)));
}

function openFallback(path) {
    try { sh('open -a ' + q(FALLBACK_APP) + ' ' + q(path)); }
    catch (e) { sh('open -t ' + q(path)); }
}

// Creates (or reuses) <External>/_links/<hash>/<name>; returns {link, status}
function ensureLink(real) {
    var hash = sh('printf %s ' + q(real) + ' | shasum -a 256 | cut -c1-10');
    var dir = LINKS_DIR + '/' + hash;
    var link = dir + '/' + real.split('/').pop();
    var cmd =
        'mkdir -p ' + q(dir) + '; ' +
        'if [ -e ' + q(link) + ' ] && [ ! -L ' + q(link) + ' ]; then echo conflict; exit 0; fi; ' +
        'cur=$(readlink ' + q(link) + ' 2>/dev/null || true); ' +
        'if [ "$cur" = ' + q(real) + ' ]; then touch -h ' + q(link) + '; echo reused; ' +
        'else ln -sfn ' + q(real) + ' ' + q(link) + ' && echo created; fi';
    return { link: link, status: sh(cmd) };
}

function openDocuments(docs) {
    touchActivity();
    var vaults = loadVaults();
    var extReady = vaults.indexOf(std(EXT_VAULT)) !== -1 &&
        fm.fileExistsAtPath($(EXT_VAULT + '/.obsidian'));
    var plan = [];
    var needDelay = false;

    docs.forEach(function (d) {
        var raw = d.toString();
        try {
            var p = std(raw);
            if (inVault(p, vaults)) { plan.push({ open: p }); return; }
            var r = realp(p);
            if (inVault(r, vaults)) { plan.push({ open: r }); return; }
            if (!extReady) {
                log('External vault not registered, fallback: ' + r);
                plan.push({ fallback: p });
                return;
            }
            var res = ensureLink(r);
            if (res.status === 'created') needDelay = true;
            if (res.status === 'created' || res.status === 'reused') {
                plan.push({ open: res.link });
                log(res.status + ' ' + res.link + ' -> ' + r);
            } else {
                log('link ' + res.status + ', fallback: ' + r);
                plan.push({ fallback: p });
            }
        } catch (e) {
            log('error for ' + raw + ': ' + e);
            plan.push({ fallback: raw });
        }
    });

    if (needDelay) sh('sleep ' + NEW_LINK_DELAY_SEC);

    plan.forEach(function (a) {
        try {
            if (a.open) openInObsidian(a.open); else openFallback(a.fallback);
        } catch (e) {
            log('open failed: ' + e);
            try { openFallback(a.open || a.fallback); } catch (e2) { log('fallback failed: ' + e2); }
        }
    });

    try { cleanLinks(false); } catch (e) { log('clean failed: ' + e); }
    touchActivity();
}

// Only symlinks of the form <External>/_links/<10 hex>/<name> may ever be removed.
function isManagedLinkPath(p) {
    if (p.indexOf(LINKS_DIR + '/') !== 0) return false;
    var parts = p.substring(LINKS_DIR.length + 1).split('/');
    return parts.length === 2 && /^[0-9a-f]{10}$/.test(parts[0]) && parts[1].length > 0;
}

function volumeMissing(target) {
    var m = /^\/Volumes\/[^\/]+/.exec(target);
    return !!m && !fm.fileExistsAtPath($(m[0]));
}

// Set of 'hash/name' for files currently open in tabs (from the vault's workspace.json)
function openTabFiles() {
    var set = { items: {}, has: function (k) { return Object.prototype.hasOwnProperty.call(this.items, k); } };
    var raw = readText(EXT_VAULT + '/.obsidian/workspace.json');
    if (!raw) return set;
    try {
        (function walk(o) {
            if (!o || typeof o !== 'object') return;
            if (o.state && typeof o.state.file === 'string') {
                var m = /^_links\/([0-9a-f]{10}\/.+)$/.exec(o.state.file);
                if (m) set.items[m[1]] = true;
            }
            Object.keys(o).forEach(function (k) { if (k !== 'lastOpenFiles') walk(o[k]); });
        })(JSON.parse(raw));
    } catch (e) {
        // unparsable JSON: protect anything mentioned in the raw text (safer)
        set.has = function (k) { return raw.indexOf(k) !== -1; };
    }
    return set;
}

// Removes stale and broken symlinks. Regular files and foreign folders are never touched.
function cleanLinks(force) {
    var now = Date.now() / 1000;
    var st = attrs(STAMP);
    if (!force && st && now - st.mtime < CLEAN_EVERY_SEC) return 0;

    var open = openTabFiles();
    var removed = 0;

    listDir(LINKS_DIR).forEach(function (hash) {
        if (!/^[0-9a-f]{10}$/.test(hash)) return;
        var dir = LINKS_DIR + '/' + hash;
        var da = attrs(dir);
        if (!da || da.type !== 'NSFileTypeDirectory') return;

        listDir(dir).forEach(function (name) {
            var link = dir + '/' + name;
            var a = attrs(link);
            if (!a || a.type !== 'NSFileTypeSymbolicLink') return; // not a symlink: leave alone
            if (!isManagedLinkPath(link)) return;
            if (open.has(hash + '/' + name)) return;                // open in a tab

            var ageDays = (now - a.mtime) / 86400;
            var target = '';
            try { target = ObjC.unwrap(fm.destinationOfSymbolicLinkAtPathError($(link), null)) || ''; } catch (e) {}
            var broken = !fm.fileExistsAtPath($(link)); // follows the link

            var reason = null;
            if (ageDays > STALE_DAYS) reason = 'stale ' + Math.floor(ageDays) + 'd';
            else if (broken && ageDays > BROKEN_DAYS && !volumeMissing(target)) reason = 'broken target';

            if (reason && fm.removeItemAtPathError($(link), null)) {
                removed++;
                log('cleaned (' + reason + ') ' + link + ' -> ' + target);
            }
        });

        // drop the hash folder once empty (a stray .DS_Store does not count)
        var rest = listDir(dir).filter(function (n) { return n !== '.DS_Store'; });
        if (rest.length === 0) {
            try { sh('rm -f ' + q(dir + '/.DS_Store')); } catch (e) {}
            fm.removeItemAtPathError($(dir), null); // removes the folder only if empty here
        }
    });

    sh('mkdir -p ' + q(LINKS_DIR) + ' && touch ' + q(STAMP));
    return removed;
}

// Launched without files (double-click on the app): force a clean, then open Obsidian.
function run() {
    touchActivity();
    var n = 0;
    try { n = cleanLinks(true); } catch (e) { log('clean failed: ' + e); }
    log('manual run, cleaned ' + n);
    sh('open -a Obsidian');
}

// Stay-open applet: quit after IDLE_QUIT_SEC without new events.
function idle() {
    if (Date.now() / 1000 - lastActivity > IDLE_QUIT_SEC) $.exit(0);
    return 2;
}
