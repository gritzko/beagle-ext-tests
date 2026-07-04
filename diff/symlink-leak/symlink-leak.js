//  test/diff/symlink-leak/symlink-leak.js — JS-069 repro: `be diff`'s wt-vs-base
//  path must NOT dereference a tracked symlink.  A tracked `link -> /etc/passwd`
//  (or here: an OUTSIDE file holding a secret marker) must diff as its stored
//  link-target STRING, never the target file's bytes.  Two leak sites in
//  views/diff/diff.js: treeMap routed a symlink leaf (kind "l") into `files`
//  (→ blob-diffed and mmap'd), and readWtFile io.mmap'd the wt path (FOLLOWS
//  the link).  In-process unit over the worktree's views/diff/diff.js (jab's
//  be-scan resolves the be-relative require), mirroring test/diff/links/links.js
//  — the `diff:` handler's own reachability is tracked by JS-071 (see report).
//
//    RED  (pre-fix): treeMap has no `links` map (symlink leaf lands in `files`);
//                    readWtLink is not exported; the mmap path leaks the SECRET.
//    GREEN (post-fix): treeMap routes kind "l" to `links`; readWtLink reads the
//                      link TARGET STRING via lstat/readlink — the secret bytes
//                      NEVER appear in the wt-side blob.

"use strict";

const { eq, ok } = require("../../lib/assert.js");
const diff = require("views/diff/diff.js");

const SECRET = "SECRET_MARKER_DO_NOT_LEAK\n";

//  --- an OUTSIDE target file + a real on-disk symlink pointing at it ----------
const TMP = io.getenv("TMP") || "/tmp";
const DIR = TMP + "/js069-symlink-leak." + io.getpid();
try { io.mkdir(TMP); } catch (e) {}
try { io.mkdir(DIR); } catch (e) {}
const SECRET_PATH = DIR + "/secret.txt";
const LINK_PATH   = DIR + "/link";
try { io.unlink(SECRET_PATH); } catch (e) {}
try { io.unlink(LINK_PATH); } catch (e) {}
(function writeSecret() {
  const fd = io.open(SECRET_PATH, "c");
  try { const b = io.buf(SECRET.length + 8); b.feed(utf8.Encode(SECRET)); io.writeAll(fd, b); }
  finally { io.close(fd); }
})();
io.symlink(SECRET_PATH, LINK_PATH);          // tracked symlink -> outside secret

//  Sanity: the link resolves to the secret on disk (so a naive read WOULD leak).
eq(io.lstat(LINK_PATH).kind, "lnk", "fixture: link is a symlink on disk");

//  --- LEAK SITE 2: the wt-side read must NOT follow the link -----------------
//  readWtFile (io.mmap) FOLLOWS the link → the secret bytes (the historical
//  leak).  This is exactly why symlinks must never reach readWtFile:
const leaked = diff.readWtFile(LINK_PATH);
ok(leaked !== undefined, "fixture: mmap read of the link succeeded");
eq(utf8.Decode(leaked), SECRET,
   "fixture: io.mmap FOLLOWS the link and yields the secret (the leak we prevent)");

//  THE FIX: readWtLink reads the link TARGET STRING (lstat/readlink), no follow.
ok(typeof diff.readWtLink === "function",
   "JS-069: diff.js exports readWtLink (no-follow wt symlink read)");
const wt = diff.readWtLink(LINK_PATH);
ok(wt !== undefined, "JS-069: readWtLink read the symlink");
const wtStr = utf8.Decode(wt);
eq(wtStr, SECRET_PATH,
   "JS-069: wt-side blob is the LINK TARGET STRING (" + SECRET_PATH + ")");
ok(wtStr.indexOf("SECRET_MARKER_DO_NOT_LEAK") < 0,
   "JS-069: wt-side blob NEVER contains the secret marker bytes");

//  --- LEAK SITE 1: treeMap must route a symlink leaf to `links`, not `files` --
//  A stub reader replaying one symlink leaf (kind "l") + one regular leaf.
const LINK_SHA = "1111111111111111111111111111111111111111";
const FILE_SHA = "2222222222222222222222222222222222222222";
const k = {
  readTreeRecursive: function (treeSha, cb) {
    cb({ path: "link", mode: 0o120000, sha: LINK_SHA, kind: "l" });
    cb({ path: "reg.c", mode: 0o100644, sha: FILE_SHA, kind: "f" });
  },
};
const tm = diff.treeMap(k, "deadbeef");
ok(tm.links, "JS-069: treeMap returns a `links` map");
eq(tm.links["link"], LINK_SHA, "JS-069: the symlink leaf routes into `links`");
eq(tm.files["link"], undefined,
   "JS-069: the symlink leaf does NOT land in `files` (would be mmap-diffed)");
eq(tm.files["reg.c"], FILE_SHA, "JS-069: a regular leaf still routes into `files`");

//  --- cleanup ----------------------------------------------------------------
try { io.unlink(LINK_PATH); } catch (e) {}
try { io.unlink(SECRET_PATH); } catch (e) {}
try { io.rmdir(DIR); } catch (e) {}

io.log("diff/symlink-leak/symlink-leak.js OK\n");
