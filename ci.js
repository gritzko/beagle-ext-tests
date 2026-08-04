//  test/ci.js — CI-004: shared/ci.js, the local build+test leg.
//  Leg A: the detection LADDER — one fixture dir per rung, first hit wins, and
//  the DISTINCT "nothing detected" result (null) for a bare dir.
//  Leg B: the background run — a detached `ci.sh` child, stdout AND stderr in
//  the log file, and the verdict row (green / red / in-flight) it feeds.
//  Leg C: STATUS-019 — the verdict is a MEMO keyed by the wt's rev, so the first
//  edit under the tree drops it; an untouched tree keeps it.
//  Leg E: the `ci` VIEW's own surface — ensure() forks ONCE and attaches after,
//  tail() reads the last 4 KB from a line start, footer() is render-only.
//  Leg G: TODO 11 — the REMEMBERED {wt: status} map beside the logs: cold, per
//  worktree, and what the board's three button colours read.
//  Leg F: shared/viewmark.js, the generic per-view marks bro honours.
//  Leg D: no watcher ⇒ no memo at all (rev tree ruling 3) — a run still reports
//  in-flight (live process state), but no verdict is ever shown as fresh.
"use strict";

const { eq, ok } = require("./lib/assert.js");
const CI = require("../shared/ci.js");
const cache = require("../shared/cache.js");

const TMP = io.getenv("TMP") || "/tmp";
const base = TMP + "/ci004-" + Date.now() + "-" + (Math.random() * 1e9 | 0);
io.mkdir(base);

function dir(name) { const p = base + "/" + name; io.mkdir(p); return p; }
function put(p, body, mode) {
  const fd = io.open(p, "c");
  const b = io.buf(body.length + 8); b.feed(utf8.Encode(body));
  io.writeAll(fd, b); io.close(fd);
  if (mode) io.chmod(p, mode);
}
function slurp(p) {
  let fd; try { fd = io.open(p, "r"); } catch (e) { return ""; }
  const b = io.buf(1 << 16);
  try { io.readAll(fd, b); } finally { io.close(fd); }
  return utf8.Decode(b.data().slice());
}
//  Spin until the child's verdict lands (or give up) — pol.sleep is the only
//  wait primitive; 100 x 50ms is far past any fixture's runtime.
function settled(wt) {
  for (let i = 0; i < 100; i++) {
    const r = CI.row(wt);
    if (r && r.state !== "run") return r;
    pol.sleep(50 * pol.MS);
  }
  return CI.row(wt);
}

//  --- Leg A: the ladder ------------------------------------------------------
const RUNGS = [
  ["ci.sh",          "ci.sh",              "./ci.sh"],
  ["scripts/ci.sh",  "scripts/ci.sh",      "./scripts/ci.sh"],
  ["cmake",          "CMakeLists.txt",     "cmake -S . -B build -G Ninja && ninja -C build && ctest --test-dir build -j16"],
  ["configure",      "configure",          "./configure && make && make test"],
  ["makefile",       "Makefile",           "make && make test"],
  ["cargo",          "Cargo.toml",         "cargo test"],
  ["go",             "go.mod",             "go test ./..."],
  ["npm",            "package.json",       "npm test"],
  ["pyproject",      "pyproject.toml",     "pytest"],
  ["setup",          "setup.py",           "pytest"],
];
for (const [name, probe, cmd] of RUNGS) {
  const wt = dir("rung-" + name.replace(/[^a-z0-9]/g, ""));
  if (probe.indexOf("/") > 0) io.mkdir(wt + "/" + probe.slice(0, probe.indexOf("/")));
  put(wt + "/" + probe, "x\n");
  const d = CI.detect(wt);
  ok(d, "ladder " + name + ": detected");
  eq(d.cmd, cmd, "ladder " + name + ": command line");
  eq(d.probe, probe, "ladder " + name + ": probe");
}

