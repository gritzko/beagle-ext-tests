//  DIFF-021 test/diff/24-con-split-provenance/check.js — the captured
//  `jab diff <con-path> --tlv` stream must still carry TOK_PATCHED (bit 26)
//  toks when the emit SPLIT a dead weave atom (`//` -> two `/`): the old
//  token-text zip desynced there and dropped the whole record's provenance.
//    argv[2] = the captured --tlv bytes.
"use strict";

const pager = require("views/bro/pager.js");

function fail(m) { io.log("FAIL " + m + "\n"); throw "FAIL " + m; }

const tlvPath = process.argv[2];
const st = io.lstat(tlvPath);
const sz = Number(st.size);
const fd = io.open(tlvPath, "r");
const rb = io.buf(sz + 16);
io.readAll(fd, rb, sz);
io.close(fd);

const hunks = pager.hunksFromTlv(rb.data().slice());
if (hunks.length < 1) fail("diff --tlv fed no hunk");
let changed = 0, patched = 0;
for (const h of hunks)
  for (const w of h.toks) {
    if ((w >>> 24) & 3) changed++;
    if ((w >>> 26) & 1) patched++;
  }
io.log("changed " + changed + " patched " + patched + "\n");
if (!changed) fail("con diff carries no changed toks at all");
if (!patched) fail("con diff lost every TOK_PATCHED (bit 26) tok — " +
                   "the provenance zip desynced on the split dead token");
io.log("test/diff/24-con-split-provenance OK\n");
