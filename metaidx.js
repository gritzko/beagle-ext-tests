//  TODO-003: shared/metaidx.js — the meta-pair index over ONE `kv64` lane.
//  Hermetic: the live `todo/` has ~840 tickets and 13 meta pairs, so it proves
//  nothing; every case plants its OWN ticket fixtures + its OWN shard in $TMP
//  and stamps explicit mtimes (io.setMtime), so the mark arithmetic is exact.
//
//  Covered: cold fill vs warm skip counts; an edited file re-lexed; a pair
//  that vanished from a live file; a deleted ticket file; an absent key
//  early-out; two worktrees sharing one shard; a crash mid-sweep (a seal that
//  did NOT advance the mark) re-lexing rather than skipping; and a value that
//  overwrites (`Sta: OPEN` -> `Sta: DONE` leaves exactly ONE row, the new one).
"use strict";

const { eq, ok } = require("./lib/assert.js");
//  DIS-054: derive the be/ code dir from THIS script's path (test/ingest.js model).
function _req(mod) {
  const self = (typeof process !== "undefined" && process.argv && process.argv[1]) || "";
  if (self) {
    const d = self.slice(0, self.lastIndexOf("/test/"));
    if (d && d !== self) { try { return require(d + "/" + mod); } catch (e) {} }
  }
  return require(mod);
}
const metaidx = _req("shared/metaidx.js");

const TMP = io.getenv("TMP") || "/tmp";
const FX = TMP + "/metaidx-" + Date.now() + "-" + (Math.random() * 1e9 | 0);

function mkdirp(p) {
  let acc = "";
  for (const s of p.split("/")) { if (s === "") { acc = ""; continue; }
    acc += "/" + s; try { io.mkdir(acc); } catch (e) {} }
}
function write(abs, body) {
  mkdirp(abs.slice(0, abs.lastIndexOf("/")));
  const fd = io.open(abs, "c");
  try {
    try { io.resize(fd, 0); } catch (e) {}
    const b = io.buf(body.length + 8); b.feed(utf8.Encode(body)); io.writeAll(fd, b);
  } finally { io.close(fd); }
}
//  A stamped mtime keeps the mark arithmetic exact: `T(n)` is a ron60 stamp
//  that ascends with n, so "the max mtime observed" is a value the case picks
//  rather than whatever the clock happened to hand the writer.
const BASE = ron.of(Date.UTC(2026, 0, 1));
function T(n) { return BASE + BigInt(n); }

//  Plant a wt: `<FX>/<name>/todo/<TOPIC>/<KEY>.mkd` (thin) or
//  `<KEY>/README.mkd` (fat).  Returns the wt root.
function wtOf(name) { return FX + "/" + name; }
function todoOf(name) { return wtOf(name) + "/todo"; }
function plant(name, rel, body, t) {
  const abs = todoOf(name) + "/" + rel;
  write(abs, body);
  io.setMtime(abs, T(t));
  return abs;
}
const SHARD = FX + "/store/.be/p";
function opts(name, extra) {
  const o = { todo: todoOf(name), wt: wtOf(name), shard: SHARD };
  for (const k in (extra || {})) o[k] = extra[k];
  return o;
}
function ids(res) { return res.tickets.map(function (t) { return t.id; }).sort().join(","); }

mkdirp(SHARD);

//  A ticket page with a header line + meta pairs, the [/meta/todo] layout.
function page(key, pairs, title) {
  let s = "#   " + key + ": " + (title || "a planted ticket") + "\n\n";
  for (const k in pairs) s += k + ": " + pairs[k] + "\n";
  s += "\nBody text with a Not: a pair line indented\n  Who: not at line start\n";
  return s;
}

