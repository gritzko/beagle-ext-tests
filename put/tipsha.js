//  tipsha.js — print a branch's resolved tip sha for a worktree (the
//  `?<40hex>` set-cur parity case needs a real, resolvable sha to put).
//  Args: <wt> [branch].  Empty/absent branch → trunk (cur's own tip).
"use strict";
const be = require("../../core/discover.js");   // be/test/put -> be/
const store = require("../../shared/store.js");
const repo = be.find(process.argv[2]);
const branch = process.argv[3] || "";
const k = store.open(repo.storePath, repo.project);
const out = k.resolveRef(branch) || "";
const bytes = utf8.Encode(out);
const b = io.buf(bytes.length + 8); b.feed(bytes); io.writeAll(1, b);
