//  JS-100: be/test/wirepush.js — the git-receive-pack PUSH child must be
//  closed+reaped on EVERY exit, including a post-FF-gate throw.  Two RED-first
//  repros over a REAL harmless child (/bin/cat: real stdin+stdout fds + pid):
//    1. wire.pushSession — force the advert drain to throw (pkt.Reader), assert
//       wfd/rfd closed + pid reaped (no leaked fd, no zombie).
//    2. post.pushRemote — force wire.buildPushPack to throw AFTER the FF gate,
//       assert the live session's child is cleaned up (session.close ran).
//  Hermetic: no network — io.spawn is redirected to /bin/cat; the leak signal
//  is per-child: the wfd/rfd numbers vanish from /proc/self/fd and /proc/<pid>
//  disappears (reaped).  Case 1 also cross-checks the aggregate fd count.
"use strict";

const { eq, ok } = require("./lib/assert.js");
//  JS-100: require via jab's bare be/-scan (NOT a path-derived _req).  post.js's
//  transitive `../view/render.js` only resolves on the be-scan path, so a
//  path-derived require would load a SECOND wire/relate instance the patched
//  post would not see.  Bare require keeps all four on ONE singleton.
const wire = require("shared/wire.js");
const pkt  = require("shared/pkt.js");
const relate = require("shared/relate.js");
const post = require("verbs/post/post.js");   // exports post fn; ._pushRemote hook

//  --- leak probes --------------------------------------------------------
function fdCount() { return io.readdir("/proc/self/fd").length; }
//  Read a small /proc file to a string (blocking fd, EOF at <read).
function readProc(path) {
  let fd; try { fd = io.open(path, "r"); } catch (e) { return null; }
  const parts = []; const s = new Uint8Array(4096);
  for (;;) { const n = io._read(fd, s); if (n <= 0) break; parts.push(s.slice(0, n)); }
  io.close(fd);
  let t = 0; for (const p of parts) t += p.length;
  const b = new Uint8Array(t); let o = 0; for (const p of parts) { b.set(p, o); o += p.length; }
  return utf8.Decode(b);
}
//  A leaked (not-reaped) child still has a /proc/<pid> entry (alive, blocked on
//  its still-open stdin, or defunct `Z`); a reaped one is gone.  This is the
//  deterministic close+reap signal — unlike an fd NUMBER, which gets recycled.
function pidLive(pid) { return readProc("/proc/" + pid + "/stat") !== null; }

//  Spawn a REAL harmless child so wfd/rfd/pid actually exist.
const realSpawn = io.spawn;
function spawnCat() { return realSpawn("/bin/cat", ["/bin/cat"]); }

//  === Case 1: pushSession advert-drain throw must not leak the child =====
(function () {
  const origReader = pkt.Reader;
  io.spawn = function () { return spawnCat(); };
  pkt.Reader = function () { throw "JS-100-drain-boom"; };   // force post-spawn throw
  const base = fdCount();
  let threw = false;
  try { wire.pushSession("file:///nonexistent?/proj"); }
  catch (e) { threw = true; }
  const after = fdCount();
  io.spawn = realSpawn; pkt.Reader = origReader;
  ok(threw, "pushSession propagates the advert-drain throw");
  //  KEY ASSERT: fd count back to baseline (wfd+rfd closed) — RED before fix.
  eq(after, base, "pushSession: no leaked fd (fd " + after + " vs base " + base + ")");
})();

//  === Case 2: pushRemote post-FF-gate throw must session.close() =========
//  Drive the REAL pushRemote.  wire.pushSession -> a real-child-backed session
//  whose close/send reap exactly like the production reaper; relate -> a
//  passing FF verdict; wire.buildPushPack -> throw AFTER the gate.  If
//  pushRemote skips session.close on that throw, the /bin/cat child leaks:
//  its wfd/rfd stay open and /proc/<pid> lingers (unreaped) — RED before fix.
(function () {
  const child = spawnCat();
  const wfd = child.stdin, rfd = child.stdout, pid = child.pid;
  let done = false;
  function reap() {                 // mirror wire.js pushSession reaper order
    try { io.close(rfd); } catch (e) {}
    try { io.reap(pid); } catch (e) {}
  }
  const session = {
    adv: { refs: [] },
    send: function () { done = true; io.close(wfd); reap(); },
    close: function () {            // idempotent done-guarded flush-close+reap
      if (done) return; done = true;
      try { io.writeAll(wfd, pkt.flushPkt()); } catch (e) {}
      try { io.close(wfd); } catch (e) {}
      reap();
    }
  };
  const origPS = wire.pushSession, origBPP = wire.buildPushPack,
        origRel = relate.relate;
  wire.pushSession = function () { return session; };
  wire.buildPushPack = function () { throw "JS-100-buildpack-boom"; };
  //  Passing FF verdict: a NEW ref (old="") so the FF gate is a no-op pass.
  relate.relate = function () {
    return { wireRef: "refs/heads/main", old: "", adv: { refs: [] },
             verdict: { eq: false, ff: true } };
  };
  const tip = "1234567890123456789012345678901234567890";
  const info = { storePath: "/tmp/js100", project: "proj" };
  const reader = { shard: {} };
  let threw = false;
  try {
    post._pushRemote(info, reader, {}, "file:///nonexistent?/proj", "", tip, true);
  } catch (e) { threw = true; }
  const closed = done, live = pidLive(pid);
  wire.pushSession = origPS; wire.buildPushPack = origBPP; relate.relate = origRel;
  session.close();               // belt+braces: never leak the probe child
  ok(threw, "pushRemote propagates the buildPushPack throw");
  //  KEY ASSERT: the throw ran session.close() → child reaped — RED before fix
  //  (unfixed pushRemote leaves `done` false and /proc/<pid> lingering).
  ok(closed, "pushRemote: buildPushPack throw ran session.close()");
  ok(!live, "pushRemote: receive-pack child (pid " + pid + ") reaped");
})();

io.log("PASS be-js-unit-wirepush");
