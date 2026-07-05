//  test/js/bro/pager/driver.js — JAB-028 headless checks for the bro pager.
//  The interactive raw-mode loop is hard to drive under ctest, so this driver
//  unit-tests the PIECES that are pure functions of (hunks, keys, bytes):
//    1. hunksFromTlv: a captured --tlv 'H'-record stream reparses to hunks.
//    2. indexAll + paintRow: a hunk stream → display rows (banner + soft-wrap),
//       a row paints plain (verbatim) and colour (carries SGR).
//    3. statusURI/statusPos: the bottom-bar `<path>#L<n>` + TOP/%/BOT.
//    4. the Pager state machine: synthetic keys (j/k/space/g/G/:/Enter) drive
//       scroll + the address bar WITHOUT a tty (we never call run()).
//  argv[2] = path to view/bro/pager.js, argv[3] = path to view/bro.js (lib).
"use strict";
const pager = require(process.argv[2]);
const bro = require(process.argv[3]);

function w(s) {
  const b = utf8.Encode(s);
  const x = io.buf(b.length + 8); x.feed(b); io.writeAll(1, x);
}
function check(name, cond) { w((cond ? "ok   " : "FAIL ") + name + "\n"); }

//  --- 1. tlv round-trip: build a HUNK log, serialize, reparse via the pager ---
const src = utf8.Encode("alpha\nbeta\ngamma\n");
const log = abc.ram("HUNK", 4096);
log.feed("note.txt#L1", src, new Uint32Array(0), "cat", 0n);
const tlv = log.subarray(0, log.buffer.watermark | 0).slice();
const hunks = pager.hunksFromTlv(tlv);
check("tlv-roundtrip-count", hunks.length === 1);
check("tlv-roundtrip-uri", hunks[0].uri === "note.txt#L1");
check("tlv-roundtrip-text", utf8.Decode(hunks[0].text) === "alpha\nbeta\ngamma\n");

//  --- 1b. JAB-030 hunksFromLog: a LIVE HUNK ram log -> hunks (the universal-
//  pager edge path, no tlv serialize round-trip).  Two records, kept distinct.
if (typeof pager.hunksFromLog === "function") {
  const log2 = abc.ram("HUNK", 4096);
  log2.feed("a.txt#L1", utf8.Encode("one\ntwo\n"), new Uint32Array(0), "cat", 0n);
  log2.feed("b.txt#L1", utf8.Encode("three\n"), new Uint32Array(0), "grep", 0n);
  const lh = pager.hunksFromLog(log2);
  check("fromLog-count", lh.length === 2);
  check("fromLog-uri0", lh[0].uri === "a.txt#L1");
  check("fromLog-uri1", lh[1].uri === "b.txt#L1");
  check("fromLog-text0", utf8.Decode(lh[0].text) === "one\ntwo\n");
  check("fromLog-empty", pager.hunksFromLog(null).length === 0);
} else {
  check("fromLog-present", false);   // JAB-030 must export hunksFromLog
}

//  --- 2. indexAll: 1 banner + N body rows; soft-wrap at a narrow width --------
const rowsWide = pager.indexAll(hunks, 80);
check("indexAll-rows", rowsWide.length === 4);          // banner + 3 lines
check("indexAll-banner", rowsWide[0].banner === true);
//  A 3-col width wraps "alpha" (5 cp) into 2 rows → more body rows than lines.
const rowsNarrow = pager.indexAll(hunks, 3);
check("indexAll-softwrap", rowsNarrow.length > 4);

