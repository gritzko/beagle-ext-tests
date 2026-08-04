//  classify.wtWalk — the pruning descent.  An ignored dir and a nested repo are
//  cut at their boundary, so neither subtree is enumerated; both DIR ENTRIES
//  survive in `names` (cache.js arms `.be/` off exactly that) and
//  `underNested` still answers for paths under the boundary.  The answer must
//  be the same one the flat-walk-then-filter version gave: this file pins the
//  observable half — what wtScan keeps — against a hand-written expectation.
"use strict";

const { eq, ok } = require("./lib/assert.js");
function _req(mod) {
  const self = (typeof process !== "undefined" && process.argv && process.argv[1]) || "";
  if (self) {
    const d = self.slice(0, self.lastIndexOf("/test/"));
    if (d && d !== self) { try { return require(d + "/" + mod); } catch (e) {} }
  }
  return require(mod);
}
const classify = _req("shared/classify.js");
const ignorelib = _req("shared/util/ignore.js");

const TMP = io.getenv("TMP") || "/tmp";
const wt = TMP + "/wtwalk-" + Date.now() + "-" + (Math.random() * 1e9 | 0);
function write(p, s) {
  const u = utf8.Encode(s), b = io.buf(u.length + 8); b.feed(u);
  const fd = io.open(p, "c"); io.writeAll(fd, b); io.close(fd);
}
//  src/a.c            tracked
//  build/big/x.o      IGNORED dir (`build/` in .gitignore) — subtree pruned
//  sub/.be + sub/s.c  a nested repo — boundary, subtree pruned
//  .be                the repo's own meta dir, ignored but ARMED by cache.js
io.mkdir(wt + "/src"); io.mkdir(wt + "/build/big"); io.mkdir(wt + "/sub/deep");
io.mkdir(wt + "/.be");
write(wt + "/.gitignore", "build/\n");
write(wt + "/src/a.c", "int a;\n");
write(wt + "/build/big/x.o", "junk");
write(wt + "/sub/.be", "");                    // the nested-repo boundary marker
write(wt + "/sub/s.c", "int s;\n");
write(wt + "/sub/deep/d.c", "int d;\n");
write(wt + "/sub/deep/.be", "");               // a nested repo INSIDE a nested one
write(wt + "/.be/wtlog", "");

//  Does THIS jab honour the `"skip"` directive?  Without it `"skip"` reads as
//  `"more"` and the walk enumerates every entry as it always did — the answers
//  below must come out the same either way, which is what makes the JS switch
//  safe to land ahead of the binary.
const probe = TMP + "/wtwalk-probe-" + Date.now();
io.mkdir(probe + "/d/deeper");
let sawDeep = false;
io.readdir(probe, { recursive: true, hidden: true, callback: function (nm) {
  if (nm === "d/deeper/") sawDeep = true;
  return nm === "d/" ? "skip" : "more";
} });
io.rmdir(probe, true);
const PRUNES = !sawDeep;

const ig = ignorelib.load(wt);
const w = classify.wtWalk(wt, ig);
const names = new Set(w.names);

//  --- the two boundaries: the dir ENTRY is kept either way ------------------
ok(names.has("build/"), "the ignored dir entry itself survives");
ok(names.has("sub/"), "the nested-repo dir entry itself survives");
ok(names.has(".be/"), "the repo's own .be dir entry survives (cache.js arms it)");

//  --- the subtrees: pruned on a jab that has "skip", enumerated on one that
//      does not.  Either way nothing below reaches a consumer (see wtScan).
eq(names.has("build/big/x.o"), !PRUNES, "the ignored dir's subtree");
eq(names.has("sub/s.c"), !PRUNES, "the nested repo's files");
eq(names.has("sub/deep/"), !PRUNES, "the nested repo's subdirs");
eq(names.has(".be/wtlog"), !PRUNES, ".be's contents");

//  --- what survives is the tracked tree, untouched --------------------------
ok(names.has("src/"), "a plain dir");
ok(names.has("src/a.c"), "a plain file");
ok(names.has(".gitignore"), "a tracked dotfile (hidden:true)");

//  --- the boundary list + underNested ---------------------------------------
//  The OUTERMOST boundary is always listed.  An INNER one (`sub/deep/`, a repo
//  inside a repo) is only ever seen by a walk that descended past `sub/` — the
//  pruning walk stops there and never learns of it.  That costs nothing: the
//  only reader is wtScan's outermost-mounts loop, which discards inner prefixes
//  anyway, and `underNested` answers for every path below `sub/` off `sub/`.
ok(w.nestedPrefixes.indexOf("sub/") >= 0, "the outermost boundary is listed");
eq(w.nestedPrefixes.length, PRUNES ? 1 : 2, "inner boundaries: only a walk that descends sees them");
ok(w.underNested("sub"), "underNested: the boundary dir itself");
ok(w.underNested("sub/deep/d.c"), "underNested: a path below it");
ok(w.underNested("sub/deep"), "underNested: the inner boundary, off the outer one");
ok(!w.underNested("src/a.c"), "underNested: a path outside it");

//  --- wtScan, the real consumer: same verdict -------------------------------
const scan = classify.wtScan(wt, ig);
ok(scan["src/a.c"], "wtScan keeps the tracked file");
ok(scan[".gitignore"], "wtScan keeps the tracked dotfile");
ok(!scan["build/big/x.o"], "wtScan drops the ignored subtree");
ok(!scan["sub/s.c"], "wtScan drops the nested repo's contents");
//  PUT-011: the nested-repo dir itself stays as ONE `s` entry.
ok(scan["sub"] && scan["sub"].kind === "s", "wtScan keeps the mount as one `s` row");

//  --- an unreadable root is an empty walk, not a throw ----------------------
const gone = classify.wtWalk(wt + "/nope", ig);
eq(gone.names.length, 0, "missing root: no names");
eq(gone.nestedPrefixes.length, 0, "missing root: no boundaries");

io.rmdir(wt, true);
io.log("wtwalk: ok\n");