// ==========================================================================
//  1. COLD FILL vs WARM SKIP.  A cold lane has no mark, so every file is
//     lexed; the warm run re-lexes ONLY the files at or past the mark (the
//     `>=` rule — the max-mtime file always costs one redundant read).
// ==========================================================================
plant("a", "GET/GET-001.mkd", page("GET-001", { Sta: "OPEN", Who: "gritzko" }), 10);
plant("a", "GET/GET-002.mkd", page("GET-002", { Sta: "DONE", Who: "gritzko" }), 20);
plant("a", "PUT/PUT-007/README.mkd", page("PUT-007", { Sta: "OPEN", Who: "ann" }), 30);
plant("a", "PUT/PUT-007/notes.mkd", "Sta: OPEN\n", 31);          // an ATTACHMENT
plant("a", "PUT/README.mkd", "#   PUT\n\nSta: OPEN\n", 32);       // not a ticket

{
  const r = metaidx.find({ Sta: "OPEN" }, opts("a"));
  eq(r.sweep.files, 3, "cold: three tickets (attachment + topic README excluded)");
  eq(r.sweep.lexed, 3, "cold: every file lexed");
  eq(r.sweep.skipped, 0, "cold: nothing skipped");
  ok(r.sweep.cold, "cold: no mark yet");
  eq(r.sweep.maxMtime, T(30), "cold: the mark is the MAX mtime observed");
  eq(ids(r), "GET/GET-001.mkd,PUT/PUT-007", "cold: the two open tickets (fat id = the DIR)");
}
{
  const r = metaidx.find({ Sta: "OPEN" }, opts("a"));
  eq(r.sweep.lexed, 1, "warm: only the max-mtime file re-lexes (>= the mark)");
  eq(r.sweep.skipped, 2, "warm: the older two skip");
  eq(r.sweep.put, 0, "warm: an identical re-lex writes no row");
  eq(r.sweep.mark, T(30), "warm: the mark was read back");
  eq(ids(r), "GET/GET-001.mkd,PUT/PUT-007", "warm: same answer from the index");
}
{
  const r = metaidx.find({ Who: "gritzko" }, opts("a"));
  eq(ids(r), "GET/GET-001.mkd,GET/GET-002.mkd", "Who: exact match, decased");
  const r2 = metaidx.find({ Sta: "OPEN", Who: "gritzko" }, opts("a"));
  eq(ids(r2), "GET/GET-001.mkd", "two clauses intersect");
  const r3 = metaidx.find({ Who: null }, opts("a"));
  eq(ids(r3), "GET/GET-001.mkd,GET/GET-002.mkd,PUT/PUT-007", "presence query");
}
io.log("metaidx.js cold/warm OK");

// ==========================================================================
//  2. AN EDITED FILE IS RE-LEXED, and the keyed lane collapses the overwrite:
//     `Sta: OPEN` -> `Sta: DONE` leaves EXACTLY ONE row, the new one.
// ==========================================================================
{
  plant("a", "GET/GET-001.mkd", page("GET-001", { Sta: "DONE", Who: "gritzko" }), 40);
  const r = metaidx.find({ Sta: "OPEN" }, opts("a"));
  //  the mark was T(30); the edit lands at T(40), so the edited file AND the
  //  T(30) file (the `>=` redundant read) re-lex, the T(20) one skips.
  eq(r.sweep.lexed, 2, "edit: the touched file + the at-the-mark file re-lex");
  eq(r.sweep.skipped, 1, "edit: the older file still skips");
  eq(r.sweep.put, 1, "edit: exactly one row rewritten (Sta) — the re-lex is a no-op");
  eq(r.sweep.tombed, 0, "edit: nothing vanished");
  eq(ids(r), "PUT/PUT-007", "edit: GET-001 left the OPEN list");
  eq(ids(metaidx.find({ Sta: "DONE" }, opts("a"))),
     "GET/GET-001.mkd,GET/GET-002.mkd", "edit: and joined the DONE list");

  //  the row itself: ONE `Sta` row on GET-001's block, carrying DONE.
  const ix = metaidx.openIndex(SHARD);
  const phl = metaidx.pathHl(todoOf("a") + "/GET/GET-001.mkd");
  const code = metaidx.codeOf("Sta");
  const got = [];
  ix.prefix(phl << 24n, 24, function (p) {
    if (metaidx.keyCode(p[0]) === code) got.push(p[1]);
  });
  ix.close();
  eq(got.length, 1, "overwrite: exactly ONE Sta row survives the merge");
  eq(got[0], metaidx.packValue("Sta", "DONE"), "overwrite: it is the NEW value");
  ok(got[0] !== metaidx.packValue("Sta", "OPEN"), "overwrite: the old value is gone");
}
io.log("metaidx.js edit + overwrite OK");