//  --- 2b. paintRow plain == verbatim; colour carries an SGR escape -----------
const body = rowsWide[1];                                // first body row
const plain = pager.paintRow(body.hunk, body.off, body.end, false);
check("paintRow-plain", plain === "alpha");
//  A syntax hunk paints; build one with toks so colour differs from plain.
const code = utf8.Encode('const x = 1;\n');
let toks; try { toks = tok.parse(code, "js"); } catch (e) { toks = new Uint32Array(0); }
const ch = { uri: "x.js#L1", verb: "hunk", text: code, toks: toks, kind: "file" };
const crows = pager.indexAll([ch], 80);
const cplain = pager.paintRow(ch, crows[1].off, crows[1].end, false);
const ccolor = pager.paintRow(ch, crows[1].off, crows[1].end, true);
check("paintRow-color-content", cplain === "const x = 1;");
let hasEsc = false;
for (let i = 0; i < ccolor.length; i++) if (ccolor.charCodeAt(i) === 27) { hasEsc = true; break; }
check("paintRow-color-sgr", toks.length === 0 || hasEsc);   // SGR iff there are toks

//  --- 3. statusURI / statusPos ----------------------------------------------
check("statusURI", bro.statusURI(hunks[0], 2) === "note.txt#L2");
check("statusPos-top", bro.statusPos(0, 100, 10) === "TOP");
check("statusPos-bot", bro.statusPos(90, 100, 10) === "BOT");
check("statusPos-all", bro.statusPos(0, 5, 10) === "ALL");

//  --- 4. Pager state machine (no tty: drive keys directly) -------------------
//  A fake fd whose tty.size we stub by monkey-patching the Pager's width source
//  is overkill; instead use the small page helper indirectly via a big hunk and
//  assert relative scroll moves.  We bypass render() (it needs tty.size) and
//  poke the keys + scroll directly, which is the state we care about.
const big = [];
let txt = "";
for (let i = 0; i < 200; i++) txt += "line " + i + "\n";
big.push({ uri: "big.txt#L1", verb: "hunk", text: utf8.Encode(txt), toks: new Uint32Array(0), kind: "file" });
//  A Pager with a stub fd; we never call run()/render(), only the key handlers,
//  so tty.size is not invoked except by _page() — stub it to a fixed size.
const realSize = tty.size;
tty.size = function () { return { rows: 24, cols: 80 }; };
const p = new pager.Pager(-1, { color: false, driveSpell: function (s) {
  //  the spell drive is mocked: a `mock:` spell yields a one-line hunk.
  if (s.indexOf("mock:") === 0)
    return [{ uri: "mock.txt#L1", verb: "hunk", text: utf8.Encode("mocked\n"),
              toks: new Uint32Array(0), kind: "file" }];
  return [];
} });
p.setHunks(big);
p.rows(80);                                              // index for width 80
check("scroll-start", p.view.scroll === 0);
p.key(0x6a); check("scroll-j", p.view.scroll === 1);     // j  down 1
p.key(0x6b); check("scroll-k", p.view.scroll === 0);     // k  up 1
p.key(0x20); check("scroll-space", p.view.scroll === 22); // space  page (24-2)
p.key(0x67); check("scroll-g", p.view.scroll === 0);     // g  top
p.key(0x47); check("scroll-G", p.view.scroll > 100);     // G  bottom (clamped later)
p.key(0x71); check("key-q", p.quit === true);            // q  quit

//  Address bar: ':' opens command mode, types a spell, Enter runs it (mocked).
const p2 = new pager.Pager(-1, { color: false, driveSpell: p._noop || function (s) {
  if (s.indexOf("mock:") === 0)
    return [{ uri: "mock.txt#L1", verb: "hunk", text: utf8.Encode("mocked\n"),
              toks: new Uint32Array(0), kind: "file" }];
  return [];
} });
p2.setHunks(big);
p2.key(0x3a); check("addr-open", p2.mode === "command");
for (const c of "mock:x") p2.key(c.charCodeAt(0));
check("addr-typed", p2.cmd === "mock:x");
p2.key(0x7f); check("addr-backspace", p2.cmd === "mock:");
p2.key(0x0d); check("addr-enter-mode", p2.mode === "scroll");
check("addr-enter-swap", p2.view.hunks.length === 1 && p2.view.hunks[0].uri === "mock.txt#L1");

//  Esc cancels the address bar without running.
const p3 = new pager.Pager(-1, { color: false });
p3.setHunks(big);
p3.key(0x3a); p3.key(0x1b);
check("addr-esc", p3.mode === "scroll" && p3.cmd === "");

