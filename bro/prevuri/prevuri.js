//  test/bro/prevuri/prevuri.js — DIS-061: the pager stashes the CURRENT view's
//  file into the ambient `be.prev_uri` bridge so a bare FILE-focused verb
//  (why/vim) takes it as its default operand — WITHOUT the pager welding any
//  implied argument into the spell.  The stash always mirrors the current view:
//  set for a single-hunk FILE view (normalized: authority filled, wt-rooted,
//  ?rev + #L stripped), CLEARED for a multi-hunk / dir / empty view, and
//  recomputed on every view change (push / pop-back / re-drive).  Then the two
//  named verbs CONSUME it in their own handlers (the file-vs-dir choice lives
//  there, never in the pager).
//  argv[2] = views/bro/pager.js, argv[3] = views/why/why.js, argv[4] = verbs/vim/vim.js.
//  $SRC_ROOT hosts SRC_ROOT/WT (a `.be/`-anchored worktree) with a `test/` sub
//  DIR and a `dog.h` regular FILE, so `//WT/test` stats dir, `//WT/dog.h` reg.
"use strict";
const pager = require(process.argv[2]);
const why   = require(process.argv[3]);
const vim   = require(process.argv[4]);

//  DIS-061: mint a minimal ambient `be` so the pager's stash lands somewhere
//  assertable and the verbs read it (the JAB-004 ctx→be bridge).
globalThis.be = globalThis.be || {};

function w(s) { const b = utf8.Encode(s); const x = io.buf(b.length + 8); x.feed(b); io.writeAll(1, x); }
function check(name, cond, got) {
  w((cond ? "ok   " : "FAIL ") + name + (cond ? "" : "   got " + JSON.stringify(got)) + "\n");
}

const SRC = io.getenv("SRC_ROOT") || "";

const realSize = tty.size;
tty.size = function () { return { rows: 24, cols: 80 }; };

function hunk(uri, text) {
  return { uri: uri, verb: "hunk", text: utf8.Encode(text || "x\n"),
           toks: new Uint32Array(0), kind: "file" };
}

//  A pager at launch context `//WT` with a mock driveSpell that ECHOES the spell
//  it was handed (as a one-hunk view) and records the (spell, context) pair.
function mkPager() {
  const rec = { drove: "", ctx: undefined };
  const p = new pager.Pager(-1, { color: false, context: "//WT",
    isVerb: function (v) { return v === "status" || v === "diff" || v === "cat" ||
                                  v === "why" || v === "vim"; },
    isMutation: function () { return false; },
    driveSpell: function (s, c2) { rec.drove = s; rec.ctx = c2; return [hunk(s)]; } });
  p.rec = rec;
  return p;
}

if (!SRC) {
  check("fixture-src-root", false, "no $SRC_ROOT");
} else {
  //  ---- 1. a single-hunk FILE view STASHES the normalized file URI ----------
  const p1 = mkPager();
  p1.setHunks([hunk("//WT/dog.h")]);
  check("file-view-prevuri", p1._prevUri() === "//WT/dog.h", p1._prevUri());
  check("file-view-stash", be.prev_uri === "//WT/dog.h", be.prev_uri);

  //  ?rev + #L are STRIPPED — the stash is the file's identity, not a position.
  const p1b = mkPager();
  p1b.setHunks([hunk("//WT/dog.h?abcd1234#L5")]);
  check("file-view-strip-rev-line", p1b._prevUri() === "//WT/dog.h", p1b._prevUri());

  //  ---- 2. a DIR view CLEARS the stash (single hunk, but a directory) --------
  const p2 = mkPager();
  p2.setHunks([hunk("//WT/test")]);
  check("dir-view-empty", p2._prevUri() === "", p2._prevUri());
  check("dir-view-stash-clear", be.prev_uri === "", be.prev_uri);

  //  ---- 3. a MULTI-hunk view CLEARS the stash --------------------------------
  const p3 = mkPager();
  p3.setHunks([hunk("//WT/dog.h"), hunk("//WT/test")]);
  check("multi-hunk-empty", p3._prevUri() === "", p3._prevUri());
  check("multi-hunk-stash-clear", be.prev_uri === "", be.prev_uri);

  //  ---- 4. STALENESS: push a file view, then BACK to the dir view -> cleared -
  const p4 = mkPager();
  p4.setHunks([hunk("//WT/test")]);                // dir view
  check("stale-start-dir", be.prev_uri === "", be.prev_uri);
  p4.pushView([hunk("//WT/dog.h")]);               // descend to a file
  check("stale-push-file", be.prev_uri === "//WT/dog.h", be.prev_uri);
  p4.popView();                                    // back to the dir view
  check("stale-pop-cleared", be.prev_uri === "", be.prev_uri);

  //  ---- 5. a bare `:why` drives BARE (no welded arg); the file rides the stash
  const p5 = mkPager();
  p5.setHunks([hunk("//WT/dog.h")]);
  check("bare-why-stash-ready", be.prev_uri === "//WT/dog.h", be.prev_uri);
  p5._applySpell("why");
  check("bare-why-no-arg", p5.rec.drove === "why", p5.rec.drove);   // never `why dog.h`
  check("bare-why-context", p5.rec.ctx === "//WT", p5.rec.ctx);

  //  ---- 6. the WHY handler CONSUMES be.prev_uri when no operand is typed ------
  be.prev_uri = "//WT/dog.h";
  check("why-no-arg-uses-prev", why.whyArgs([]).length === 1 &&
        why.whyArgs([])[0] === "//WT/dog.h", why.whyArgs([]));
  check("why-arg-wins", why.whyArgs(["x.h"]).length === 1 && why.whyArgs(["x.h"])[0] === "x.h",
        why.whyArgs(["x.h"]));
  be.prev_uri = "";
  check("why-no-arg-no-prev-noop", why.whyArgs([]).length === 0, why.whyArgs([]));

  //  ---- 7. the VIM handler resolves be.prev_uri as its default file ----------
  const realOpen = io.open, realSpawn = io.spawnFds, realReap = io.reap;
  function runVim() {
    let captured = null, threw = null;
    io.open = function () { throw "no tty"; };            // → fd null → pass -1
    io.spawnFds = function (bin, argv) { captured = argv[1]; return 4242; };
    io.reap = function () { return { code: 0 }; };
    try { vim(); } catch (e) { threw = String(e); }
    finally { io.open = realOpen; io.spawnFds = realSpawn; io.reap = realReap; }
    return { captured: captured, threw: threw };
  }
  be.verb = "vim";
  be.context = "//WT/test";

  be.prev_uri = "//WT/dog.h";
  const v1 = runVim();
  check("vim-no-arg-uses-prev", v1.captured === SRC + "/WT/dog.h", v1);

  //  empty stash → today's behaviour: the nav CONTEXT's own path.
  be.prev_uri = "";
  const v2 = runVim();
  check("vim-no-prev-falls-to-context", v2.captured === SRC + "/WT/test", v2);

  //  empty stash AND no context → the unchanged VIMNONE miss.
  be.context = "";
  const v3 = runVim();
  check("vim-no-prev-no-ctx-miss", v3.threw === "VIMNONE", v3);
}

tty.size = realSize;
w("DONE\n");
