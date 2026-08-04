//  TODO-006 r3 repro driver — the REAL path: ONE resident process that runs the
//  REAL `todo` verb through core/loop.js (exactly what the pager's driveSpell
//  does), with the shared/cache.js REV TREE live and todo.js keeping its
//  STRUCTURED per-row blocks (heads / file counts / ahbeh), each with its OWN
//  witness.  The row is RE-RENDERED from those numbers every time, so the
//  measures are about the WORK behind them, never about reused bytes:
//  the CFOLD-001 `JAB_STATS` object-read counter, a count of every io.open /
//  io.readdir under the TICKET TREE (a quiet board reads no ticket file and
//  lists no topic dir), the classifyMerge calls (which wt paid the FILE block),
//  and the emitted hunk BYTES + TOKS — rendering from cached numbers must give
//  the very bytes a cold render gives.
//  args: <project root> <jsrc dir> <jab>   (the jsrc the fixture's verbs load
//  from — the driver MUST share those module instances, so it requires through
//  the very same path, and hands loop.js that root as its process.argv[1]).
"use strict";

const ROOT = args[0], JSRC = args[1], JAB = args[2];
process.argv[1] = JSRC + "/main.js";
const loop  = require(JSRC + "/core/loop.js");
const cache = require(JSRC + "/shared/cache.js");
//  The object-read counter, read STRAIGHT off the module the verbs bump (never
//  a scraped log line) — one instance, so a miscount cannot masquerade as a win.
const stats = require(JSRC + "/shared/util/stats.js");
//  the tlv reparse the pager itself uses: bytes -> { text, toks } hunks.
const pager = require(JSRC + "/views/bro/pager.js");
//  THE expensive thing a cached FILE block skips: one classifyMerge per repo.
//  Which wt paid it is the whole point of the r3 split, so the wt is recorded.
const classify = require(JSRC + "/shared/classify.js");
let folds = [];
const oMerge = classify.classifyMerge;
classify.classifyMerge = function (b, w, r, o) { folds.push(b.wt); return oMerge(b, w, r, o); };
//  The row is rendered EVERY time (r3): its hidden `O` click spells are minted
//  again on a hit — a count that DROPS to zero would mean a second renderer.
const spelllib = require(JSRC + "/shared/spell.js");
let mints = 0;
const oMint = spelllib.mintOspell;
spelllib.mintOspell = function (c, s) {
  if (/[A-Z]+-[0-9]+/.test(String(s))) mints++;
  return oMint(c, s);
};

const BOARD = ROOT + "/todo", WORK = ROOT + "/work";
const W1 = WORK + "/TIC-001", W2 = WORK + "/TIC-002";

let fails = 0;
function ok(cond, msg) {
  if (!cond) { fails++; io.log("FAIL " + msg); } else io.log("ok   " + msg);
}

//  EVERY touch of the ticket tree: a board-level standstill must skip
//  listTopics / listTopic / metaidx and read no ticket file at all.  The topic
//  DIR LISTINGS are counted apart — listing `todo/TIC` is exactly what reading
//  that topic's heads begins with, so a topic whose dir is never listed is a
//  topic whose heads were served off the cache.
let touch = 0, lists = [];
const oOpen = io.open, oReaddir = io.readdir;
io.open = function (p, m) {
  if (String(p).indexOf(BOARD) === 0) touch++;
  return oOpen(p, m);
};
io.readdir = function (p, o) {
  if (String(p).indexOf(BOARD) === 0) { touch++; lists.push(String(p)); }
  return o === undefined ? oReaddir(p) : oReaddir(p, o);
};
function listed(topic) {
  let n = 0;
  for (const p of lists) if (p === BOARD + "/" + topic) n++;
  return n;
}

//  Run the REAL verb in-process, capturing fd 1 (the driveSpell hook).
function spellRaw(argv) {
  const oWriteAll = io.writeAll, oWrite = io.write;
  const outs = [];
  io.writeAll = function (fd, b) {
    if (fd === 1) { outs.push(b.data().slice()); return; }
    if (fd === 2) return;
    return oWriteAll(fd, b);
  };
  io.write = function (fd, b) {
    if (fd === 1) { const d = b.data().slice(); outs.push(d); return d.length; }
    if (fd === 2) return;
    return oWrite(fd, b);
  };
  try { loop.cli(["jab", "loop.js"].concat(argv), { reentry: true }); }
  finally { io.writeAll = oWriteAll; io.write = oWrite; }
  let n = 0; for (const c of outs) n += c.length;
  const all = new Uint8Array(n); let o = 0;
  for (const c of outs) { all.set(c, o); o += c.length; }
  return all;
}