// ==========================================================================
//  3. A PAIR THAT VANISHED from a live file is tombstoned against its block.
// ==========================================================================
{
  plant("a", "GET/GET-002.mkd", page("GET-002", { Sta: "DONE" }), 50);   // Who: dropped
  const r = metaidx.find({ Who: null }, opts("a"));
  eq(r.sweep.tombed, 1, "vanished: one tombstone written");
  eq(ids(r), "GET/GET-001.mkd,PUT/PUT-007", "vanished: GET-002 no longer carries Who");
  eq(ids(metaidx.find({ Sta: "DONE" }, opts("a"))),
     "GET/GET-001.mkd,GET/GET-002.mkd", "vanished: its other pairs survive");
}
io.log("metaidx.js vanished pair OK");

// ==========================================================================
//  4. A DELETED ticket file: the sweep holds the complete path list, so the
//     whole block dies — the index never answers with a ghost.
// ==========================================================================
{
  io.unlink(todoOf("a") + "/GET/GET-002.mkd");
  const r = metaidx.find({ Sta: null }, opts("a"));
  eq(r.sweep.files, 2, "deleted: two tickets left on disk");
  ok(r.sweep.tombed >= 1, "deleted: the dead block was tombstoned");
  eq(ids(r), "GET/GET-001.mkd,PUT/PUT-007", "deleted: no ghost row answers");
  //  and a second sweep does not re-kill it
  const r2 = metaidx.find({ Sta: null }, opts("a"));
  eq(r2.sweep.tombed, 0, "deleted: the kill is not repeated");
  eq(ids(r2), "GET/GET-001.mkd,PUT/PUT-007", "deleted: stable");
}
io.log("metaidx.js deleted file OK");

// ==========================================================================
//  5. AN ABSENT KEY early-outs: no row in the lane carries the code, so the
//     answer is empty without a per-ticket test.
// ==========================================================================
{
  const r = metaidx.find({ For: "v9" }, opts("a"));
  eq(r.tickets.length, 0, "absent key: empty answer");
  eq(r.sweep.earlyOut, "For", "absent key: the early-out fired");
  //  a PRESENT key does not early-out
  const r2 = metaidx.find({ Sta: "OPEN" }, opts("a"));
  eq(r2.sweep.earlyOut, undefined, "present key: no early-out");
}
io.log("metaidx.js absent-key early-out OK");

// ==========================================================================
//  6. `Due:` normalizes to a ron60 DATE, so deadlines RANGE; free text hashes.
// ==========================================================================
{
  plant("a", "GET/GET-003.mkd", page("GET-003", { Sta: "OPEN", Due: "2026-08-10",
        Ask: "someone with spaces in the value" }), 60);
  const r = metaidx.find({ Due: { lo: "2026-08-01", hi: "2026-09-01" } }, opts("a"));
  eq(ids(r), "GET/GET-003.mkd", "Due: in-range");
  eq(ids(metaidx.find({ Due: { lo: "2026-09-01" } }, opts("a"))), "", "Due: out of range");
  eq(ids(metaidx.find({ Due: "2026-08-10" }, opts("a"))), "GET/GET-003.mkd", "Due: exact");
  const m = r.tickets[0].meta;
  ok(m.Due && m.Due.lit, "Due: stored as a LITERAL (it ranges)");
  ok(m.Ask && !m.Ask.lit, "free text with spaces past ron60 stores as a HASH");
  eq(ids(metaidx.find({ Ask: "someone with spaces in the value" }, opts("a"))),
     "GET/GET-003.mkd", "a hashed value still EQUALS");
  eq(ids(metaidx.find({ Ask: { lo: "a" } }, opts("a"))), "", "a hash never ranges");
}
io.log("metaidx.js ron60 literal vs hash OK");