//  --- 4b. bracketed paste into the address bar -------------------------------
//  A paste arrives via _feed as a byte burst ESC[200~ <text> ESC[201~.  The
//  payload must land in this.cmd VERBATIM; a pasted ESC/newline must NOT cancel
//  or submit the bar (the bug: the leading ESC dropped you out of the bar).
const BEG = [0x1b,0x5b,0x32,0x30,0x30,0x7e], END = [0x1b,0x5b,0x32,0x30,0x31,0x7e];
function pbytes() {                                       // build a byte burst
  const a = [];
  for (let k = 0; k < arguments.length; k++) { const x = arguments[k];
    if (typeof x === "string") for (let j = 0; j < x.length; j++) a.push(x.charCodeAt(j));
    else if (typeof x === "number") a.push(x);
    else for (let j = 0; j < x.length; j++) a.push(x[j]); }
  return Uint8Array.from(a);
}
const pp = new pager.Pager(-1, { color: false });
pp.setHunks(big); pp.key(0x3a);                           // ':' opens the bar
pp._feed(pbytes(BEG, "be://host/path?main", END));
check("paste-captured", pp.cmd === "be://host/path?main");
check("paste-stays-open", pp.mode === "command");

//  A pasted trailing NEWLINE is dropped, not submitted; the bar stays open.
const pp2 = new pager.Pager(-1, { color: false });
pp2.setHunks(big); pp2.key(0x3a);
pp2._feed(pbytes(BEG, "cat:foo", 0x0a, END));
check("paste-newline-nosubmit", pp2.cmd === "cat:foo" && pp2.mode === "command");

//  A paste SPLIT across two reads (end marker straddles): the carry/pend path
//  (return used; re-feed the tail) preserves the capture state.
const pp3 = new pager.Pager(-1, { color: false });
pp3.setHunks(big); pp3.key(0x3a);
const full = pbytes(BEG, "diff:x", END);
const used = pp3._feed(full.slice(0, full.length - 3));   // cut inside END marker
pp3._feed(full.slice(used));                              // re-feed the tail
check("paste-straddle", pp3.cmd === "diff:x" && pp3.mode === "command");

//  A lone Esc keypress must STILL cancel the bar (the paste probe never swallows
//  a solitary ESC into a hang).
const pp4 = new pager.Pager(-1, { color: false });
pp4.setHunks(big); pp4.key(0x3a);
pp4._feed(Uint8Array.from([0x1b]));
check("paste-lone-esc-cancels", pp4.mode === "scroll" && pp4.cmd === "");