function tagOf(w) { return String.fromCharCode(65 + ((w >>> 27) & 0x1f)); }
function endOf(w) { return w & 0xffffff; }
//  the VISIBLE text of a hunk (the hidden O spans dropped), split per row.
function rowsOf(text, toks) {
  let vis = "", prev = 0;
  for (let i = 0; i < toks.length; i++) {
    const end = endOf(toks[i]);
    if (tagOf(toks[i]) !== "O") vis += utf8.Decode(text.slice(prev, end));
    prev = end;
  }
  const by = new Map();
  for (const l of vis.split("\n")) {
    const m = /([A-Z]+-[0-9]+)/.exec(l);
    if (m) by.set(m[1], l);
  }
  return { vis: vis, by: by };
}
function same(a, b) {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}
//  TODO-006 r3: the row's two FRAMES, split — `[ i …]` is the FILE block and
//  `[ ≡ …]` the COMMIT block, so a leg can say WHICH half moved.
function fileHalf(l) { const i = l.indexOf("[ i"); return i < 0 ? "" : l.slice(i, l.indexOf("]", i) + 1); }
function ciHalf(l) { const i = l.indexOf("[ ≡"); return i < 0 ? "" : l.slice(i, l.indexOf("]", i) + 1); }

let last = 0, lastTouch = 0, lastMint = 0;     // the counters are CUMULATIVE
function board(arg) {
  io.chdir(ROOT);
  lists = []; folds = [];
  const t0 = Date.now();
  const raw = spellRaw(arg ? ["todo", arg, "--tlv"] : ["todo", "--tlv"]);
  const ms = Date.now() - t0;
  const hs = pager.hunksFromTlv(raw);
  const text = hs.length ? hs[0].text : new Uint8Array(0);
  const toks = hs.length ? hs[0].toks : new Uint32Array(0);
  const d = { text: text, toks: toks, ms: ms, mints: mints - lastMint,
              work: stats.counts.obj - last, touch: touch - lastTouch,
              folds: folds.slice(), tic: listed("TIC"), bug: listed("BUG") };
  last = stats.counts.obj; lastTouch = touch; lastMint = mints;
  const r = rowsOf(text, toks);
  d.vis = r.vis; d.row = r.by;
  return d;
}
function write(p, s) {
  const u = utf8.Encode(s), b = io.buf(u.length + 8); b.feed(u);
  const fd = oOpen(p, "c"); io.writeAll(fd, b); io.close(fd);
}
//  Run a jab command in ANOTHER process, in `dir` — the cross-process shape.
function run(argv, dir) {
  const here = io.cwd();
  io.chdir(dir);
  try {
    const p = io.spawn(argv[0], argv);
    io.close(p.stdin);
    const b = io.ram(1 << 18);
    while (io.read(p.stdout, b) > 0) {}
    io.close(p.stdout);
    return io.reap(p.pid);
  } finally { io.chdir(here); }
}
//  every row of the board except the named ones, byte-compared line by line.
function othersSame(a, b, moved) {
  for (const k of a.row.keys()) {
    if (moved.indexOf(k) >= 0) continue;
    if (a.row.get(k) !== b.row.get(k)) return k;
  }
  return "";
}

ok(stats.ON, "JAB_STATS is on (the object-read counter is live)");

//  --- 1. with NO watcher there is no memo: every render recomputes ----------
const n1 = board(), n2 = board();
const nTIC = board("TIC");                     // …and the one-topic listing
ok(n1.text.length > 0 && n1.row.size === 5, "the board renders 5 ticket rows");
ok(n1.work > 0 && n2.work > 0,
   "watcher-less: every render pays the full work (" + n1.work + "," + n2.work + ")");
ok(n1.touch === n2.touch && n1.touch > 0,
   "watcher-less: every render re-reads the ticket tree (" + n1.touch + ")");
