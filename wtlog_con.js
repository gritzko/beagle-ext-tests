//  ULOG-004: shared/wtlog.js conflicts() — the cheap conflict list (DIS-080):
//  `con <path>` rows scanned BACK from the tip to the last get/post BARRIER,
//  deduped, oldest-first.  Row-scoped liveness: no wt byte scan, no markers.
//  Legs: con only, con+post, con+get, multi-patch dups, con after a barrier,
//  non-barriers (patch/put/delete/a wt-relative scoped get row) and a
//  sub re-attach address row (`//wt/sub#sha`) which IS a barrier.
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
const A = SHA("a"), B = SHA("b"), C = SHA("c");

const TMP = io.getenv("TMP") || "/tmp";
const base = TMP + "/ulog004-con-" + Date.now() + "-" + (Math.random() * 1e9 | 0);
io.mkdir(base);
let seq = 0;
//  A fresh fixture wtlog carrying `rows`, opened as a reader (project "p").
function fixture(rows) {
  const p = base + "/wtlog-" + (seq++);
  ulog.append(p, rows);
  return wtlog.open({ bePath: p, project: "p" });
}

const CON = (p) => ({ verb: "con", uri: p });

//  --- leg A: con rows with no barrier at all -----------------------------
(function () {
  const r = fixture([{ verb: "get", uri: "file:" + base + "/.be/?/p" },
                     CON("src/a.c"), CON("src/b.c")]);
  const c = r.conflicts();
  eq(c.length, 2, "A: both con paths");
  eq(c[0], "src/a.c", "A: oldest-first");
  eq(c[1], "src/b.c", "A: second path");
})();

//  --- leg B: con then post — a post is a barrier, conflicts expire -------
(function () {
  const r = fixture([{ verb: "get", uri: "?main#" + A },
                     CON("src/a.c"),
                     { verb: "post", uri: "?main#" + B }]);
  eq(r.conflicts().length, 0, "B: a post clears the list");
})();

//  --- leg C: con then get — a whole-tree get is a barrier too ------------
(function () {
  const r = fixture([{ verb: "get", uri: "?main#" + A },
                     CON("src/a.c"),
                     { verb: "get", uri: "?main#" + B }]);
  eq(r.conflicts().length, 0, "C: a get clears the list");
})();

//  --- leg D: multi-patch stacking — duplicate con rows dedup ------------
(function () {
  const r = fixture([{ verb: "get", uri: "?main#" + A },
                     { verb: "patch", uri: "?" + B }, CON("src/a.c"),
                     { verb: "patch", uri: "?" + C }, CON("src/a.c"),
                     CON("src/b.c")]);
  const c = r.conflicts();
  eq(c.length, 2, "D: deduped");
  eq(c[0], "src/a.c", "D: first occurrence keeps its slot");
  eq(c[1], "src/b.c", "D: the second path");
})();

//  --- leg E: con AFTER the barrier stays live ---------------------------
(function () {
  const r = fixture([{ verb: "get", uri: "?main#" + A },
                     CON("old.c"),
                     { verb: "post", uri: "?main#" + B },
                     CON("new.c")]);
  const c = r.conflicts();
  eq(c.length, 1, "E: only the post-barrier con");
  eq(c[0], "new.c", "E: the live path");
})();

//  --- leg F: non-barriers — patch, put, delete, a SCOPED get row --------
//  A scoped `get <path>` must not amnesty unrelated paths: a wt-relative
//  path row is a scope, not a tip move (today it writes no row at all).
(function () {
  const r = fixture([{ verb: "get", uri: "?main#" + A },
                     CON("src/a.c"),
                     { verb: "patch", uri: "?" + B },
                     { verb: "put", uri: "src/x.c" },
                     { verb: "delete", uri: "src/y.c" },
                     { verb: "get", uri: "src/z.c?main#" + C }]);
  const c = r.conflicts();
  eq(c.length, 1, "F: none of these is a barrier");
  eq(c[0], "src/a.c", "F: the conflict survives");
})();

//  --- leg G: a sub re-attach address row IS a barrier -------------------
(function () {
  const r = fixture([{ verb: "get", uri: "?main#" + A },
                     CON("src/a.c"),
                     { verb: "get", uri: "//wt/sub#" + B }]);
  eq(r.conflicts().length, 0, "G: an addressed get is a tip move");
})();

//  --- leg H: a ref-less anchor row is no barrier ------------------------
(function () {
  const r = fixture([CON("src/a.c"),
                     { verb: "get", uri: "file:" + base + "/.be/?/p" }]);
  eq(r.conflicts().length, 1, "H: a store anchor pins nothing, clears nothing");
})();

//  --- leg I: an empty log has no conflicts ------------------------------
(function () {
  const r = fixture([{ verb: "get", uri: "?main#" + A }]);
  const c = r.conflicts();
  ok(Array.isArray(c) && c.length === 0, "I: empty array");
})();

//  cleanup
for (const f of io.readdir(base)) { try { io.unlink(base + "/" + f); } catch (e) {} }

io.log("wtlog_con.js OK\n");