//  --- 4c. URI-011: the word(context_uri,…rest) spell composer (a–g) ----------
//  _composeCall(spell) classifies each token against the tracked context URI: the
//  FIRST unquoted token shapes arg 0 — a bareword is a WT-RELATIVE path, `./x` is
//  context-relative, `//`/`?`/`#`/`scheme:` merge/reset as before; a leading `-`
//  = default context + raw REST, a quoted token stays a REST message.
function ccPager(verb, uri) {
  const p = new pager.Pager(-1, { color: false });
  p.setHunks(big); p.view.verb = verb; p.view.uri = uri;
  return p;
}
function cc(verb, uri, spell) { return ccPager(verb, uri)._composeCall(spell); }
function eqCall(name, got, verb, arg0, rest) {
  const ok = got && got.verb === verb && got.arg0 === arg0 &&
             JSON.stringify(got.rest) === JSON.stringify(rest);
  check(name, ok);
  if (!ok) w("   got " + JSON.stringify(got) + " want {verb:" + JSON.stringify(verb) +
             ", arg0:" + JSON.stringify(arg0) + ", rest:" + JSON.stringify(rest) + "}\n");
}
eqCall("cc-a-bareverb",   cc("cat","//HERE/src/x.c","status"),        "status","//HERE/src/x.c",[]);
eqCall("cc-b-pathedit",   cc("ls","//HERE/dir","./sub"),              "ls","//HERE/dir/sub",[]);
eqCall("cc-c-authmerge",  cc("status","//HERE/src","//OTHER"),        "status","//OTHER/src",[]);
eqCall("cc-c2-authreset", cc("status","//HERE/src","//OTHER/"),       "status","//OTHER/",[]);
eqCall("cc-d-refmerge",   cc("log","//HERE/x.c","?feat"),             "log","//HERE/x.c?feat",[]);
eqCall("cc-d2-reffrag",   cc("cat","//HERE/x.c","?feat#L20"),         "cat","//HERE/x.c?feat#L20",[]);
eqCall("cc-e-schemereset",cc("status","//HERE","post ssh://blah"),    "post","ssh://blah",[]);
eqCall("cc-f-message",    cc("ls","//HERE","post 'fix bug'"),         "post","//HERE",["fix bug"]);
eqCall("cc-g-urimsg",     cc("ls","//HERE","post //OTHER 'fix bug'"), "post","//OTHER",["fix bug"]);
eqCall("cc-put-multi",    cc("ls","//THERE/dir","put a.txt b/c.txt"), "put","//THERE/a.txt",["b/c.txt"]);
eqCall("cc-put-pathedit", cc("ls","//THERE/dir","put ./file"),        "put","//THERE/dir/file",[]);
//  URI-011b: the pager reads a bareword as a WT-RELATIVE URI part (fixes `:why
//  main.js` staying on the old view + `:put test`'s spurious arg 0); `-` = raw REST.
eqCall("cc-retarget-file",cc("why","view/bro.js","why main.js"),      "why","main.js",[]);
eqCall("cc-retarget-root",cc("status","/","put test"),               "put","test",[]);
eqCall("cc-bare-wtrel",   cc("cat","core/loop.js","cat theme.js"),   "cat","theme.js",[]);
eqCall("cc-dash-rest",    cc("post","//HERE","post - fix the bug"),  "post","//HERE",["fix","the","bug"]);

//  --- 4d. URI-011: the SHARED composer's CLI entry (composeArgv: verb known,
//  tokens pre-split, arg 0 = the cwd/`//WT` context).  Same classifier as the bar.
const SPELL = require("shared/spell.js");
//  URI-011b: with an isVerb probe a leading NON-verb bareword is a path, not a verb
//  (`verbs` in `ls //WHY-001` → `ls //WHY-001/verbs`, not a stray 2nd `ls` hunk).
const isVerbT = function (w) { return w === "ls" || w === "cat" || w === "why"; };
eqCall("cc-nonverb-path", SPELL.compose("//WHY-001","ls","verbs",isVerbT), "ls","//WHY-001/verbs",[]);
eqCall("cc-realverb-kept",SPELL.compose("//WHY-001","ls","cat x",isVerbT), "cat","//WHY-001/x",[]);
function ac(uri, verb, toks) { return SPELL.composeArgv(uri, verb, toks); }
eqCall("ca-cli-bareverb",  ac("//URI-011","status",[]),               "status","//URI-011",[]);
eqCall("ca-cli-message",   ac("//URI-011","post",["fix bug"]),        "post","//URI-011",["fix bug"]);
eqCall("ca-cli-authmerge", ac("//HERE/src","status",["//OTHER"]),     "status","//OTHER/src",[]);
eqCall("ca-cli-multipath", ac("//T/dir","put",["a.txt","b/c.txt"]),   "put","//T/dir",["a.txt","b/c.txt"]);

