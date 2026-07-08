//  BE-027: repro — the bro pager Tab-completion (`_fsCompletions`) must NOT escape
//  the worktree via an uncollapsed `../`.  The stem's dir prefix used to be RAW-
//  concatenated onto the wt root (only a leading `./` and trailing `/` stripped),
//  so `../…` fed straight into io.readdir/io.lstat and enumerated dirs ABOVE the
//  wt.  This drives `_fsCompletions` directly against a temp wt with a SIBLING dir
//  one level up; a `../` stem must yield NO completions (NAVESCAPE → []), while an
//  in-tree stem still completes.  RED before the confinement fix, GREEN after.
//  Also asserts the unified `_resolveSpell` `..` handling THROWS on a climb.
"use strict";

//  Derive the be/ code dir from THIS script's path (cf. test/uri.js _req).
function _req(mod) {
  const self = (typeof process !== "undefined" && process.argv && process.argv[1]) || "";
  const d = self.slice(0, self.lastIndexOf("/test/"));
  if (d && d !== self) { try { return require(d + "/" + mod); } catch (e) {} }
  return require(mod);
}
const pager = _req("views/bro/pager.js");

function fail(m) { io.log("FAIL " + m + "\n"); throw "FAIL " + m; }
function ok(v, m) { if (!v) fail(m); }

//  --- hermetic fixture: root/{wt, OUTSIDE} — OUTSIDE is a SIBLING above the wt --
const TMP = io.getenv("TMP") || "/tmp";
const root = TMP + "/be027-" + io.getpid() + "-" + (Math.random() * 1e9 | 0);
const wt = root + "/wt";
function touch(p) { const fd = io.open(p, "c"); io.close(fd); }
io.mkdir(root); io.mkdir(wt);
io.mkdir(root + "/OUTSIDE"); touch(root + "/OUTSIDE/secret_outside");
io.mkdir(wt + "/inside"); touch(wt + "/inside/file_inside");

function mkPager(viewPath) {
  const p = new pager.Pager(-1, { color: false, be: { wt_root: wt, cwd: wt } });
  p._verbUri = function () { return { verb: "ls", uri: viewPath }; };
  return p;
}
function hasOutside(list) { return list.some(function (s) { return s.indexOf("secret_outside") >= 0; }); }

//  --- (1) THE ESCAPE: a `../` stem from the wt root must not read OUTSIDE -------
const c1 = mkPager("");                                  // empty view path → base = wt
const esc1 = c1._fsCompletions("../OUTSIDE/");
ok(!hasOutside(esc1), "a `../OUTSIDE/` stem must NOT enumerate the sibling above the wt: "
   + JSON.stringify(esc1));

//  --- (2) THE ESCAPE via the VIEW dir: `../../` climbs wt/inside → wt → root ----
const c2 = mkPager("inside");                            // view dir = wt/inside
const esc2 = c2._fsCompletions("../../OUTSIDE/");
ok(!hasOutside(esc2), "a view-relative `../../OUTSIDE/` stem must NOT escape the wt: "
   + JSON.stringify(esc2));

//  --- (3) positive control: an in-tree stem STILL completes (fix is confined) ---
const good = mkPager("");
const in1 = good._fsCompletions("inside/");
ok(in1.some(function (s) { return s.indexOf("file_inside") >= 0; }),
   "an in-tree `inside/` stem still completes to its entries: " + JSON.stringify(in1));

//  --- (4) unified spell resolution: an over-climbing `../` THROWS NAVESCAPE -----
const sp = new pager.Pager(-1, { color: false });
sp._verbUri = function () { return { uri: "cat://journal/todo/URI/URI-014.mkd" }; };
let threw = false;
try { sp._resolveSpell("../../../../../x"); } catch (e) { threw = true; }
ok(threw, "an over-climbing relative spell throws NAVESCAPE (one semantics with discover.resolve)");
//  A benign in-tree `../` still resolves (collapsed, not verbatim).
const okSpell = sp._resolveSpell("../X");
ok(okSpell.indexOf("..") < 0, "a benign `../X` spell is COLLAPSED, not kept verbatim: " + okSpell);

//  --- cleanup ------------------------------------------------------------------
io.unlink(root + "/OUTSIDE/secret_outside"); io.rmdir(root + "/OUTSIDE");
io.unlink(wt + "/inside/file_inside"); io.rmdir(wt + "/inside");
io.rmdir(wt); io.rmdir(root);

io.log("PASS be-js-bro-navescape (BE-027: _fsCompletions confined, spell `..` unified)\n");