ok(n2.folds.length === 3 && n2.tic >= 1 && n2.bug >= 1,
   "watcher-less: all 3 worktrees re-classify and both topics re-list, every time");
const UNCACHED = n1.work, UNCACHED_TOUCH = n1.touch, UNCACHED_MINTS = n1.mints;
ok(same(n1.text, n2.text), "watcher-less renders are byte-identical");

ok(cache.start(ROOT) === true, "watcher started (revs exist at all)");

//  --- 2. hit vs miss: the SAME bytes off cached numbers, ~0 objects, no reads -
const a1 = board();
const a2 = board();
ok(a1.work >= UNCACHED, "the first WARM render still pays the full work (" + a1.work + ")");
//  THE bar (ticket §TODOs): a quiet board reads ~0 objects — only the tips
//  fingerprint's refs — classifies nothing and opens no ticket file.
ok(a2.work <= 8, "a HIT reads ~0 objects: " + a2.work + " (miss " + a1.work + ")");
ok(a2.folds.length === 0, "a HIT classifies NO worktree (the FILE blocks stand)");
ok(a2.touch === 0,
   "a HIT touches the ticket tree ZERO times (the board rev short-circuit): " + a2.touch);
ok(a1.touch >= UNCACHED_TOUCH, "…while the miss read it " + a1.touch + " times");
ok(same(a2.text, a1.text) && same(a1.text, n1.text),
   "hit, miss and uncached renders are BYTE-IDENTICAL");
ok(same(a2.toks, a1.toks), "…and so are the TOK spans");
//  r3 RULING: the tok array is rendered EVERY time, off the cached numbers —
//  a hit that stopped minting spells would mean a second, cached renderer.
ok(a2.mints === a1.mints && a2.mints === UNCACHED_MINTS,
   "a HIT re-renders every row through titleRow (" + a2.mints + " spells, as cold)");
const MISS_MS = a1.ms, HIT_MS = a2.ms;

//  --- 2b. a re-SHAPED listing renders off the very same cached blocks -------
//  `todo TIC` puts the SAME tickets at a different indent with no topic header.
//  r2's whole-line cache missed every row on that; the r3 blocks do not care.
const t1 = board("TIC");
ok(same(t1.text, nTIC.text),
   "`todo TIC` matches its UNCACHED bytes exactly, at its own indent");
ok(t1.folds.length === 0, "…and re-classified nothing: the shape is not a witness");
ok(t1.row.get("TIC-001").indexOf(" ") !== 0, "…un-indented, as the topic listing is");
ok(a2.row.get("TIC-001").indexOf("  ") === 0, "…while the board's own row keeps its indent");
const a2c = board();
ok(a2c.work <= 8 && a2c.touch === 0 && same(a2c.text, a1.text),
   "…and the board renders back identically, still warm (" + a2c.work + " objects)");

//  --- 3. a write under ONE wt re-runs THAT wt's FILE block only -------------
write(W1 + "/fresh.txt", "new\n");
const a3 = board();
ok(a3.row.get("TIC-001") !== a2c.row.get("TIC-001"), "the touched wt's row moved");
ok(a3.row.get("TIC-001").indexOf("+1") > 0, "…showing the new untracked file (+1)");
ok(a3.folds.length === 1 && a3.folds[0] === W1,
   "…and ONE worktree classified: " + a3.folds.join(",") + " (of 3)");
ok(othersSame(a2c, a3, ["TIC-001"]) === "",
   "every OTHER row is byte-identical (" + othersSame(a2c, a3, ["TIC-001"]) + ")");
ok(a3.touch === 0, "…and no ticket file was read: the board rev stood still");
ok(a3.work > a2c.work && a3.work < a1.work,
   "one row's worth of work, not the board's (" + a3.work + " of " + a1.work + ")");
const a4 = board();
ok(a4.work <= 8 && a4.folds.length === 0 && same(a4.text, a3.text),
   "…and the new counts re-warm, identically");

//  --- 4. one TICKET edit re-reads THAT topic's heads only ------------------
write(BOARD + "/BUG/BUG-001.mkd",
      "#   BUG-001: a bug that owns a worktree, RETITLED\nNow: OPEN\nSev: MED\n\nbody\n");