//  FIRST HIT wins: a tree carrying every marker still picks `./ci.sh`.
const all = dir("all");
io.mkdir(all + "/scripts");
for (const [, probe] of RUNGS)
  put(all + "/" + probe, "x\n");
eq(CI.detect(all).cmd, "./ci.sh", "first hit wins over every lower rung");

//  A CMakeLists tree with no ci.sh falls to the cmake rung (rung ORDER, not
//  just presence) — the shape the be/ tree itself has.
const cm = dir("cmake-only");
put(cm + "/CMakeLists.txt", "x\n"); put(cm + "/Makefile", "x\n");
eq(CI.detect(cm).probe, "CMakeLists.txt", "cmake outranks a sibling Makefile");

//  THE distinct "nothing detected" result.
eq(CI.detect(dir("bare")), null, "nothing detected in a bare dir");
eq(CI.detect(""), null, "nothing detected without a worktree");
//  A DIRECTORY named like a rung is not a rung (the probe is a regular file).
const dirprobe = dir("dirprobe"); io.mkdir(dirprobe + "/Makefile");
eq(CI.detect(dirprobe), null, "a dir named Makefile is not a rung");

//  --- Leg B: the background run ---------------------------------------------
//  The verdict is a rev-keyed memo, so from here on the rev tree must be LIVE:
//  with no watcher there is no memo and nothing below could ever land (leg D).
eq(cache.start(base), true, "the rev tree starts (verdicts are memos under it)");

//  green: exit 0, stdout AND stderr both captured in the log.
const green = dir("green");
put(green + "/ci.sh", "#!/bin/sh\necho OUTLINE\necho ERRLINE >&2\nexit 0\n", 0o755);
const g0 = CI.run(green);
ok(g0.started, "green: run started");
ok(g0.message.indexOf("./ci.sh") >= 0, "green: message names the command");
const gr = settled(green);
ok(gr, "green: a verdict row landed");
eq(gr.state, "green", "green: state");
eq(gr.code, 0, "green: exit code");
eq(gr.log, CI.paths(green).log, "green: row carries the log path");
eq(CI.badge(gr), "ci: ok", "green: badge");
const glog = slurp(gr.log);
ok(glog.indexOf("OUTLINE") >= 0, "green: stdout captured");
ok(glog.indexOf("ERRLINE") >= 0, "green: stderr captured");

//  red: a non-zero exit rides through to the row + the badge.
const red = dir("red");
put(red + "/ci.sh", "#!/bin/sh\necho boom\nexit 3\n", 0o755);
ok(CI.run(red).started, "red: run started");
const rr = settled(red);
eq(rr.state, "red", "red: state");
eq(rr.code, 3, "red: exit code");
ok(CI.badge(rr).indexOf("exit 3") >= 0, "red: badge names the exit code");
ok(CI.badge(rr).indexOf(rr.log) >= 0, "red: badge names the log");

//  in flight: a re-press while the child runs REPORTS, never respawns.
const slow = dir("slow");
put(slow + "/ci.sh", "#!/bin/sh\nsleep 2\nexit 0\n", 0o755);
ok(CI.run(slow).started, "slow: first run started");
const again = CI.run(slow);
eq(again.started, false, "slow: a re-press does not spawn a second child");
ok(again.message.indexOf("already running") >= 0, "slow: re-press says so in plain words");
eq(CI.row(slow).state, "run", "slow: the row reads in-flight");
eq(CI.badge(CI.row(slow)), "ci: running", "slow: in-flight badge");
const sr = settled(slow);
eq(sr.state, "green", "slow: settles green");
//  Once settled the SAME key runs again (the record is not wedged).
ok(CI.run(slow).started, "slow: a settled tree re-runs on the next press");

//  a tree with no rung starts nothing and says why.
const none = dir("norung");
const nr = CI.run(none);
eq(nr.started, false, "norung: nothing started");
ok(nr.message.indexOf("no build or test command") >= 0, "norung: plain-words refusal");
eq(CI.row(none), null, "norung: no verdict row");

