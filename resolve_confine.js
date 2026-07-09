//  BE-030 test/resolve_confine.js — unit repro for core/discover.js
//  resolve(context, rel), the CONTEXT-CONFINED path resolver.  `context` (a URI
//  OBJECT) carries BOTH the tree NAME (its authority) and the TRUSTED in-repo dir
//  (its path) the relative arg resolves against; `rel` is a PATH, NEVER a URI —
//  a `//other` authority or a `scheme:` in `rel` is REFUSED (the //OTHER escape),
//  and a `..` climb above the tree root THROWS "NAVESCAPE".  So a resolved path
//  can NEVER leave $SRC_ROOT/<context-name>/.  Run: jab test/resolve_confine.js.
"use strict";

const { eq, ok, throws } = require("./lib/assert.js");
//  Derive the be/ code dir from THIS script's path (cf. test/uri.js _req); the
//  fallback require() rides jab's upward be/-scan to the same worktree module.
const discover = _req("core/discover.js");
function _req(mod) {
  const self = (typeof process !== "undefined" && process.argv && process.argv[1]) || "";
  if (self) {
    const d = self.slice(0, self.lastIndexOf("/test/"));
    if (d && d !== self) { try { return require(d + "/" + mod); } catch (e) {} }
  }
  return require(mod);
}

const resolve = discover.resolve;
const SR = discover.srcRoot();                     // whatever root this box resolves
const ctx = uri._parse("//ABC-123/dir");           // POINT 6: context is a URI OBJECT

//  (1) a plain relative path resolves UNDER the context tree, against the context's
//  OWN path (the folded-in base): //ABC-123/dir + sub/y.
eq(resolve(ctx, "sub/y"), SR + "/ABC-123/dir/sub/y", "rel joins context path under tree");
//  (2) an IN-tree `..` climb is allowed (stays within the tree).
eq(resolve(ctx, "../sib"), SR + "/ABC-123/sib", "in-tree .. stays confined");
//  (3) a rooted `/x` rel addresses the tree ROOT (context path dropped).
eq(resolve(ctx, "/rooted"), SR + "/ABC-123/rooted", "rooted rel drops context path");
//  (4a) no rel → the context's OWN dir (its path).
eq(resolve(ctx, ""), SR + "/ABC-123/dir", "empty rel → context dir");
//  (4b) a PATH-LESS context → the tree root (the old `base=""` case, now expressed
//  as a context with no path — NOT a separate arg).
eq(resolve(uri._parse("//ABC-123"), ""), SR + "/ABC-123", "path-less context → tree root");

//  (5) POINT 5: `rel` is a PATH, not a URI — a `//other` authority is REFUSED
//  (this closes the resolve('//ABC','//OTHER/x') → $SRC_ROOT/OTHER escape) ...
throws(function () { resolve(ctx, "//OTHER/x"); }, "rel //OTHER authority refused");
//  ... and a `scheme://` transport in `rel` is REFUSED.
throws(function () { resolve(ctx, "git://h/x"); }, "rel scheme refused");

//  (6) CONFINEMENT: a `..` that climbs ABOVE the tree root THROWS NAVESCAPE.
throws(function () { resolve(ctx, "../../x"); }, "climb above tree root refused");
//  (7) a bad authority NAME (`..`) in the context is refused too.
throws(function () { resolve(uri._parse("//.."), "x"); }, "bad nav authority refused");

//  (8) THE INVARIANT: whatever the rel, a resolved path stays under
//  $SRC_ROOT/<name> — the confinement is a PROPERTY of the one function.
for (const rel of ["a", "a/b/c", "./d", "../dir/e", "x/../y"]) {
  const p = resolve(ctx, rel);
  ok(p.indexOf(SR + "/ABC-123/") === 0 || p === SR + "/ABC-123",
     "confined under //ABC-123: '" + rel + "' -> " + p);
}

io.log("PASS be-js-unit-resolve_confine\n");
