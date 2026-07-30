//  JS-074: be/test/registry.js — core/registry.js must SURFACE a verb/view
//  module that EXISTS but throws at LOAD (syntax error / throwing top-level),
//  never mask it as an unresolved verb.  Before the fix both catch sites were
//  blind to the error KIND: build() recorded table[verb]=null and resolveVerb()
//  returned null, so a broken-but-present module decayed downstream into the
//  misleading "no handler for verb" / "no plain-args handler" refusal (the
//  2026-07-19 live hit: a cold get.js throw reported as a missing handler).
//  Only the jab loader's genuine "cannot find" not-found stays fall-through.
//  Hermetic: plants a fixture jsrc/ forest in TMP, drives build()+resolveVerb().
"use strict";

const { eq, ok } = require("./lib/assert.js");
//  Derive the be/ code dir from THIS script's path (cf. test/uri.js _req).
function _req(mod) {
  const self = (typeof process !== "undefined" && process.argv && process.argv[1]) || "";
  if (self) {
    const d = self.slice(0, self.lastIndexOf("/test/"));
    if (d && d !== self) { try { return require(d + "/" + mod); } catch (e) {} }
  }
  return require(mod);
}
const reg = _req("core/registry.js");

//  --- hermetic fixture forest under TMP ------------------------------------
const TMP = io.getenv("TMP") || "/tmp";
const fx = TMP + "/registry-" + Date.now() + "-" + (Math.random() * 1e9 | 0);
function mkdirp(p) {
  let acc = "";
  for (const s of p.split("/")) { if (s === "") { acc = ""; continue; } acc += "/" + s;
    try { io.mkdir(acc); } catch (e) {} }
}
function plant(rel, body) {
  const abs = fx + "/" + rel;
  mkdirp(abs.slice(0, abs.lastIndexOf("/")));
  const fd = io.open(abs, "c");
  const b = io.buf(body.length + 8); b.feed(utf8.Encode(body)); io.writeAll(fd, b); io.close(fd);
}
const GOOD = 'module.exports = function h(){ return 1; };\nmodule.exports.jab = "args";\n';
//  build() resolves BAREWORD "views/x/x.js" via jab's frozen jsrc-scan; a require
//  bound to fx/ pins that scan to fx/jsrc.  resolveVerb() climbs <startDir>/jsrc.
plant("_req.js", "module.exports = require;\n");
plant("jsrc/views/goodview/goodview.js", GOOD);
plant("jsrc/views/throwview/throwview.js", 'throw "VIEW-BOOM: throwview blew up at load";\n');
plant("jsrc/verbs/goodverb/goodverb.js", GOOD);
plant("jsrc/verbs/throwverb/throwverb.js", 'throw "VERB-BOOM: throwverb blew up at load";\n');
plant("jsrc/verbs/syntaxverb/syntaxverb.js", 'function (){ this is not valid js ===;\n');
plant("jsrc/verbs/badshape/badshape.js", "module.exports = 42;\n");   // loads, wrong shape

//  assert `fn` throws an error whose text contains `needle`.
function throwsMsg(fn, needle, label) {
  let threw = false, msg = "";
  try { fn(); } catch (e) { threw = true; msg = "" + ((e && e.message != null) ? e.message : e); }
  ok(threw, label + ": expected a throw containing '" + needle + "', got none");
  ok(msg.indexOf(needle) >= 0, label + ": throw text '" + msg + "' lacks '" + needle + "'");
}

const fxReq = require(fx + "/_req.js");   // pins the bareword jsrc-scan to fx/jsrc

//  --- build(): a load error PROPAGATES, a real not-found stays null ---------
//  A views/ module that throws surfaces its own error (no fall-through to verbs/).
throwsMsg(function () { reg.build(["throwview"], fxReq); }, "VIEW-BOOM", "build(throwview)");
//  A verbs/ module (absent in views/) that throws surfaces its error.
throwsMsg(function () { reg.build(["throwverb"], fxReq); }, "VERB-BOOM", "build(throwverb)");
//  A syntax error in a present verbs/ module surfaces the raw SyntaxError.
throwsMsg(function () { reg.build(["syntaxverb"], fxReq); }, "Function statements must have a name", "build(syntaxverb)");
//  Sanity: a good verb resolves to a plain-args handler.
{ const t = reg.build(["goodverb"], fxReq); ok(t.goodverb && t.goodverb.jab === "args", "build: goodverb resolves"); }
//  A genuinely absent name (not-found in BOTH trees) stays null — fall-through.
{ const t = reg.build(["reallyabsent"], fxReq); eq(t.reallyabsent, null, "build: absent verb -> null"); }

//  --- resolveVerb(): verbFile PROVED the file, so a throw is a LOAD error ---
//  A throwing module surfaces wrapped as `cannot load verb '<w>' (<file>): ...`.
throwsMsg(function () { reg.resolveVerb("throwverb", fx, require); }, "cannot load verb 'throwverb'", "resolveVerb(throwverb) wrap");
throwsMsg(function () { reg.resolveVerb("throwverb", fx, require); }, "VERB-BOOM", "resolveVerb(throwverb) cause");
//  A syntax error likewise surfaces (wrapped), never a silent null.
throwsMsg(function () { reg.resolveVerb("syntaxverb", fx, require); }, "cannot load verb 'syntaxverb'", "resolveVerb(syntaxverb)");
//  A module that LOADS but exports a bad shape is a LOUD authoring error, not
//  the phantom downstream "no plain-args handler" refusal.
throwsMsg(function () { reg.resolveVerb("badshape", fx, require); }, "no plain-args handler", "resolveVerb(badshape)");
//  Sanity: a good verb resolves; a genuinely absent verb is null (verbFile miss).
{ const c = reg.resolveVerb("goodverb", fx, require); ok(c && c.jab === "args", "resolveVerb: goodverb resolves"); }
eq(reg.resolveVerb("reallyabsent", fx, require), null, "resolveVerb: absent verb -> null");

io.log("registry.js: all assertions passed\n");