//  a stale verdict never reads as the fresh run's: run() drops the marker first.
const restale = dir("restale");
put(restale + "/ci.sh", "#!/bin/sh\nexit 7\n", 0o755);
CI.run(restale); eq(settled(restale).code, 7, "restale: first verdict");
put(restale + "/ci.sh", "#!/bin/sh\nsleep 1\nexit 0\n", 0o755);
CI.run(restale);
eq(CI.row(restale).state, "run", "restale: the second run is in flight, not the old verdict");
eq(settled(restale).code, 0, "restale: the second verdict replaces the first");

//  --- Leg C: STATUS-019 — the verdict is a MEMO keyed by the wt's rev --------
const memo = dir("memo");
put(memo + "/ci.sh", "#!/bin/sh\nexit 0\n", 0o755);
CI.run(memo);
eq(settled(memo).state, "green", "memo: the verdict landed");
eq(CI.row(memo).state, "green", "memo: an untouched tree REPLAYS the verdict");
eq(CI.row(memo).state, "green", "memo: ... on every ask, the rev standing still");
//  THE staling leg: ONE edit under the wt moves its rev and the verdict is gone
//  — no drop call anywhere, the key simply stops matching.
put(memo + "/hello.txt", "edited\n");
eq(CI.row(memo), null, "memo: an edit under the wt STALES the verdict");
eq(CI.badge(CI.row(memo)), "", "memo: a staled verdict shows no badge");
//  ...and the marker still on disk does NOT resurrect it (it is consumed once).
eq(CI.row(memo), null, "memo: the staled verdict never comes back");

//  --- Leg E: ensure() — fork ONCE, attach after, replay a standing verdict ----
//  The view calls this on every render (the ~1s tick included), so the ONE thing
//  it must never do is fork a second build over a tree that already has one.
const ens = dir("ensure");
const cnt = base + "/ensure-count";        // OUTSIDE the wt: no rev churn
put(ens + "/ci.sh", "#!/bin/sh\necho started >>'" + cnt + "'\nsleep 1\necho tailline\nexit 0\n", 0o755);
const e0 = CI.ensure(ens);
eq(e0.cmd, "./ci.sh", "ensure: the fork names the command it started");
eq(CI.row(ens).state, "run", "ensure: the row reads in-flight");
eq(CI.ensure(ens).cmd, "./ci.sh", "ensure: a second ask ATTACHES to that run");
eq(settled(ens).code, 0, "ensure: the run settles green");
eq(CI.ensure(ens).message, "", "ensure: a FRESH verdict replays, nothing is forked");
eq(slurp(cnt), "started\n", "ensure: the command ran EXACTLY once");
eq(CI.ensure("").message, "ci: no worktree in this context", "ensure: plain-words refusal");

//  The TAIL is a reader over that same log file, and the FOOTER is render-only.
const et = CI.tail(ens);
ok(et && et.text.indexOf("tailline") >= 0, "tail: the log's own bytes");
eq(et.cut, 4096, "tail: capped at 4 KB");
eq(CI.footer(CI.row(ens)), "── PASS rc=0 ──", "footer: the PASS line carries rc=0");
eq(CI.footer({ state: "red", code: 3 }), "── FAIL rc=3 ──", "footer: FAIL names the rc");
eq(CI.footer({ state: "run" }), "⋯ running", "footer: mid-run");
eq(CI.footer(null), "", "footer: nothing fresh ⇒ no footer");
ok(slurp(CI.paths(ens).log).indexOf("PASS") < 0, "footer: never a byte in the log file");