// ==========================================================================
//  7. TWO WORKTREES ON ONE SHARD.  `path_hl` hashes the wt-qualified path and
//     the mark row is per-wt, so wt b's sweep neither marks nor tombstones
//     wt a's blocks — the failure a global mark would cause.
// ==========================================================================
{
  plant("b", "GET/GET-001.mkd", page("GET-001", { Sta: "OPEN", Who: "bob" }), 100);
  plant("b", "GET/GET-009.mkd", page("GET-009", { Sta: "OPEN", Who: "bob" }), 110);
  const rb = metaidx.find({ Sta: "OPEN" }, opts("b"));
  eq(rb.sweep.files, 2, "wt b: its own two tickets");
  eq(rb.sweep.lexed, 2, "wt b: cold, its own mark");
  ok(rb.sweep.cold, "wt b: wt a's mark did not mark wt b's files done");
  eq(rb.sweep.tombed, 0, "wt b: wt a's blocks are NOT tombstoned");
  eq(ids(rb), "GET/GET-001.mkd,GET/GET-009.mkd", "wt b: answers its own tree");

  const ra = metaidx.find({ Sta: "OPEN" }, opts("a"));
  eq(ids(ra), "GET/GET-003.mkd,PUT/PUT-007", "wt a: unharmed by wt b's sweep");
  eq(ra.sweep.tombed, 0, "wt a: wt b's blocks are not tombstoned either");
  eq(ids(metaidx.find({ Who: "bob" }, opts("a"))), "", "wt a: does not see wt b's rows");
  eq(ids(metaidx.find({ Who: "bob" }, opts("b"))),
     "GET/GET-001.mkd,GET/GET-009.mkd", "wt b: does");
  //  same rel path, DIFFERENT path_hl — the wt qualification
  ok(metaidx.pathHl(todoOf("a") + "/GET/GET-001.mkd") !==
     metaidx.pathHl(todoOf("b") + "/GET/GET-001.mkd"), "wt-qualified path_hl");
  ok(metaidx.wtCode(wtOf("a")) !== metaidx.wtCode(wtOf("b")), "distinct wt codes");
}
io.log("metaidx.js two worktrees, one shard OK");

// ==========================================================================
//  8. A CRASH MID-SWEEP.  The sweep seals (rows land in a run) and dies before
//     the mark row: the next sweep must RE-LEX those files, never skip them.
//     A mark advanced by an intermediate seal would silently lose the tail.
// ==========================================================================
{
  const NM = "c";
  for (let i = 1; i <= 6; i++)
    plant(NM, "CR/CR-00" + i + ".mkd", page("CR-00" + i, { Sta: "OPEN" }), 200 + i);
  //  crash after 3 of the 6 tickets, right after an intermediate seal
  let msg = "";
  try { metaidx.find({ Sta: "OPEN" }, opts(NM, { _crashAfter: 3 })); }
  catch (e) { msg = "" + e; }
  ok(msg.indexOf("injected sweep fault") >= 0, "crash: the sweep aborted (" + msg + ")");

  //  the rows the seal landed ARE in the lane, but the mark is not
  {
    const ix = metaidx.openIndex(SHARD);
    const mk = ix.get(metaidx.packKey(metaidx.MARK_PHL, metaidx.wtCode(wtOf(NM)),
                                      metaidx.KIND_MARK));
    eq(mk, undefined, "crash: the mark row was NOT written");
    let rows = 0;
    ix.prefix(metaidx.pathHl(todoOf(NM) + "/CR/CR-001.mkd") << 24n, 24,
              function () { rows++; });
    ok(rows > 0, "crash: the sealed rows survived the abort");
    ix.close();
  }
  //  so the next sweep re-lexes EVERY file, not just the tail
  const r = metaidx.find({ Sta: "OPEN" }, opts(NM));
  eq(r.sweep.mark, 0n, "crash: the next sweep still sees no mark");
  eq(r.sweep.lexed, 6, "crash: all six re-lex (a redundant read, never a skip)");
  eq(r.sweep.skipped, 0, "crash: nothing was marked done that was never lexed");
  eq(r.tickets.length, 6, "crash: the full list answers");
  //  and now it settles
  const r2 = metaidx.find({ Sta: "OPEN" }, opts(NM));
  eq(r2.sweep.lexed, 1, "crash: settled — only the max-mtime file re-lexes");
  eq(r2.sweep.skipped, 5, "crash: settled — the rest skip");
}
io.log("metaidx.js crash mid-sweep OK");

