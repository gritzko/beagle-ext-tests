//  BE-039: pager cross-mount repro.  A pager `:put <sub-crossing> <rest…>` (multi
//  arg, paths crossing the mounted `vendor/sub`) must behave BYTE-IDENTICALLY to
//  the CLI form: a VERB word-call keeps EVERY arg RAW (no `//authority` merged
//  onto arg0); the nav context travels as CONTEXT through the driveSpell reentry
//  (opts2.context), and put/delete resolve each arg against the CORRECT tree.
//  PUT descends the mount per-arg (stageInSub) → both files staged in the sub.
//  DELETE descends too (SUBS-039/DELETE, like CLI) → rows in the SUB wtlog, NOT
//  the RED destructive mis-target that silently deleted the sub's own file.
"use strict";
if (typeof process !== "undefined" && process.argv) process.argv[1] = io.cwd() + "/jsrc/loop.js";
const SPELL = require("shared/spell.js");
const loop  = require("core/loop.js");
const bro   = require("views/bro/bro.js");

function isVerb(w) { return loop.isVerb(w); }

//  Drive one address-bar spell exactly as the pager does: compose (context + RAW
//  args) → build the call → hand it to bro.driveSpell WITH the tracked context.
//  Print each returned hunk's text (the put:/delete: rows the pager would show).
function drive(ctxUri, spell) {
  const c = SPELL.compose(ctxUri, "", spell, isVerb);
  const built = SPELL.buildSpell(c);
  io.log(">> " + spell + "\n");
  let hunks = [], err = "";
  try { hunks = bro.driveSpell(built, c.context) || []; } catch (e) { err = String(e); }
  let s = "";
  for (const h of hunks) if (h.text) s += utf8.Decode(h.text);
  //  Strip the volatile wall-clock date column BEFORE the `   | ` prefix — the
  //  golden_norm leading-date strip cannot reach a prefixed line (SUBS-039).
  for (let line of s.split("\n")) {
    if (!line.replace(/\s/g, "")) continue;
    line = line.replace(/^ *[0-9]{1,2}:[0-9]{2} +/, "T ");
    io.log("   | " + line + "\n");
  }
  if (err) io.log("   ERR: " + err + "\n");
}

//  The nav context a pager STARTS with (BRO-017 → navCwd fallback): `//<name>`,
//  i.e. `//cli` here.  navCwd's wt-naming is a SEPARATE concern (BRO-017/BE-037);
//  this case fixes the composer+reentry, so it feeds the context navCwd yields in a
//  clean project — `//` + the cwd dir name — and drives it through the SHARED composer.
const ctx = "//" + io.cwd().slice(io.cwd().lastIndexOf("/") + 1);
io.log("=== context " + ctx + "\n");
drive(ctx, "put vendor/sub/x/k.txt vendor/sub/x/l.txt");
drive(ctx, "delete vendor/sub/x/k.txt vendor/sub/x/l.txt");
