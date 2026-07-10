//  BE-036: repro — a pager word spell (`put *.c`, `delete src/*`) must expand its
//  glob ARG words shell-style before dispatch (the pager plays the shell), the
//  SAME wt-confined readdir walk Tab-completion uses ([BE-027]).  Today the literal
//  pattern reaches the verb as a filename (FILENONE/bogus row).  This drives the
//  Pager internals directly (fd -1, no tty), like test/bro/navescape/navescape.js:
//  `_applySpell` end-to-end (expansion + failglob dispatch) and the `_glob` helper
//  (shape / dotfiles / wt-confinement).  RED before the expansion lands, GREEN after.
"use strict";

//  Derive the be/ code dir from THIS script's path (cf. navescape.js _req).
function _req(mod) {
  const self = (typeof process !== "undefined" && process.argv && process.argv[1]) || "";
  const d = self.slice(0, self.lastIndexOf("/test/"));
  if (d && d !== self) { try { return require(d + "/" + mod); } catch (e) {} }
  return require(mod);
}
const pager = _req("views/bro/pager.js");

function fail(m) { io.log("FAIL " + m + "\n"); throw "FAIL " + m; }
function ok(v, m) { if (!v) fail(m); }
function eqJson(a, b) { return JSON.stringify(a) === JSON.stringify(b); }

//  --- hermetic fixture: root/{wt, OUTSIDE}; wt holds .c/.h files, a dotfile, a
//  subdir, and OUTSIDE is a SIBLING above the wt (confinement negative control). --
const TMP = io.getenv("TMP") || "/tmp";
const root = TMP + "/be036-" + io.getpid() + "-" + (Math.random() * 1e9 | 0);
const wt = root + "/wt";
function touch(p) { const fd = io.open(p, "c"); io.close(fd); }
io.mkdir(root); io.mkdir(wt);
touch(wt + "/a.c"); touch(wt + "/b.c"); touch(wt + "/main.h"); touch(wt + "/.hidden.c");
io.mkdir(wt + "/src"); touch(wt + "/src/x.c"); touch(wt + "/src/y.c");
io.mkdir(root + "/OUTSIDE"); touch(root + "/OUTSIDE/secret.c");

//  A Pager over the fixture wt; _verbUri is stubbed to a (verb, view-path) pair,
//  as navescape.js does — so no real hunk stream / tty is needed.
function mkPager(viewPath) {
  const p = new pager.Pager(-1, { color: false, be: { wt_root: wt, cwd: wt } });
  p._verbUri = function () { return { verb: "put", uri: viewPath }; };
  return p;
}
//  A pager that RECORDS the spell handed to driveSpell (dispatch capture).
function drivePager(viewPath) {
  const p = mkPager(viewPath);
  p._log = [];
  p.driveSpell = function (s) {
    p._log.push(s);
    return [{ uri: "x", verb: "hunk", text: new Uint8Array(0), toks: new Uint32Array(0) }];
  };
  return p;
}

//  --- (1) END-TO-END: `put *.c` expands; no literal glob reaches the verb --------
const p1 = drivePager("");
p1._applySpell("put *.c");
ok(p1._log.length === 1, "put *.c dispatches once: " + JSON.stringify(p1._log));
const s1 = p1._log[0] || "";
ok(s1.indexOf("*") < 0, "put *.c EXPANDS — no literal glob reaches the verb: " + s1);
ok(s1.indexOf("a.c") >= 0 && s1.indexOf("b.c") >= 0, "both .c files present: " + s1);
ok(s1.indexOf(".hidden") < 0, "dotfile NOT matched by *.c: " + s1);

//  --- (2) FAILGLOB: a zero-match glob is NOT dispatched, shows a message ---------
const p2 = drivePager("");
p2._applySpell("put *.nomatch");
ok(p2._log.length === 0, "failglob: zero-match glob NOT dispatched: " + JSON.stringify(p2._log));
ok(p2.message && p2.message.length > 0, "failglob shows an addr-bar message: " + p2.message);

//  --- (3) HELPER _glob: shape (bare wt-rel vs ./ view-rel), sort, dotfiles -------
const g = mkPager("");
ok(eqJson(g._glob("*.c"), ["a.c", "b.c"]),
   "bare *.c → sorted wt-relative: " + JSON.stringify(g._glob("*.c")));
ok(eqJson(g._glob("src/*.c"), ["src/x.c", "src/y.c"]),
   "src/*.c → bare wt-relative subdir: " + JSON.stringify(g._glob("src/*.c")));
ok(eqJson(mkPager("src")._glob("./*.c"), ["./x.c", "./y.c"]),
   "./*.c from the src view → view-relative ./x words: " + JSON.stringify(mkPager("src")._glob("./*.c")));
ok(g._glob("*.nomatch").length === 0, "no-match glob → []");
//  io.readdir hides dotfiles (like Tab-completion); a bare `*` never matches one.
const star = g._glob("*");
ok(star.indexOf(".hidden.c") < 0, "a bare `*` skips dotfiles (shell convention): " + JSON.stringify(star));
ok(star.indexOf("a.c") >= 0 && star.indexOf("src") >= 0, "`*` matches files AND dirs: " + JSON.stringify(star));
ok(g._glob("main.?").indexOf("main.h") >= 0, "`?` matches one char: " + JSON.stringify(g._glob("main.?")));
ok(eqJson(g._glob("[ab].c"), ["a.c", "b.c"]), "[ab] class: " + JSON.stringify(g._glob("[ab].c")));

//  --- (4) CONFINEMENT: a `../` glob cannot reach the sibling above the wt --------
ok(g._glob("../*").length === 0, "../* from wt root escapes nothing (NAVESCAPE → no match)");
ok(!g._glob("../OUTSIDE/*.c").some(function (s) { return s.indexOf("secret") >= 0; }),
   "../OUTSIDE/*.c cannot match the sibling above the wt: " + JSON.stringify(g._glob("../OUTSIDE/*.c")));

//  --- cleanup ------------------------------------------------------------------
io.unlink(wt + "/a.c"); io.unlink(wt + "/b.c"); io.unlink(wt + "/main.h");
io.unlink(wt + "/.hidden.c"); io.unlink(wt + "/src/x.c"); io.unlink(wt + "/src/y.c");
io.rmdir(wt + "/src");
io.unlink(root + "/OUTSIDE/secret.c"); io.rmdir(root + "/OUTSIDE");
io.rmdir(wt); io.rmdir(root);

io.log("PASS be-js-bro-glob (BE-036: word-spell glob expansion, failglob, wt-confined)\n");