// ==========================================================================
//  9. BATCHING: > IDX_BATCH rows in one sweep still seal correctly (rows put
//     between two commits must fit ONE 4 KB memtable page).
// ==========================================================================
{
  const NM = "d";
  const N = 150;                                    // 150 * 2 pairs = 300 rows
  for (let i = 0; i < N; i++)
    plant(NM, "BT/BT-" + (1000 + i) + ".mkd",
          page("BT-" + (1000 + i), { Sta: i % 2 ? "OPEN" : "DONE", Who: "zed" }), 300 + i);
  const r = metaidx.find({ Sta: "OPEN", Who: "zed" }, opts(NM));
  eq(r.sweep.files, N, "batch: every planted ticket scanned");
  eq(r.sweep.lexed, N, "batch: cold fill");
  ok(r.sweep.put > metaidx.IDX_BATCH, "batch: more rows than one batch (" + r.sweep.put + ")");
  eq(r.tickets.length, N / 2, "batch: half of them are OPEN");
  const r2 = metaidx.find({ Sta: "OPEN", Who: "zed" }, opts(NM));
  eq(r2.sweep.put, 0, "batch: warm re-run writes nothing");
  eq(r2.tickets.length, N / 2, "batch: and answers the same");
}
io.log("metaidx.js batching OK");

// ==========================================================================
// 9b. A PATH-HASH COLLISION.  40-bit hashlets collide at ~0.45 expected pairs
//     per 1M tickets, so one cannot be PLANTED with real sha — the golden
//     forces it through the `_hash` override.  The sweep holds the complete
//     path list, so the collision is DETECTED: both paths leave the index and
//     are read directly, and the answer stays complete.
// ==========================================================================
{
  const NM = "e";
  const T1 = plant(NM, "CO/CO-001.mkd", page("CO-001", { Sta: "OPEN" }), 400);
  const T2 = plant(NM, "CO/CO-002.mkd", page("CO-002", { Sta: "OPEN" }), 401);
  const T3 = plant(NM, "CO/CO-003.mkd", page("CO-003", { Sta: "DONE" }), 402);
  const clean = metaidx.pathHl;
  const collide = function (abs) { return abs === T2 ? clean(T1) : clean(abs); };

  //  run A — no collision: all three index normally
  const a = metaidx.find({ Sta: null }, opts(NM));
  eq(a.sweep.collided, 0, "collision: run A is clean");
  eq(a.tickets.length, 3, "collision: run A lists all three");

  //  run B — CO-001 and CO-002 now share one path_hl
  const b = metaidx.find({ Sta: "OPEN" }, opts(NM, { _hash: collide }));
  eq(b.sweep.collided, 2, "collision: both colliding paths detected");
  ok(b.sweep.tombed >= 1, "collision: the shared block was dropped from the index");
  eq(ids(b), "CO/CO-001.mkd,CO/CO-002.mkd", "collision: both still answer (read directly)");
  eq(ids(metaidx.find({ Sta: "DONE" }, opts(NM, { _hash: collide }))),
     "CO/CO-003.mkd", "collision: the uncollided ticket answers from the index");

  //  run C — still detected, still complete, and no ghost row is resurrected
  const c = metaidx.find({ Sta: "OPEN" }, opts(NM, { _hash: collide }));
  eq(c.sweep.collided, 2, "collision: still detected");
  eq(c.sweep.tombed, 0, "collision: the drop is not repeated");
  eq(ids(c), "CO/CO-001.mkd,CO/CO-002.mkd", "collision: answer stays complete");
}
io.log("metaidx.js path-hash collision OK");