//  --- 4e. URI-011: put/delete bind rest UNDER arg 0 (the verb's file-vs-dir
//  oracle is mocked here: `dirs` names the directories).  Dir base drops + rest
//  joins under it; a FILE base is a target + rest joins its parent (equivalence).
function bindT(name, argv, dirs, want) {
  const got = SPELL.bindRest(argv, function (p) { return dirs.indexOf(p) >= 0; });
  const ok = JSON.stringify(got) === JSON.stringify(want);
  check(name, ok);
  if (!ok) w("   got " + JSON.stringify(got) + " want " + JSON.stringify(want) + "\n");
}
bindT("bind-dir-base",  ["dir","a.txt","b/c.txt"], ["dir"], ["dir/a.txt","dir/b/c.txt"]);
bindT("bind-file-base", ["dir/a.txt","b/c.txt"],   [],      ["dir/a.txt","dir/b/c.txt"]);
bindT("bind-single",    ["dir"],                   ["dir"], ["dir"]);
bindT("bind-ref-skip",  ["dir","a.txt","?feat"],   ["dir"], ["dir/a.txt","?feat"]);

//  --- 4f. URI-012: a followed/clicked RELATIVE click-target inherits the
//  CONTEXT authority.  A `//JS-072`-scoped status view bakes bare `diff:<path>`
//  (no authority); following/clicking it MUST drive `diff://JS-072/<path>` — not
//  the scope-less target that resolves against cwd → `no hunks`.  RED pre-fix.
function droveOnFollow(ctxUri, target) {
  let drove = null;
  const p = new pager.Pager(-1, { color: false, driveSpell: function (s) {
    drove = s;
    return [{ uri: s, verb: "hunk", text: utf8.Encode("x\n"), toks: new Uint32Array(0), kind: "file" }];
  } });
  p.setHunks(big); p.view.uri = ctxUri;                  // the tracked context URI
  p._runSpell(target);                                   // the follow/click choke point
  return drove;
}
check("follow-inherit-authority",
      droveOnFollow("status://JS-072", "diff:shared/patchscope.js") ===
        "diff://JS-072/shared/patchscope.js");
//  Idempotent: a target that ALREADY carries an authority passes through unchanged.
check("follow-authority-idempotent",
      droveOnFollow("status://JS-072", "diff://OTHER/a.c") === "diff://OTHER/a.c");
//  No context authority (launch/cwd tree) → the bare target is driven UNCHANGED.
check("follow-no-authority-noop",
      droveOnFollow("status:", "diff:a.c") === "diff:a.c");

//  --- 5. BRO-005: a LEFT-CLICK on a `U`-tagged token navigates to ITS URI -----
//  Build a hunk whose first row carries a hidden `U` click-target: the visible
//  token "open" is followed by a `U` token over the URI bytes "cat:foo.txt"
//  (invisible), then " more\n".  Mirrors C bro's row layout (HUNK.h: a path
//  column + a trailing 'U' tok over the hidden nav URI).
function packTok(tag, end) { return (((tag.charCodeAt(0) - 65) & 0x1f) << 27) | (end & 0xffffff); }
const utext = utf8.Encode("opencat:foo.txt more\n");      // "open"+"cat:foo.txt"+" more\n"
const utoks = Uint32Array.from([packTok("C", 4), packTok("U", 15), packTok("S", 21)]);
const uhunk = { uri: "host.txt#L1", verb: "hunk", text: utext, toks: utoks, kind: "file" };

//  _uriAt: the U-target URI for a byte offset.  A click on the visible token
//  before the U resolves to it (token-precise); BRO-005 follow-up — a click on
//  the REST of the same logical line (here " more") also resolves, since the
//  line carries exactly ONE U (the whole row is clickable, not just the token).
const pu = new pager.Pager(-1, { color: false });
check("uriAt-on-token", pu._uriAt(uhunk, 1) === "cat:foo.txt");
check("uriAt-line-tail", pu._uriAt(uhunk, 17) === "cat:foo.txt");
//  A line with MORE THAN ONE U stays token-precise (no line-fallback): clicking
//  word "a" → its own U, the space between → null (not the neighbour's link).
const mtext = utf8.Encode("aU1: bU2:\n");          // "a"+U"U1:"+" "+"b"+U"U2:"+"\n"
const mtoks = Uint32Array.from([packTok("F", 1), packTok("U", 4), packTok("S", 5),
                                packTok("F", 6), packTok("U", 9), packTok("S", 10)]);
