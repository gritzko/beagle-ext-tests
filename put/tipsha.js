//  tipsha.js — print a branch's resolved tip sha for a worktree (the
//  `?<40hex>` set-cur parity case needs a real, resolvable sha to put).
//  Args: <wt> [branch].  Empty/absent branch → trunk (cur's own tip).
"use strict";
const be = require("../../core/discover.js");   // be/test/put -> be/
const store = require("../../shared/store.js");
const wtlog = require("../../shared/wtlog.js");
const repo = be.treeAt(process.argv[2]);
const branch = process.argv[3] || "";
// DIS-076: a bare post never mints/moves a ref, so trunk ("") has no store
// ref to resolve — the WORKTREE's own cur tip is what "trunk" means here.
let out;
if (branch === "") out = wtlog.open(repo).curTip().sha || "";
else {
  const k = store.open(repo.storePath, repo.project);
  out = k.resolveRef(branch) || "";
}
const bytes = utf8.Encode(out);
const b = io.buf(bytes.length + 8); b.feed(bytes); io.writeAll(1, b);
