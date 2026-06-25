//  JSQUE-002: repro+test for be/loop.js (resident dispatch loop) + the
//  core/registry.js verb->handler table + the handler contract.  Seeds a small
//  job ULog via core/job.js, runs the loop, and asserts: (a) 2+ verbs dispatch
//  to resident handlers, (b) a handler that returns {enqueue:[...]} fans out a
//  CHILD row consumed in the same loop (consume-while-append), (c) the dispatch
//  ORDER is the FIFO seed-then-fan-out order, (d) the CONVERTED trivial verb
//  `refs` runs as an exported handler (not a one-shot main();), and (e) a
//  handler THROW propagates to the top (never swallowed per-row).
//
//  Run from inside the JSQUE-002 worktree (env WT points at it; the worktree's
//  `be -> .` self-symlink makes the be-relative require find loop.js + core/*):
//    cd ~/todo/JSQUE-002 && WT=$PWD $JAB beagle/test/js/loop.js
"use strict";

const here = process.argv[1].slice(0, process.argv[1].lastIndexOf("/"));
const { eq, ok, throws } = require(here + "/lib/assert.js");

//  The CODE worktree (core/registry.js + be/loop.js live there, not the live
//  shard); default the pilot path.  Loaded be-relative so the worktree's
//  self-symlink resolves core/job.js etc. from there.
const WT = io.getenv("WT") || "/home/gritzko/todo/JSQUE-002";
const loop = require(WT + "/loop.js");

//  Hermetic scratch: a be/ shard holding the fake test handlers + a _req.js
//  that hands back its OWN be-relative require (so loop's registry.build
//  resolves bareword verbs against THIS shard).  Never a bare /tmp/.be.
const TMP = io.getenv("TMP") || "/tmp";
const dir = TMP + "/jsque002-" + Date.now() + "-" + (Math.random() * 1e9 | 0);
const shard = dir + "/be";
io.mkdir(dir); io.mkdir(shard);

//  A module-global record of dispatch (in the TEST, not in a handler — handlers
//  stay re-entrant).  Each fake handler appends "<verb>:<uri>" via a global.
function writeHandler(name, body) {
  const fd = io.open(shard + "/" + name + ".js", "c");
  const b = io.buf(body.length + 8); b.feed(utf8.Encode(body));
  io.writeAll(fd, b); io.close(fd);
}

//  _req.js: export this shard's be-relative require for opts.require.
writeHandler("_req", "module.exports = require;");

//  leaf handler `done`: records, no fan-out.
writeHandler("done",
  "module.exports = function (row, ctx) {\n" +
  "  globalThis.__seen.push('done:' + row.uri);\n" +
  "};\n");

//  fan-out handler `seed`: records, then enqueues ONE child `done` row.  Proves
//  consume-while-append — the child is appended at the tail and consumed THIS
//  loop, after the rest of the already-queued rows.
writeHandler("seed",
  "module.exports = function (row, ctx) {\n" +
  "  globalThis.__seen.push('seed:' + row.uri);\n" +
  "  return { enqueue: [{ verb: 'done', uri: 'child-of-' + row.uri }] };\n" +
  "};\n");

//  boom handler: throws — must propagate to the top, never be swallowed.
writeHandler("boom",
  "module.exports = function (row, ctx) { throw 'BOOM ' + row.uri; };\n");

//  refs re-export: the CONVERTED trivial verb from the worktree shard, proven
//  to run AS A HANDLER (a function export, no main(); tail) through the loop.
writeHandler("refs", "module.exports = require('" + WT + "/refs.js');");

const req = require(shard + "/_req.js");

//  --- (1) dispatch order + fan-out (consume-while-append) -----------------
//  Seed: seed(a), done(b).  The seed handler fans out done(child-of-a) at the
//  tail, so the FIFO order is: seed:a, done:b, THEN done:child-of-a.
{
  globalThis.__seen = [];
  const qp = dir + "/queue1";
  const r = loop.run({
    seedRows: [{ verb: "seed", uri: "a" }, { verb: "done", uri: "b" }],
    queuePath: qp,
    require: req,
  });
  eq(r.dispatched, 3, "dispatched 3 rows (2 seed + 1 fan-out child)");
  eq(r.order.join(","), "seed,done,done", "dispatch verb order (FIFO + fan-out)");
  eq(globalThis.__seen.join("|"), "seed:a|done:b|done:child-of-a",
     "consume-while-append: child row consumed after queued rows");
  //  Clean close unlinks the queue + its .done side-row.
  ok(io.stat === undefined || _absent(qp), "queue unlinked on clean close");
}

//  --- (2) the converted `refs` verb runs as a HANDLER ---------------------
//  refs is a leaf (no fan-out); it reports the worktree it is pointed at via
//  row.uri.  Dispatching it proves the main();-to-export conversion: a function
//  export the registry resolves and the loop calls, not a load-time side effect.
{
  globalThis.__seen = [];
  const qp = dir + "/queue2";
  const r = loop.run({
    seedRows: [{ verb: "refs", uri: WT }],
    queuePath: qp,
    require: req,
  });
  eq(r.dispatched, 1, "refs dispatched once as a handler");
  eq(r.order.join(","), "refs", "refs is the dispatched verb");
}

//  --- (3) a handler THROW propagates to the top (not swallowed per-row) ----
{
  globalThis.__seen = [];
  const qp = dir + "/queue3";
  throws(function () {
    loop.run({
      seedRows: [{ verb: "done", uri: "x" }, { verb: "boom", uri: "y" }],
      queuePath: qp,
      require: req,
    });
  }, "a handler throw propagates out of loop.run");
}

//  --- (4) an unknown verb with no handler is a hard error (no silent skip) --
{
  const qp = dir + "/queue4";
  throws(function () {
    loop.run({ seedRows: [{ verb: "nope", uri: "z" }], queuePath: qp, require: req });
  }, "unknown verb with no handler throws");
}

function _absent(p) { try { io.stat(p); return false; } catch (e) { return true; } }

io.log("loop.js: all assertions passed\n");
