//  GIT-016 test/put/wire-refguard — shared/relate.js resolveRef branch->refs/
//  heads/X (absolute-marker strip + empty-segment guard).  RULING 2026-07-16:
//  the guard's refusal is verb-neutral plain text (one line, <=64 chars, no
//  C-style code prefix), re-raised verbatim by put's/head's wire paths — the
//  old POST->PUT `e.msg.replace(/^POST/, "PUT")` code map is gone.
"use strict";

const { eq, ok } = require("../../lib/assert.js");
const relate = require("../../../shared/relate.js");

//  --- resolveRef: the branch -> refs/heads/X rule ------------------------
eq(relate.resolveRef(""),        "refs/heads/main",    "empty branch -> main");
eq(relate.resolveRef("main"),    "refs/heads/main",    "main -> main");
eq(relate.resolveRef("dev"),     "refs/heads/dev",     "dev -> dev");
eq(relate.resolveRef("/project"), "refs/heads/project", "/project: absolute-marker stripped");

//  --- empty-ref-segment guard: a trailing/doubled slash is refused --------
function refThrow(branch) {
  try { relate.resolveRef(branch); return null; }
  catch (e) { return e; }
}
const eSlashTail = refThrow("dev/");
ok(typeof eSlashTail === "string" &&
   eSlashTail.indexOf("empty ref segment") >= 0,
   "dev/ -> refused, names the empty segment (trailing slash)");
ok(eSlashTail.indexOf("refs/heads/dev/") >= 0,
   "dev/ -> the refusal names the bad wire ref");
const eDoubleSlash = refThrow("a//b");
ok(typeof eDoubleSlash === "string" &&
   eDoubleSlash.indexOf("empty ref segment") >= 0,
   "a//b -> refused, names the empty segment (middle slash)");

//  --- RULING 2026-07-16 message shape: plain text, 1 line, <=64, no code --
ok(eSlashTail.length <= 64 && eSlashTail.indexOf("\n") < 0,
   "refusal is one line <= 64 chars");
ok(!/^[A-Z]+[A-Z0-9]*:/.test(eSlashTail), "no C-style code prefix");
ok(eSlashTail.indexOf("POST") < 0, "no residual POST code in the refusal");

io.log("put/wire-refguard OK\n");
