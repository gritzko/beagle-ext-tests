//  JSQUE-005: repro+parity test for core/emit.js — the output-as-ULog row
//  sink + edge flush.  Asserts the RENDERED bytes match the native banner
//  shape (the `put:` 7-space blank-date rows + the `get` real-date rows),
//  proving render.js (dateCol/verbCol) parity, NOT the C HUNK path.
//
//  RUN from inside the JSQUE-005 worktree (a `be -> .` symlink makes the
//  be-relative require find core/emit.js + be/lib/render.js there):
//    cd ~/todo/JSQUE-005 && JSQUE5=$PWD jab beagle/test/js/emit.js
"use strict";

const { eq, ok, bytesEq, fail } = require("./lib/assert.js");

//  Resolve core/emit.js + be/lib/render.js from the CODE worktree (env
//  JSQUE5), independent of this test's main-tree location.
const ROOT = io.getenv("JSQUE5");
if (!ROOT) fail("set JSQUE5=<worktree root> (the ~/todo/JSQUE-005 tree)");
const emit   = require(ROOT + "/core/emit.js");
const render = require(ROOT + "/be/lib/render.js");

const dec = (u8) => utf8.Decode(u8);

//  --- (1) PUT shape: real-date header, BLANK-date (7-space) rows ----------
//  Native `be put a.txt e.txt` (od -c verified): header ` <date>  put put:`
//  then per-row `        put <path>` — 7 blank-date spaces + joiner + verb.
{
  const out = emit.create();
  const ts = ron.now();
  out.banner("put", "put:", ts);            // the open `put:` table header
  out.row("a.txt", "put", 0n);              // ts 0 → blank-date row
  out.row("e.txt", "put", 0n);
  const got = out.render();

  //  Expected, built straight from render.js the way every verb banner is.
  let want = render.dateCol(ts) + " " + render.verbCol("put") + " put:\n";
  want += render.dateCol(0n) + " " + render.verbCol("put") + " a.txt\n";
  want += render.dateCol(0n) + " " + render.verbCol("put") + " e.txt\n";
  bytesEq(got, utf8.Encode(want), "put: rendered bytes");

  //  Hard byte-parity anchor: a blank-date row MUST be 7 spaces + joiner,
  //  NOT ron.date(0n)'s `   ?   ` placeholder (the C HUNK-banner trap).
  const line = dec(got).split("\n")[1];
  eq(line.slice(0, 8), "        ", "put: row date column is 8 spaces (7 blank + joiner)");
  ok(dec(got).indexOf("?") < 0, "put: no `?` placeholder leaked in");
}

//  --- (2) GET shape: real-date header AND real-date rows ------------------
//  Native `be get` (od -c verified): ` <date>  get ?#<hashlet>` then
//  ` <date>  new <path>` — every row carries the REAL ts, not a blank date.
{
  const out = emit.create();
  const ts = ron.now();
  out.banner("get", "?#01be107f", ts);
  out.row("a.txt", "new", ts);
  out.row("b.txt", "new", ts);
  out.row("sub/c.txt", "new", ts);
  const got = out.render();

  let want = render.dateCol(ts) + " " + render.verbCol("get") + " ?#01be107f\n";
  for (const p of ["a.txt", "b.txt", "sub/c.txt"])
    want += render.dateCol(ts) + " " + render.verbCol("new") + " " + p + "\n";
  bytesEq(got, utf8.Encode(want), "get: rendered bytes");

  const line = dec(got).split("\n")[1];
  ok(line.slice(0, 7) !== "       ", "get: row carries a real date, not blank");
}

//  --- (3) collect-and-sort AT THE FLUSH (get: new+upd lex, then del lex) --
{
  const out = emit.create();
  const ts = ron.now();
  out.banner("get", "?#deadbeef", ts);
  //  Push OUT of order; the flush sort must reorder to new+upd(lex)+del(lex).
  out.row("z.txt", "del", ts);
  out.row("m.txt", "new", ts);
  out.row("a.txt", "upd", ts);
  out.row("b.txt", "del", ts);
  out.row("c.txt", "new", ts);
  //  get's edge sort: non-del lex, THEN del lex.
  const byPath = (a, b) => a.uri < b.uri ? -1 : a.uri > b.uri ? 1 : 0;
  const getSort = (rows) => rows.filter(r => r.verb !== "del").sort(byPath)
                       .concat(rows.filter(r => r.verb === "del").sort(byPath));
  const got = dec(out.render(getSort));
  const paths = got.split("\n").slice(1).filter(Boolean)
                   .map(l => l.slice(8 + 4));   // strip 8-col date + 3+1 verb
  //  new/upd a,c,m (lex) THEN del b,z (lex).
  eq(paths.join("|"), "a.txt|c.txt|m.txt|b.txt|z.txt", "get sort: bad order");
}

//  --- (4) PUT sort: move/dir rows before file rows ------------------------
{
  const out = emit.create();
  const ts = ron.now();
  out.banner("put", "put:", ts);
  //  Tag each row with a `pass` so the put sort keeps pass-1 (move/dir)
  //  before pass-2 (file), each pass in insertion order (native order).
  out.row("new.txt", "put", 0n, { pass: 2 });
  out.row("old.txt#dst.txt", "put", 0n, { pass: 1 });
  out.row("dir/x.txt", "put", 0n, { pass: 1 });
  const putSort = (rows) => rows.slice().sort((a, b) => (a.pass || 0) - (b.pass || 0));
  const got = dec(out.render(putSort));
  const paths = got.split("\n").slice(1).filter(Boolean).map(l => l.slice(8 + 4));
  eq(paths.join("|"), "old.txt#dst.txt|dir/x.txt|new.txt",
     "put sort: move/dir before file");
}

//  --- (5) END-TO-END parity vs a REAL native `put:` banner ----------------
//  If the harness captured a live native sample (EMIT_NATIVE_PUT), prove the
//  emit.js render reproduces it byte-for-byte after normalising ONLY the
//  wall-clock date column (the two runs are seconds apart).  This is the
//  render.js-path-matches-native evidence the ticket asks for.
{
  const sample = io.getenv("EMIT_NATIVE_PUT");
  if (sample) {
    const natBytes = io.mmap(sample, "r").data();
    const nat = dec(new Uint8Array(natBytes));
    //  The sample is `be put a.txt e.txt`: header + two blank-date rows.
    const out = emit.create();
    out.banner("put", "put:", ron.now());
    out.row("a.txt", "put", 0n);
    out.row("e.txt", "put", 0n);
    const js = dec(out.render());
    //  Normalise the 7-col date field on the header line (` HH:MM ` width)
    //  to compare the structural bytes; the blank-date rows are already
    //  date-stable, so any drift there is a real parity bug.
    const norm = (s) => s.replace(/^ *[0-9]{1,2}:[0-9]{2} +put/m, "T put");
    eq(norm(js), norm(nat), "put: emit render != live native banner");
  }
}

io.log("emit.js OK\n");