//  A log LONGER than the cap tails its last 4 KB, cut at a line START.
const big = dir("bigtail");
put(big + "/ci.sh", "#!/bin/sh\ni=0\nwhile [ $i -lt 400 ]; do printf 'row %03d 0123456789012345\\n' $i; i=$((i+1)); done\nexit 0\n", 0o755);
CI.run(big); settled(big);
const bt = CI.tail(big);
ok(bt.text.length <= 4096, "tail: never more than the cap");
ok(bt.text.indexOf("row 399") >= 0, "tail: the END of the log is what shows");
ok(bt.text.indexOf("row 000") < 0, "tail: ...never its start");
eq(bt.text.slice(0, 3), "row", "tail: cut at a line START — no half first line");
eq(CI.tail(dir("notail")), null, "tail: no log ⇒ nothing to read");

//  --- Leg G: TODO 11 — the REMEMBERED verdict map (the board's colour) --------
//  Cold by construction: a plain file beside the logs, no watcher, no memo.  It
//  is what makes the ` ∞` button's three colours survive a fresh pager process.
eq(CI.status(dir("neverran")), null, "status: a tree that never ran is UNKNOWN");
eq(CI.status(green), "ok", "status: a green run is remembered as ok");
eq(CI.status(red), "fail", "status: a red run is remembered as fail");
eq(CI.status(""), null, "status: no worktree, no status");
//  PER-WT keys: one tree's verdict never bleeds into another's.
ok(CI.status(green) !== CI.status(red), "status: two wts, two independent rows");
//  It lives OUTSIDE every worktree — writing it can bump no wt's rev.
const spath = CI.statusPath();
ok(spath.indexOf(green) < 0 && spath.indexOf(red) < 0,
   "status: the map is stored beside the logs, never inside a tree");
//  ...and it is on DISK: the row a fresh process would read back, verbatim.
const sraw = slurp(spath);
ok(sraw.indexOf("ok\t" + green + "\n") >= 0, "status: the ok row is on disk");
ok(sraw.indexOf("fail\t" + red + "\n") >= 0, "status: ...and the fail row beside it");
//  A LATER run overwrites that tree's row and leaves the others alone.
put(green + "/ci.sh", "#!/bin/sh\nexit 5\n", 0o755);
CI.run(green); eq(settled(green).code, 5, "status: the tree re-runs red");
eq(CI.status(green), "fail", "status: ...and its remembered verdict flips");
eq(CI.status(red), "fail", "status: ...the other tree's row is untouched");

//  --- Leg F: shared/viewmark.js — the GENERIC per-view marks ------------------
const MARK = require("../shared/viewmark.js");
eq(MARK.take().tick, 0, "viewmark: an unmarked view takes nothing away");
MARK.tick(1000); MARK.end();
const vm = MARK.take();
eq(vm.tick, 1000, "viewmark: the refresh mark rides through");
eq(vm.end, true, "viewmark: ...and so does the end pin");
eq(MARK.take().tick, 0, "viewmark: taking DISARMS — one drive, one mark");
eq(MARK.take().end, false, "viewmark: ...both of them");
MARK.tick(0);
eq(MARK.take().tick, 0, "viewmark: a zero period is quiet, not a busy loop");

//  --- Leg D: no watcher ⇒ no memo (rev tree ruling 3) ------------------------
const nw = dir("nowatch");
put(nw + "/ci.sh", "#!/bin/sh\nsleep 1\nexit 0\n", 0o755);
cache.stop();
eq(cache.stats().live, false, "nowatch: the rev tree is off");
ok(CI.run(nw).started, "nowatch: the run still starts");
eq(CI.row(nw).state, "run", "nowatch: in-flight is LIVE state, not a memo");
const nwrc = CI.paths(nw).rc;
for (let i = 0; i < 200; i++) {
  let st; try { st = io.stat(nwrc); } catch (e) { st = null; }
  if (st && st.size > 0) break;
  pol.sleep(50 * pol.MS);
}
eq(CI.row(nw), null, "nowatch: no watcher ⇒ NO memo ⇒ nothing is shown as fresh");
eq(CI.badge(CI.row(nw)), "", "nowatch: ... and no badge");

io.rmdir(base, true);
console.log("DONE");