const mhunk = { uri: "m.txt#L1", verb: "hunk", text: mtext, toks: mtoks, kind: "file" };
check("uriAt-multiU-word", pu._uriAt(mhunk, 0) === "U1:");
check("uriAt-multiU-space", pu._uriAt(mhunk, 4) === null);   // space, >1 U → no fallback

//  A full left-click through _mouse: row 2 (banner is row 1), col over "open"
//  → driveSpell("cat:foo.txt") → PUSH that view.  driveSpell is mocked to echo.
let clicked = null;
const pc = new pager.Pager(-1, { color: false, driveSpell: function (s) {
  clicked = s;
  return [{ uri: s, verb: "hunk", text: utf8.Encode("opened\n"), toks: new Uint32Array(0), kind: "file" }];
} });
pc.setHunks([uhunk]);
pc.rows(80);                                              // index for width 80
//  Banner is display-row 0 (screen row 1); the body row is screen row 2.
//  Left press (button 0) at col 2 (over "open"), row 2 → "\x1b[<0;2;2M".
pc._mouse("0;2;2", true);
check("uclick-drove", clicked === "cat:foo.txt");
check("uclick-pushed", pc.view.hunks.length === 1 && pc.view.hunks[0].uri === "cat:foo.txt");
check("uclick-stack", pc.stack.length === 1);
//  BRO-005 follow-up: clicking " more" — the line tail PAST the U — now also
//  navigates to the line's U-target (the whole single-U row is clickable).
let clicked2 = null;
const pc2 = new pager.Pager(-1, { color: false, driveSpell: function (s) { clicked2 = s; return [{ uri: s, verb: "hunk", text: utf8.Encode("x\n"), toks: new Uint32Array(0), kind: "file" }]; } });
pc2.setHunks([uhunk]); pc2.rows(80);
pc2._mouse("0;7;2", true);                                // col over " more" (line tail)
check("uclick-line-tail", clicked2 === "cat:foo.txt");
//  A row whose line carries NO U at all falls back to the row's hunk URI.
let clickedNoU = null;
const plainHk = { uri: "plain.txt#L1", verb: "hunk", text: utf8.Encode("just text\n"),
                  toks: Uint32Array.from([packTok("S", 10)]), kind: "file" };
const pc3 = new pager.Pager(-1, { color: false, driveSpell: function (s) { clickedNoU = s; return [{ uri: s, verb: "hunk", text: utf8.Encode("y\n"), toks: new Uint32Array(0), kind: "file" }]; } });
pc3.setHunks([plainHk]); pc3.rows(80);
pc3._mouse("0;3;2", true);                                // a plain row → hunk URI
check("uclick-fallback", clickedNoU === "plain.txt#L1");

//  --- 6. BRO-005: the mouse WHEEL scrolls (button 64 up / 65 down) ------------
const pw = new pager.Pager(-1, { color: false });
pw.setHunks(big); pw.rows(80);
pw.view.scroll = 10;
pw._mouse("64;5;5", true); check("wheel-up", pw.view.scroll < 10);     // wheel up
const before = pw.view.scroll;
pw._mouse("65;5;5", true); check("wheel-down", pw.view.scroll > before); // wheel down

//  --- 7. BRO-005: `m` toggles mouse tracking on/off --------------------------
const pm = new pager.Pager(-1, { color: false });
pm.setHunks(big);
check("mouse-default-on", pm.mouse === true);
pm.key(0x6d); check("mouse-off", pm.mouse === false);    // m → off
pm.key(0x6d); check("mouse-on", pm.mouse === true);      // m → on
//  With mouse OFF, a click does nothing (no navigate).
let clicked3 = null;
const pmo = new pager.Pager(-1, { color: false, driveSpell: function (s) { clicked3 = s; return []; } });
pmo.setHunks([uhunk]); pmo.rows(80); pmo.mouse = false;
pmo._mouse("0;2;2", true);
check("mouse-off-noclick", clicked3 === null);

