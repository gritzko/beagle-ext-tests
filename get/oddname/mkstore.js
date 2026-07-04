//  JS-075 test/get/oddname/mkstore.js — build a REAL source store whose tree
//  carries tracked names with `#` and `?` (which the CLI put/post layer cannot
//  stage), so the get fan-out + leaf can be exercised end-to-end.  Feeds a git
//  pack (blob/tree/commit) via git.pack + ingest.clone; prints the store dir.
"use strict";

const CODE = io.getenv("BECODE");
const store  = require(CODE + "/shared/store.js");
const ingest = require(CODE + "/shared/ingest.js");

const OUT = io.getenv("ODDSTORE");                     // destination store dir

function enc(s) { return utf8.Encode(s); }
function concat(a) { let n = 0; for (const x of a) n += x.length;
  const o = new Uint8Array(n); let p = 0; for (const x of a) { o.set(x, p); p += x.length; }
  return o; }
//  git object id = sha1("<type> <len>\0" + body).
function oid(type, body) { return sha1(concat([enc(type + " " + body.length + "\0"), body])); }
function hex(u8) { let s = ""; for (const b of u8) { const h = b.toString(16); s += h.length < 2 ? "0" + h : h; } return s; }
//  git tree entry: "<octmode> <name>\0" + 20 raw sha bytes.
function ent(mode, name, raw) { return concat([enc(mode + " " + name + "\0"), raw]); }

io.mkdir(OUT); io.mkdir(OUT + "/.be");

const bA = enc("HASHNAME\n"), bC = enc("QUESNAME\n"), bP = enc("PLAIN\n");
const sA = oid("blob", bA), sC = oid("blob", bC), sP = oid("blob", bP);
//  Tree entries MUST be byte-sorted by name: "a#b" < "c?d" < "plain.txt".
const tree = concat([ent("100644", "a#b", sA), ent("100644", "c?d", sC),
                      ent("100644", "plain.txt", sP)]);
const sT = oid("tree", tree);
const commit = enc("tree " + hex(sT) + "\nauthor x <x@x> 0 +0000\n" +
                   "committer x <x@x> 0 +0000\n\nc1\n");
const sC2 = oid("commit", commit);

const ta = new Uint8Array(1 << 16);
const pk = git.pack.over(ta);
pk.header();
pk.feed("blob", bA, -1, null); pk.feed("blob", bC, -1, null);
pk.feed("blob", bP, -1, null); pk.feed("tree", tree, -1, null);
pk.feed("commit", commit, -1, null);
pk.finish();
const wm = Number(pk.buffer.watermark);
const full = new Uint8Array(wm + 20);
full.set(ta.subarray(0, wm), 0); full.set(sha1(ta.subarray(0, wm)), wm);

ingest.clone(full, OUT + "/.be", "src", hex(sC2), "file:test");
//  Round-trip sanity: readTree must return the odd names byte-intact.
const k = store.open(OUT, "src");
const es = k.readTree(k.commitTree(hex(sC2)));
const got = es.map(function (e) { return e.name; }).join(",");
if (got !== "a#b,c?d,plain.txt") throw "mkstore: tree names corrupt: " + got;
io.log("OK\n");
