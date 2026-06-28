//  mtimeinv.js — assert the `be put` restamp invariant for a worktree: each
//  `put` row's staged file carries an mtime EQUAL to that row's ts (so a
//  later put / POST fast-paths it via the stamp-set).  For a move row
//  (`<old>#<new>`) the DEST (`<new>`) is the stamped file.  Args: <wt-dir>.
//  Exits non-zero (throws) on any mismatch.  Used by test/js/put/putcase.sh.
"use strict";
//  DIS-054: an ISOLATED ticket clone gives the test tree its OWN `.be` shard,
//  so a be-relative require here resolves against that code-less shard.  Derive
//  the be/ code dir from THIS script's own path; fall back to $BEDIR, then
//  be-relative.
const ulog = _loadUlog();
function _loadUlog() {
  const self = (typeof process !== "undefined" && process.argv && process.argv[1]) || "";
  const cands = [];
  if (self) { const d = self.slice(0, self.lastIndexOf("/test/")); if (d && d !== self) cands.push(d); }
  const env = (typeof io !== "undefined" && io.getenv) ? io.getenv("BEDIR") : "";
  if (env) cands.push(env);
  for (const d of cands) for (const p of ["/shared/ulog.js", "/lib/ulog.js"]) {
    try { return require(d + p); } catch (e) {}
  }
  return require("shared/ulog.js");              // be-relative: the be/ shard's ulog
}
const wt = process.argv[2];
let bad = 0;
//  Only the put rows AFTER the last get/post are in the current staging
//  scope; an earlier baseline-staging `put` row's file was re-stamped by the
//  post that consumed it, so its mtime legitimately no longer matches.
let floor = 0n;
ulog.each(wt + "/.be/wtlog", function (log) {
  if (log.verb === "get" || log.verb === "post") floor = log.time;
});
ulog.each(wt + "/.be/wtlog", function (log) {
  if (log.verb !== "put") return;
  if (log.time <= floor) return;
  const u = new URI(log.uri);
  //  Skip ref-form put rows (`?br#sha`) — they are REFS ops, not files.
  if (!u.path) return;
  const rel = u.fragment ? u.fragment : u.path;     // move dest, else file
  //  A sha fragment is a sub-bump, not a path — skip (no such file here).
  if (u.fragment && /^[0-9a-f]{40}$/.test(u.fragment)) return;
  let m;
  try { m = io.lstat(wt + "/" + rel).mtime; }
  catch (e) { io.log("NOFILE " + rel + "\n"); bad++; return; }
  if (ron.encode(m) !== ron.encode(log.time)) {
    io.log("MISMATCH " + rel + " mtime=" + ron.encode(m) +
           " rowts=" + ron.encode(log.time) + "\n");
    bad++;
  }
});
if (bad) throw "mtimeinv: " + bad + " mismatch(es)";
