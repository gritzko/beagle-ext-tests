//  test/bro/barectx/barectx.js — DIS-061 regression: a BARE `:verb` spell must
//  run the verb at the CONTEXT with NO argument — it must NEVER scavenge a path
//  off a rendered hunk BANNER.  The live bug: the initial `status` view of a
//  worktree with a mounted sub renders two hunks — the parent report (banner
//  `status`) and the sub's aggregated report (banner `status test`, the sub
//  mounted at test/).  The sub banner's URI is the RELATIVE, authority-less
//  path `test`.  The old implied-subject WELD mis-took it for the view's sole
//  FILE subject and baked a bare `:diff` into `diff test` (arg-blind violated).
//  The weld is GONE now (DIS-061): the pager composes from the context + typed
//  verb + typed args ONLY, so `:diff` drives a BARE `diff` in the context.  A
//  multi-hunk view also stashes NO `be.prev_uri` (only a single-hunk FILE view
//  does), so `_prevUri()` is "" here too — no path leaks to a file-focused verb.
//  argv[2] = views/bro/pager.js.  $SRC_ROOT hosts SRC_ROOT/WT (a `.be/`-anchored
//  worktree) with a `test/` sub DIR, so `//WT/test` resolves + stats as a dir.
"use strict";
const pager = require(process.argv[2]);

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

//  The pager at launch context `//WT`, initial `status` view: two hunks whose
//  URI fields are the full banner spells (as captured from the HUNK log): the
//  parent `status` (no address) + the sub `status test` (relative sub path).
function mkStatusPager() {
  const rec = { drove: "", ctx: undefined };
  const p = new pager.Pager(-1, { color: false, context: "//WT",
    isVerb: function (v) { return v === "status" || v === "diff" || v === "cat"; },
    isMutation: function () { return false; },
    driveSpell: function (s, c2) {
      rec.drove = s; rec.ctx = c2;
      return [hunk(s)];
    } });
  p.setHunks([hunk("status"), hunk("status test")]);
  p.rec = rec;
  return p;
}

if (!SRC) {
  check("fixture-src-root", false, "no $SRC_ROOT");
} else {
  //  Sanity: the fixture must resolve `//WT/test` as a DIR (else the guard would
  //  reject for the wrong reason and the regression could not fire).
  const p0 = mkStatusPager();
  check("fixture-sub-is-dir", p0._ctxKind("//WT/test") === "dir", p0._ctxKind("//WT/test"));

  //  the CONTEXT of the initial view is `//WT` (launch context), not a hunk path.
  const p1 = mkStatusPager();
  check("ctx-is-launch", p1._composeCall("diff").context === "//WT",
        p1._composeCall("diff").context);

  //  THE REGRESSION: a bare `:diff` must drive a bare `diff` (context threaded),
  //  NEVER `diff test` welded off the `status test` banner.
  const p2 = mkStatusPager();
  p2._applySpell("diff");
  check("bare-diff-no-banner-arg", p2.rec.drove === "diff", p2.rec.drove);
  check("bare-diff-context", p2.rec.ctx === "//WT", p2.rec.ctx);

  //  a MULTI-hunk view stashes no file subject — `_prevUri()` is "" (the sub
  //  banner is never scavenged as the current file).
  const p3 = mkStatusPager();
  check("multi-hunk-no-prev-uri", p3._prevUri() === "", p3._prevUri());
}

tty.size = realSize;
w("DONE\n");