// ==========================================================================
// 10. The packing surface itself: the wh128 field split, the verbatim 3-char
//     key code, and the reserved slots.
// ==========================================================================
{
  eq(metaidx.codeOf("Sta"), ron.decode("Sta"), "key_code is the key VERBATIM (ron60)");
  eq(metaidx.codeOf("STA"), null, "a mis-shaped key has no code");
  eq(metaidx.codeOf("Stat"), null, "a four-letter key has no code");
  ok(metaidx.codeOf("Sta") < (1n << 18n), "a verbatim code fits 18 bits");
  ok(metaidx.codeOf("Sta") !== metaidx.codeOf("Sts"), "codes are injective");
  ok(metaidx.CODE_HEAD > (1n << 18n), "the reserved header code is above them all");
  const k = metaidx.packKey(0x1234567890n, metaidx.codeOf("Who"), metaidx.KIND_BLOCK);
  eq(metaidx.keyPhl(k), 0x1234567890n, "key: path_hl round-trips");
  eq(metaidx.keyCode(k), metaidx.codeOf("Who"), "key: key_code round-trips");
  eq(metaidx.keyKind(k), metaidx.KIND_BLOCK, "key: kind round-trips");
  //  the mark sentinel sorts ABOVE every path block
  ok(metaidx.packKey(metaidx.MARK_PHL, 0n, metaidx.KIND_MARK) >
     metaidx.packKey(metaidx.MARK_PHL - 1n, metaidx.CODE_HEAD, metaidx.KIND_BLOCK),
     "the mark row is keyed above every path block");
  //  normalization is despaced + decased
  eq(metaidx.normalize("  OPEN "), "open", "normalize: despaced + decased");
  eq(metaidx.packValue("Sta", "OPEN"), metaidx.packValue("Sta", " open "),
     "normalize: the two spellings pack identically");
  eq(metaidx.valKind(metaidx.packValue("Sta", "OPEN")), metaidx.VK_LIT, "OPEN is a literal");
  eq(metaidx.valKind(metaidx.packValue("Ask", "a much longer free text value")),
     metaidx.VK_HASH, "long free text hashes");
  //  classification
  eq(JSON.stringify(metaidx.classify("GET/GET-001.mkd")),
     JSON.stringify({ id: "GET/GET-001.mkd", rel: "GET/GET-001.mkd", code: "GET-001" }),
     "classify: thin ticket");
  eq(metaidx.classify("GET/GET-001/README.mkd").id, "GET/GET-001", "classify: fat id = the DIR");
  eq(metaidx.classify("GET/GET-001/log.mkd"), null, "classify: an attachment is not a ticket");
  eq(metaidx.classify("GET/GET-001/sub/GET-002.mkd"), null, "classify: nothing nests");
  eq(metaidx.classify("GET/README.mkd"), null, "classify: a topic README is not a ticket");
}
io.log("metaidx.js packing OK");

// ==========================================================================
// 11. Plain-words refusals: no bare codes reach a user.
// ==========================================================================
{
  let m = "";
  try { metaidx.find({ Sta: "OPEN" }, { todo: todoOf("a"), wt: wtOf("a"),
                                        shard: FX + "/nope" }); }
  catch (e) { m = "" + e; }
  ok(m.indexOf("there is no store shard") >= 0, "missing shard: plain words (" + m + ")");
  m = "";
  try { metaidx.find({ status: "OPEN" }, opts("a")); } catch (e) { m = "" + e; }
  ok(m.indexOf("is not a meta key") >= 0, "bad query key: plain words (" + m + ")");
}
io.log("metaidx.js refusals OK");

io.log("metaidx.js OK");