//  --- 8. BRO-013: address-bar Tab path-completion from hunk U/F tokens --------
//  Build an `ls`-shaped hunk: each row is  <visible-name><nav-spell>\n  with an
//  F tok over the visible name, a P tok (dir only), a U tok over the hidden nav
//  spell `verb //auth/path`.  Completion walks these and fills this.cmd's last
//  word — a dir gets a trailing '/', a file none; many matches CYCLE on Tab.
function lsRow(parts, spans, off, name, navSpell, isDir) {
  const nameB = utf8.Encode(name), navB = utf8.Encode(navSpell), nlB = utf8.Encode("\n");
  parts.push(nameB); parts.push(navB); parts.push(nlB);
  const eName = off + nameB.length;
  spans.push(packTok("F", eName));
  if (isDir) spans.push(packTok("P", eName));            // F+P ⇒ dir
  spans.push(packTok("U", eName + navB.length));         // hidden nav spell
  spans.push(packTok("S", eName + navB.length + nlB.length));
  return nameB.length + navB.length + nlB.length;
}
function lsHunk(rows) {                                   // rows: [name, navSpell, isDir]
  const parts = [], spans = []; let off = 0;
  for (const r of rows) off += lsRow(parts, spans, off, r[0], r[1], r[2]);
  let n = 0; for (const p of parts) n += p.length;
  const text = new Uint8Array(n); let k = 0;
  for (const p of parts) { text.set(p, k); k += p.length; }
  return { uri: "ls //WHY-001", verb: "ls", text: text, toks: Uint32Array.from(spans), kind: "dir" };
}
const lh = lsHunk([
  ["verbs/",  "ls //WHY-001/verbs/",  true],
  ["version.js", "cat //WHY-001/version.js", false],
  ["view/",   "ls //WHY-001/view/",   true],
  ["readme.md", "cat //WHY-001/readme.md", false],
]);
//  Unique match: `re` → the sole `readme.md` (a FILE, no trailing slash).
const t1 = new pager.Pager(-1, { color: false });
t1.setHunks([lh]); t1.key(0x3a); t1.cmd = "re";
t1.key(0x09);
check("tab-unique-file", t1.cmd === "readme.md");
//  Dir completion appends a trailing '/'.
const t2 = new pager.Pager(-1, { color: false });
t2.setHunks([lh]); t2.key(0x3a); t2.cmd = "verb";
t2.key(0x09);
check("tab-unique-dir-slash", t2.cmd === "verbs/");
//  Shared prefix: `ve` matches verbs/ + version.js → EXTEND to the common prefix
//  `ver` first (both share it, no cycle yet).
const t3 = new pager.Pager(-1, { color: false });
t3.setHunks([lh]); t3.key(0x3a); t3.cmd = "ve";
t3.key(0x09);
check("tab-shared-prefix-extends", t3.cmd === "ver");
//  From the divergence point `ver`, Tab CYCLES the two candidates; a further Tab
//  advances, and after wrapping the cycle returns to the first candidate.
t3.key(0x09);
const first = t3.cmd;
t3.key(0x09);
const second = t3.cmd;
check("tab-cycle-advances", first !== second &&
      (first === "verbs/" || first === "version.js") &&
      (second === "verbs/" || second === "version.js"));
t3.key(0x09);                                            // wrap back to the first
check("tab-cycle-wraps", t3.cmd === first);
//  A non-Tab key RESETS cycle state; re-Tab starts fresh from the stem.
const t4 = new pager.Pager(-1, { color: false });
t4.setHunks([lh]); t4.key(0x3a); t4.cmd = "vi";
t4.key(0x09);
check("tab-only-word-completes", t4.cmd === "view/");
//  A leading verb word is KEPT — only the tail word completes.
const t5 = new pager.Pager(-1, { color: false });
t5.setHunks([lh]); t5.key(0x3a); t5.cmd = "cat re";
t5.key(0x09);
check("tab-keeps-verb-word", t5.cmd === "cat readme.md");

tty.size = realSize;                                     // restore the stub
w("DONE\n");
