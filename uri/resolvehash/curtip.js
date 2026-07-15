//  curtip.js — print a worktree's OWN current tip: the last get/post row in ITS
//  wtlog.  Args: <wt>.  This is [/wiki/URI] step 5.5's oracle, and it is NOT
//  test/put/tipsha.js: that one resolves the shard TRUNK (k.resolveRef), which
//  every tree sharing a shard reports identically.  A wt and a sub pinned at
//  different commits differ ONLY in their own wtlogs.
"use strict";
const discover = require("../../../core/discover.js");   // test/uri/resolvehash -> be/
const wtlog = require("../../../shared/wtlog.js");
const cur = wtlog.open(discover.treeAt(process.argv[2])).curTip();
const out = (cur && cur.sha) || "";
const bytes = utf8.Encode(out);
const b = io.buf(bytes.length + 8); b.feed(bytes); io.writeAll(1, b);
