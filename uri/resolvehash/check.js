//  URI-016: the resolve_hash() record, asserted field-by-field against
//  [/wiki/URI] §URI->hash resolution.  $PROJ = the scratch project root (a
//  layout: meta/ + .be + work/WT, with a nested sub inside the wt).
"use strict";

const { eq, ok, fail } = require(io.getenv("ROOT") + "/lib/assert.js");
const WT = io.getenv("BEDIR");
const rh = require(WT + "/core/resolve_hash.js").resolve_hash;

const PROJ = io.getenv("PROJ");
const MAIN_SHA = io.getenv("MAIN_SHA");     // the main tree's tip
const WT_SHA = io.getenv("WT_SHA");     // the wt's tip
const SUB_SHA  = io.getenv("SUB_SHA");      // DE-FACTO: the sub's own checkout
const PIN      = io.getenv("PIN");          // DE-JURE: the parent's gitlink

function threw(c, u, code) {
  let e;
  try { rh(c, u); } catch (x) { e = String(x); }
  if (!e) fail(code + ": " + JSON.stringify(u) + " did not throw");
  if (e.indexOf(code) !== 0) fail("want " + code + ", got: " + e);
}

//  --- steps 1-4: the frame, off `//WT` ---------------------------------
//  A real layout: ONE store (`$PROJ/.be`) with a NAMED shard (`alpha`); the wt
//  and the sub are CLONES of it, each with its own wtlog.  So store/shard is the
//  SAME dir for every tree here, and only chash/spath/rpath re-anchor.
const r = rh("//WT", "main.js");
eq(r.store, PROJ + "/.be/", "step 1: store = the PROJECT root's store (one per project)");
eq(r.shard, "alpha", "step 4: shard = the named shard under that store");
eq(r.mpath, PROJ + "/",     "step 1: mpath = the main tree");
eq(r.wtree, "WT",         "step 4: wtree");
eq(r.spath, "",             "step 4: spath (no sub)");
eq(r.rpath, "main.js",      "step 4: rpath");
eq(r.chash, WT_SHA,       "step 5.5: chash = the wt's own tip");
eq(r.otype, "blob",         "step 6: otype");
ok(/^[0-9a-f]{40}$/.test(r.ohash), "step 6: ohash is a full sha");
ok(r.ohash !== r.chash, "step 6: a blob's ohash is NOT the chash");

//  step 2: `///mtrel` is the MAIN tree — its own store AND its own tip, never
//  the wt's (the record must re-anchor, not inherit the context's tree).
const m = rh("//WT", "///README.mkd");
eq(m.wtree, "", "step 2: ///mtrel has no wtree");
eq(m.rpath, "README.mkd", "step 2: ///mtrel rpath");
eq(m.chash, MAIN_SHA, "step 2: ///mtrel resolves the MAIN tree's tip");
eq(m.store, PROJ + "/.be/", "step 2: ///mtrel reads the same project store");
ok(m.chash !== r.chash, "step 2: the main tree's tip is NOT the wt's");

//  step 3.1: a worktree-less uri takes the context's worktree.
eq(rh("//WT", "main.js").wtree, "WT", "step 3.1: wtree from the context");
//  step 3.2: a relative path resolves against the context's path; an own
//  authority reroots; a rooted path addresses the tree root.
eq(rh("//WT/dir", "deep.txt").rpath, "dir/deep.txt", "step 3.2: ctx-relative");
eq(rh("//WT/dir", "./deep.txt").rpath, "dir/deep.txt", "step 3.2: ./ctx-relative");
eq(rh("//WT/dir", "../main.js").rpath, "main.js", "step 3.2: ../ climbs in-tree");
eq(rh("//WT/dir", "/main.js").rpath, "main.js", "step 3.2: /rooted = tree root");
eq(rh("//WT/dir", "//WT/main.js").rpath, "main.js", "step 3.1: own authority reroots");

//  --- step 4: the mount, BOTH readings — the trailing-slash convention -----
//  The sub is pinned AHEAD of its own checkout, so the two readings cannot
//  coincide by accident: PIN (what the wt recorded) != SUB_SHA (what the sub
//  has checked out).

//  `sub/` — ENTERED.  Step 4 re-anchors into the mount, step 5.5 reads the
//  SUB's own wtlog: the DE-FACTO checkout.
const df = rh("//WT", "sub/");
eq(df.spath, "sub/",   "de-facto: spath = the submodule path");
eq(df.rpath, "",       "de-facto: rpath = the sub's own root");
eq(df.chash, SUB_SHA,  "de-facto: chash = the SUB's own checkout, not the parent's tip");
eq(df.otype, "tree",   "de-facto: the sub's root TREE");
ok(df.chash !== r.chash, "de-facto: the sub's tip is NOT the parent wt's");

//  `sub` — NAMED by its parent.  No re-anchor: step 6 walks the PARENT's tree to
//  the gitlink entry, which IS a commit: the DE-JURE pin.
const dj = rh("//WT", "sub");
eq(dj.spath, "",       "de-jure: no descent, so no spath");
eq(dj.rpath, "sub",    "de-jure: rpath = the entry in the PARENT's tree");
eq(dj.chash, r.chash,  "de-jure: chash = the PARENT's commit");
eq(dj.otype, "commit", "de-jure: a gitlink entry IS a commit");
eq(dj.ohash, PIN,      "de-jure: ohash = the pin the parent recorded");
ok(dj.ohash !== df.chash, "the two readings differ: pin != checkout");

//  A path THROUGH the mount is already inside — it carries the `/` after `sub`.
const th = rh("//WT", "sub/README.mkd");
eq(th.spath, "sub/",      "through: spath = the submodule path");
eq(th.rpath, "README.mkd","through: rpath = the path WITHIN the submodule");
eq(th.chash, SUB_SHA,     "through: resolved at the SUB's own checkout");
eq(th.otype, "blob",      "through: otype inside the sub");

//  --- step 5: the ladder, every rung landing on the SAME commit -----------
const full = WT_SHA, hashlet = WT_SHA.slice(0, 7);
eq(rh("//WT", "main.js#" + full).chash,    full, "5.1: #fullsha");
eq(rh("//WT", "main.js#" + hashlet).chash, full, "5.2: #hashlet");
eq(rh("//WT", "main.js?").chash,           full, "5.3: ?trunk via the reflog");
eq(rh("//WT", "main.js?" + hashlet).chash, full, "5.4: ?hashlet via the index");
eq(rh("//WT", "main.js").chash,            full, "5.5: the tree's own tip");

//  Precedence: the fragment WINS over the query (5.1/5.2 precede 5.3/5.4).
//  `?nosuchbranch` alone is REFNONE, so a resolving `#` proves the fragment won.
eq(rh("//WT", "main.js?nosuchbranch#" + full).chash, full,
   "step 5: the fragment precedes the query");

//  --- refusals: an ok64 code, never a partial record ----------------------
threw("//WT", "main.js#" + r.ohash, "NOTACOMMIT");
threw("//WT", "main.js#deadbeefcafe", "HASHNONE");
threw("//WT", "main.js?nosuchbranch", "REFNONE");
threw("//WT", "nosuchfile.js",        "PATHNONE");
threw("//WT", "../../../etc/passwd",  "NAVESCAPE");
threw("//NOSUCHWT", "x",                "WTNONE");
threw("//WT", "file:/etc/passwd",     "URISCHEME");

io.log("PASS [resolvehash] the 9-field record, 6 steps, de-facto/de-jure, 7 refusals");