const a5 = board();
ok(a5.touch > 0, "a ticket edit re-runs the board path (" + a5.touch + " tree touches)");
ok(a5.row.get("BUG-001").indexOf("RETITLED") > 0, "…and the row shows the new title");
ok(a5.bug >= 1 && a5.tic === 0,
   "…re-listing the BUG topic (" + a5.bug + ", listTopic + the re-arm) and NOT the\n     TIC one (" + a5.tic + "): the untouched topic's heads came off the cache");
ok(a5.folds.length === 0, "…and classifying nothing: a head edit is not a file event");
ok(othersSame(a4, a5, ["BUG-001", "BUG-002"]) === "",
   "…while the untouched TIC topic's rows stay byte-identical");
const a6 = board();
ok(a6.touch === 0 && a6.work <= 8 && same(a6.text, a5.text),
   "…then the board goes quiet again (" + a6.work + " objects, " + a6.touch + " touches)");

//  --- 5. THE main-tree post: a moved upstream refreshes AHBEH ONLY ----------
//  The bare `post` (a PUSH) runs in ANOTHER PROCESS and rewrites the shared
//  `<shard>/refs` tip EVERY tracking wt's ahbeh reads.  No file under TIC-001 or
//  BUG-001 changes, so only the `tips` fingerprint can see it — and only their
//  COMMIT block may be recomputed: no classify, no ticket read, file half frozen.
ok(a6.row.get("TIC-001").indexOf("-1") < 0, "TIC-001 is level with the trunk before the push");
ok(run([JAB, "post"], W2).code === 0, "TIC-002 pushes its commit to the shared store");
const a7 = board();
ok(a7.row.get("TIC-001").indexOf("-1") > 0,
   "TIC-001 now reads BEHIND 1, with no fs event under it at all");
ok(a7.folds.indexOf(W1) < 0 && a7.folds.indexOf(WORK + "/BUG-001") < 0,
   "…and NEITHER untouched wt re-classified (" + a7.folds.join(",") + ")");
ok(a7.touch === 0, "…without reading one ticket file");
ok(fileHalf(a7.row.get("TIC-001")) === fileHalf(a6.row.get("TIC-001")) &&
   fileHalf(a7.row.get("BUG-001")) === fileHalf(a6.row.get("BUG-001")),
   "…the FILE frames are byte-for-byte what they were: only the ahbeh moved");
ok(ciHalf(a7.row.get("TIC-001")) !== ciHalf(a6.row.get("TIC-001")),
   "…and the COMMIT frame is the half that changed");
//  On THIS 3-wt fixture the ahbeh refresh IS most of a tiny board's reads, so
//  the honest bound here is "never more than a full board"; the pty leg and the
//  real journal board (88 wts) are where the fraction shows.
ok(a7.work <= a1.work,
   "…never more than a full board's reads (" + a7.work + " vs " + a1.work + ")");
const a8 = board();
ok(a8.work <= 8 && a8.folds.length === 0 && same(a8.text, a7.text),
   "…and the new tips re-warm, identically");

//  --- 6. the pager's R (bumpRoot) drops every block ------------------------
cache.bumpRoot();
const a9 = board();
ok(a9.folds.length === 3 && a9.touch > 0,
   "bumpRoot re-renders the whole board (" + a9.folds.length + " wts, " + a9.touch + " touches)");
ok(same(a9.text, a8.text), "…identically");

//  --- 7. with the watcher gone there is no memo again ----------------------
cache.stop();
const z1 = board(), z2 = board();
ok(z1.work >= UNCACHED - 8 && z2.work >= UNCACHED - 8,
   "watcher-less = every render recomputes (" + z1.work + "," + z2.work + ")");
ok(same(z1.text, z2.text) && same(z1.text, a9.text), "…and still renders identically");

//  the HIT vs MISS wall clock: the hit render IS the tips fingerprint plus the
//  full re-render off the cached numbers, so its ms IS that accepted price.
io.log("cost: miss=" + MISS_MS + "ms hit=" + HIT_MS + "ms (3 wts) " +
       "objects miss=" + a1.work + " hit=" + a2.work +
       " upstream-post=" + a7.work + " spells/render=" + a2.mints);

io.log(fails === 0 ? "PASS" : ("FAILED " + fails));
if (fails) throw "TODO006FAIL";
