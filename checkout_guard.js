//  BE-011: checkout.writeFile / writeSymlink LOCAL worktree-confinement guard.
//  These EXPORTED write leaves compose `join(wtRoot, rel)` + mkdir + open/symlink.
//  The confinement (safeRel) lived one layer up in materialise; a DIRECT caller of
//  the leaf could pass a `../` rel and write OUTSIDE the wt.  This is a DEFENSE-IN-
//  DEPTH guard, not a fixed live escape (materialise's own safeRel still gates the
//  sole live caller).  RED against pre-guard code (escape file written / no throw),
//  GREEN after the leaf-local safeRel refuses the `..` rel.  Hermetic: real fs only.
"use strict";

const { ok, eq } = require("./lib/assert.js");
const checkout = _req("shared/checkout.js");
function _req(mod) {
  const self = (typeof process !== "undefined" && process.argv && process.argv[1]) || "";
  if (self) {
    const d = self.slice(0, self.lastIndexOf("/test/"));
    if (d && d !== self) { try { return require(d + "/" + mod); } catch (e) {} }
  }
  return require(mod);
}

function threwWith(fn, needle, msg) {
  let threw = false, e = null;
  try { fn(); } catch (x) { threw = true; e = x; }
  ok(threw, msg + ": did not throw");
  const s = (typeof e === "string") ? e : ((e && e.message) || String(e));
  ok(s.indexOf(needle) >= 0, msg + ": thrown '" + s + "' lacks '" + needle + "'");
}
function absent(p) { try { io.lstat(p); return false; } catch (e) { return true; } }

const TMP = io.getenv("TMP") || "/tmp";
const base = TMP + "/js-ckguard-" + Date.now() + "-" + (Math.random() * 1e9 | 0);
const wt = base + "/wt";
io.mkdir(base); io.mkdir(wt);
const bytes = utf8.Encode("data\n");

//  --- escape: a `..` rel must be REFUSED, and NOTHING written above the wt ----
const pwn = base + "/pwned.txt";                    // where "../pwned.txt" resolves
threwWith(function () { checkout.writeFile(wt, "../pwned.txt", bytes); },
          "unsafe path", "writeFile('../pwned.txt')");
ok(absent(pwn), "writeFile escape wrote OUTSIDE the wt: " + pwn);

const evil = base + "/evil.lnk";
threwWith(function () { checkout.writeSymlink(wt, "../evil.lnk", "target"); },
          "unsafe path", "writeSymlink('../evil.lnk')");
ok(absent(evil), "writeSymlink escape linked OUTSIDE the wt: " + evil);

//  reserved-name segments (.git/.be) are refused too (safeRel policy).
threwWith(function () { checkout.writeFile(wt, ".git/hooks/x", bytes); },
          "unsafe path", "writeFile('.git/...')");

//  --- benign in-tree rels still succeed (no over-rejection) -------------------
checkout.writeFile(wt, "sub/ok.txt", bytes);
eq(absent(wt + "/sub/ok.txt"), false, "benign writeFile did not create the file");
checkout.writeSymlink(wt, "ok.lnk", "tgt");
eq(io.readlink(wt + "/ok.lnk"), "tgt", "benign writeSymlink target");

function w(s){const u=utf8.Encode(s+"\n");const b=io.buf(u.length+8);b.feed(u);io.write(1,b);}
w("PASS checkout_guard.js");
