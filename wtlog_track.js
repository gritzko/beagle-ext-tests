//  DIS-078: shared/wtlog.js track()/base() — the TWO worktree fundamentals as
//  ONE routine each.  Builds a fixture wtlog per leg (ulog.append synthetic
//  rows, the test/ulog.js idiom) and drains it through wtlog.open, pinning:
//    track() — the recentmost `get` ref-row as a full fact (row/authority
//              exposed) with the attachedBranch attach/detach verdict;
//    base()  — the recentmost get/post sha-row (curTip's fact, row included).
//  Legs: plain get, get+post, detached `#sha`, remote-authority `//peer`,
//  legacy `?branch&sha` &-chain, and a pins-nothing store anchor.  Also asserts
//  attachedBranch() is now a THIN DECODE over track() (its output unchanged).
"use strict";

const { eq, ok } = require("./lib/assert.js");
//  DIS-054/JS-048: an isolated ticket clone owns a code-less `.be` shard, so a
//  be-relative require may miss — derive the be/ code dir from this script path.
const wtlog = _req("shared/wtlog.js");
const ulog = _req("shared/ulog.js");
function _req(mod) {
  const self = (typeof process !== "undefined" && process.argv && process.argv[1]) || "";
  if (self) {
    const d = self.slice(0, self.lastIndexOf("/test/"));
    if (d && d !== self) { try { return require(d + "/" + mod); } catch (e) {} }
  }
  return require(mod);
}

const SHA = (c) => c.repeat(40);
const A = SHA("a"), B = SHA("b"), C = SHA("c"), D = SHA("d"), E = SHA("e");

const TMP = io.getenv("TMP") || "/tmp";
const base = TMP + "/dis078-wtlog-" + Date.now() + "-" + (Math.random() * 1e9 | 0);
io.mkdir(base);
let seq = 0;
//  A fresh fixture wtlog carrying `rows`, opened as a reader (project "p").
function fixture(rows) {
  const p = base + "/wtlog-" + (seq++);
  ulog.append(p, rows);
  return wtlog.open({ bePath: p, project: "p" });
}

//  --- leg A: a plain attached `get ?main#<sha>` --------------------------
(function () {
  const r = fixture([{ verb: "get", uri: "?main#" + A }]);
  const t = r.track(), b = r.base();
  eq(t.branch, "main", "A track: branch");
  eq(t.sha, A, "A track: sha");
  eq(t.detached, false, "A track: attached");
  eq(t.uriTrack, false, "A track: query-shaped (not uriTrack)");
  ok(t.row && t.row.verb === "get", "A track: row is the get");
  eq(b.sha, A, "A base: sha");
  ok(b.row && b.row.verb === "get", "A base: row is the get");
  const ab = r.attachedBranch();
  eq(ab.branch, "main", "A att: branch");
  eq(ab.track, "?main", "A att: track ref");
  eq(ab.base, A, "A att: base fragment");
})();

//  --- leg B: get then post — TRACK is the get, BASE is the post ----------
(function () {
  const r = fixture([{ verb: "get", uri: "?main#" + A },
                     { verb: "post", uri: "?main#" + B }]);
  const t = r.track(), b = r.base();
  eq(t.sha, A, "B track: the recentmost GET sha (not the post)");
  ok(t.row && t.row.verb === "get", "B track: row is the get");
  eq(b.sha, B, "B base: the recentmost get/post sha (the post)");
  ok(b.row && b.row.verb === "post", "B base: row is the post");
  eq(r.attachedBranch().base, B, "B att: base advances to the post fragment");
})();

//  --- leg C: a bare-hash detach `get #<sha>` (DIS-075) -------------------
(function () {
  const r = fixture([{ verb: "get", uri: "#" + C }]);
  const t = r.track();
  eq(t.detached, true, "C track: DETACHED");
  eq(t.branch, "", "C track: no branch");
  eq(t.sha, C, "C track: sha");
  eq(r.attachedBranch().track, "", "C att: a detached wt tracks nothing");
})();

//  --- leg D: a remote-authority `get //peer#<sha>` (a uriTrack) ----------
(function () {
  const r = fixture([{ verb: "get", uri: "//peer#" + D }]);
  const t = r.track();
  eq(t.uriTrack, true, "D track: URI-shaped track");
  eq(t.detached, false, "D track: a uriTrack is NOT detached");
  ok(t.authority && t.authority.indexOf("peer") >= 0, "D track: authority exposed");
  eq(t.sha, D, "D track: sha");
  const ab = r.attachedBranch();
  ok(ab.track.indexOf("peer") >= 0, "D att: track keeps the authority");
})();

//  --- leg E: a legacy `?main&<sha>` &-chain row -------------------------
//  refOf reads the sha out of the QUERY &-chain (no fragment); base()/curTip
//  see it, but attachedBranch.base (fragment-only baseSha, STATUS-009) does NOT
//  — a genuine distinction the pair PRESERVES.
(function () {
  const r = fixture([{ verb: "get", uri: "?main&" + E }]);
  const t = r.track(), b = r.base();
  eq(t.branch, "main", "E track: branch from the &-chain");
  eq(t.sha, E, "E track: sha from the &-chain");
  eq(b.sha, E, "E base: base() reads the &-chain sha");
  eq(r.attachedBranch().base, "", "E att: fragment-only base is empty for legacy");
})();

//  --- leg F: a pins-nothing store anchor — the empty fact ---------------
(function () {
  const r = fixture([{ verb: "get", uri: "file:" + base + "/.be/?/p" }]);
  const t = r.track(), b = r.base();
  eq(t.row, undefined, "F track: no ref row → empty fact");
  eq(t.branch, "", "F track: empty branch");
  eq(t.detached, false, "F track: empty fact is not detached");
  eq(b.sha, "", "F base: no sha");
})();

//  cleanup
for (const f of io.readdir(base)) { try { io.unlink(base + "/" + f); } catch (e) {} }

io.log("wtlog_track.js OK\n");
