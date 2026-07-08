//  BE-011: submount.mount LOCAL worktree-confinement guard.  mount() composes
//  `subWt = join(wt, subpath)` and mkdirs/checks-out there; today its sole caller
//  (recurse.js) passes a store-guarded gitlink path, so this is DEFENSE-IN-DEPTH,
//  not a fixed live escape.  A leaf-local safeRel(subpath) refuses a `..`/reserved
//  subpath at mount entry — BEFORE any fetch/mkdir.  RED against pre-guard code
//  (no NAVESCAPE: the `..` path falls through to the pin/fetch handling), GREEN
//  after.  Positive control: a legit subpath is NOT NAVESCAPE-blocked (it falls
//  through to the pin check).  Hermetic: pin="" short-circuits before any wire.
"use strict";

const { ok } = require("./lib/assert.js");
const submount = _req("shared/submount.js");
function _req(mod) {
  const self = (typeof process !== "undefined" && process.argv && process.argv[1]) || "";
  if (self) {
    const d = self.slice(0, self.lastIndexOf("/test/"));
    if (d && d !== self) { try { return require(d + "/" + mod); } catch (e) {} }
  }
  return require(mod);
}

//  Capture the thrown value and assert it does / does not carry `needle`.
function thrown(fn) {
  let threw = false, e = null;
  try { fn(); } catch (x) { threw = true; e = x; }
  return { threw: threw, s: (typeof e === "string") ? e : ((e && e.message) || String(e)) };
}

const wt = "/nonexistent/wt";   // never reached: pin="" refuses before wt use.
function mountSub(subpath) {
  return function () {
    submount.mount({ wt: wt, beDir: "/nonexistent/be", subpath: subpath,
                     pin: "", source: null });
  };
}

//  --- escape subpaths: refused with NAVESCAPE (confinement), before pin/fetch --
for (const bad of ["../outside", "../../etc", "a/../../b", ".git/x", ".be"]) {
  const r = thrown(mountSub(bad));
  ok(r.threw, "mount('" + bad + "') did not throw");
  ok(r.s.indexOf("NAVESCAPE") >= 0,
     "mount('" + bad + "') not NAVESCAPE-refused: '" + r.s + "'");
}

//  --- positive control: a legit subpath passes the guard (NOT NAVESCAPE); it
//  falls through to the pin check and throws the ordinary "no ... gitlink pin".
const good = thrown(mountSub("vendor/sub"));
ok(good.threw, "mount('vendor/sub') should still throw on empty pin");
ok(good.s.indexOf("NAVESCAPE") < 0,
   "mount('vendor/sub') was wrongly NAVESCAPE-blocked: '" + good.s + "'");
ok(good.s.indexOf("gitlink pin") >= 0,
   "mount('vendor/sub') did not reach the pin check: '" + good.s + "'");

function w(s){const u=utf8.Encode(s+"\n");const b=io.buf(u.length+8);b.feed(u);io.write(1,b);}
w("PASS submount_guard.js");
