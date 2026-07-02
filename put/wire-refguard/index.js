//  GIT-016 test/put/wire-refguard — shared/relate.js resolveRef branch->refs/
//  heads/X (absolute-marker strip + empty-segment POSTREF guard) and put's
//  POST->PUT message map (verbs/put/put.js pushWire) turning POSTREF into PUTREF:.
"use strict";

const { eq, ok } = require("../../lib/assert.js");
const relate = require("../../../shared/relate.js");

//  --- resolveRef: the branch -> refs/heads/X rule ------------------------
eq(relate.resolveRef(""),        "refs/heads/main",    "empty branch -> main");
eq(relate.resolveRef("main"),    "refs/heads/main",    "main -> main");
eq(relate.resolveRef("dev"),     "refs/heads/dev",     "dev -> dev");
eq(relate.resolveRef("/project"), "refs/heads/project", "/project: absolute-marker stripped");

//  --- POSTREF guard: an empty ref segment / trailing slash is refused -----
function refThrow(branch) {
  try { relate.resolveRef(branch); return null; }
  catch (e) { return e; }
}
const eSlashTail = refThrow("dev/");
ok(eSlashTail && eSlashTail.code === "POSTREF", "dev/ -> POSTREF (trailing empty segment)");
const eDoubleSlash = refThrow("a//b");
ok(eDoubleSlash && eDoubleSlash.code === "POSTREF", "a//b -> POSTREF (empty middle segment)");

//  --- put's POST->PUT message map (put.js pushWire catch arm) -------------
//  put re-raises resolveRef's {code,msg} with the POST prefix mapped to PUT:
//  `e.msg.replace(/^POST/, "PUT")`.  The POSTREF: msg must become a PUTREF: str.
function putMapped(branch) {
  try { relate.resolveRef(branch); return null; }
  catch (e) { return (e && e.msg) ? e.msg.replace(/^POST/, "PUT") : e; }
}
const mapped = putMapped("a//b");
ok(typeof mapped === "string", "put map yields a string message");
ok(mapped.indexOf("PUTREF:") === 0, "POSTREF msg mapped to a PUTREF: string");
ok(mapped.indexOf("POST") === -1, "no residual POST prefix after the put map");

io.log("put/wire-refguard OK\n");
