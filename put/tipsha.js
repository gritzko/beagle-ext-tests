//  tipsha.js — print a branch's resolved tip sha for a worktree (the
//  `?<40hex>` set-cur parity case needs a real, resolvable sha to put).
//  Args: <wt> [branch].  Empty/absent branch → trunk (cur's own tip).
"use strict";
const here = process.argv[1].slice(0, process.argv[1].lastIndexOf("/"));
const base = here + "/../../../../be/lib";
const be = require(base + "/be.js");
const store = require(base + "/store.js");
const repo = be.find(process.argv[2]);
const branch = process.argv[3] || "";
const k = store.open(repo.storePath, repo.project);
const out = k.resolveRef(branch) || "";
const bytes = utf8.Encode(out);
const b = io.buf(bytes.length + 8); b.feed(bytes); io.writeAll(1, b);
