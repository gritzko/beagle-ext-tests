//  parentsha.js — print cur.tip's first-parent sha for a worktree (the
//  ref-set parity case needs a real sha to set a branch to).  Args: <wt>.
"use strict";
const here = process.argv[1].slice(0, process.argv[1].lastIndexOf("/"));
const base = here + "/../../../../be/lib";
const be = require(base + "/be.js");
const wtlog = require(base + "/wtlog.js");
const store = require(base + "/store.js");
const repo = be.find(process.argv[2]);
const log = wtlog.open(repo);
const cur = log.curTip();
const k = store.open(repo.storePath, repo.project);
const par = cur && cur.sha ? k.commitParents(cur.sha) : null;
const out = (par && par[0]) ? par[0] : "";
const bytes = utf8.Encode(out);
const b = io.buf(bytes.length + 8); b.feed(bytes); io.writeAll(1, b);
