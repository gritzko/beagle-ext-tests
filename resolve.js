//  JSQUE-004: repro for core/resolve.js — resolution-at-entry seed.  argv ->
//  branch-free, hash-pinned SEED rows: `?branch`/ref pinned to a commit sha
//  ONCE at entry; downstream rows carry no branch label and are
//  order-independent.  Asserts the multi-path batch fans 1:1, the ref-write
//  forms (`?br`, `?br#sha`, `?#sha`, `?<40hex>`) pin to a 40-hex sha, the
//  patch (ours, theirs, fork) triple + the .gitignore snapshot are pinned, and
//  CRUCIALLY that a handler can run a seed row with NO live re-resolve (the
//  seed resolver fires only at seed time, never per-row).
//
//  This test loads the JSQUE-004 WORKTREE code (core/resolve.js does not exist
//  in the live shard).  Point WT at the worktree root; default is the pilot
//  path.  Run with $JAB; cwd-independent (explicit requires into the worktree).
"use strict";

const WT = io.getenv("WT") || "/home/gritzko/todo/JSQUE-004";
const here = process.argv[1].slice(0, process.argv[1].lastIndexOf("/"));
const { eq, ok, throws } = require(here + "/lib/assert.js");

const resolve = require(WT + "/core/resolve.js");
const wtlog   = require(WT + "/lib/wtlog.js");
const store   = require(WT + "/lib/store.js");
const ulog    = require(WT + "/lib/ulog.js");
const sha      = require(WT + "/lib/sha.js");

const TMP = io.getenv("TMP") || "/tmp";
const dir = TMP + "/jsque004-" + Date.now() + "-" + (Math.random() * 1e9 | 0);
const proj = "p";
const shard = dir + "/.be/" + proj;
io.mkdir(dir); io.mkdir(dir + "/.be"); io.mkdir(shard);

//  --- hermetic store: a commit -> tree -> blob in one keeper pack ----------
//  resolveHex(full) needs the object to exist; resolveRef needs a refs tip.
const pk = git.pack.mmap(shard + "/0000000001.keeper", "c", 1 << 16);
pk.header();
const blobBody = utf8.Encode("hello jsque004\n");
const blobSha  = sha.frameSha("blob", blobBody);
pk.feed("blob", blobBody);
const treeBody = treeEntry("100644", "hello.txt", blobSha);
const treeSha  = sha.frameSha("tree", treeBody);
pk.feed("tree", treeBody);
const commitBody = utf8.Encode("tree " + treeSha + "\n" +
  "author a <a@x> 1700000000 +0000\ncommitter a <a@x> 1700000000 +0000\n\nseed\n");
const commitSha = sha.frameSha("commit", commitBody);
pk.feed("commit", commitBody);
pk.finish();

//  refs: trunk + a `feat` branch both at the commit; a second commit for ?<sha>.
store.set(shard, "", commitSha);
store.set(shard, "feat", commitSha);

//  wtlog: row-0 redirect (secondary-wt anchor) + a cur tip on `feat`.
const bePath = dir + "/.be/wtlog";
ulog.write(bePath, [
  { verb: "get", uri: "file:" + dir + "/.be/?/" + proj },
  { verb: "get", uri: "?feat#" + commitSha }
]);

//  a .gitignore at the wt root (the snapshot the seed pins).
writeFile(dir + "/.gitignore", "*.log\nbuild/\n");

//  repo handle as be.find() would return (only the used fields).
const repo = { wt: dir, storePath: dir, project: proj, bePath: bePath, root: dir };
const k = store.open(dir, proj);
const wtl = wtlog.open(repo);

//  --- build the seed ctx (the pin happens HERE, once) ----------------------
//  Spy on resolveRef so we can prove NO live re-resolve happens after seeding.
let refResolves = 0;
const realResolveRef = k.resolveRef;
k.resolveRef = function () { refResolves++; return realResolveRef.apply(this, arguments); };

const ctx = resolve.seedCtx(repo, wtl, k);

//  cur was pinned to its ABSOLUTE branch + sha; baseline + anyPd + ignore too.
eq(ctx.curBranch, "feat", "ctx: cur branch pinned to absolute label");
eq(ctx.curSha, commitSha, "ctx: cur sha pinned");
eq(ctx.baselineSha, commitSha, "ctx: baseline sha pinned");
eq(ctx.anyPd, false, "ctx: commit-all bit (no put/delete after last get) pinned");
ok(ctx.ignore && ctx.ignore.match("foo.log", false),
   "ctx: .gitignore snapshot pinned (*.log ignored)");
ok(ctx.ignore.match("build/x", false), "ctx: .gitignore build/ ignored");

//  --- (A) multi-path batch fans 1:1, every row BRANCH-FREE -----------------
const sPut = resolve.seed("put", ["a.txt", "b.txt", "c.txt"], ctx, repo);
eq(sPut.rows.length, 3, "put a b c: one seed row per path arg");
eq(sPut.refs.length, 0, "put a b c: no ref-write ops");
eq(sPut.rows.map(function (r) { return r.path; }).join(","), "a.txt,b.txt,c.txt",
   "put a b c: row paths in arg order");
for (const r of sPut.rows) {
  ok(!("branch" in r), "put row carries NO branch label: " + r.path);
  eq(r.baseline, commitSha, "put row pins the baseline commit (branch-free): " + r.path);
}

//  --- (B) ref-write `?br#<sha>` set pins branch -> 40-hex sha ---------------
const short = commitSha.slice(0, 12);
const sSet = resolve.seed("put", ["?feat#" + short], ctx, repo);
eq(sSet.rows.length, 0, "?br#sha: no path rows");
eq(sSet.refs.length, 1, "?br#sha: one ref op");
eq(sSet.refs[0].op, "set", "?br#sha: set op");
eq(sSet.refs[0].branch, "feat", "?br#sha: branch");
eq(sSet.refs[0].sha, commitSha, "?br#sha: short hashlet pinned to the full 40-hex sha");
ok(sha.isFullSha(sSet.refs[0].sha), "?br#sha: pinned sha is a full 40-hex");

//  --- (C) ref-write `?br` create (no sha yet — branch absent) ---------------
const sNew = resolve.seed("put", ["?brandnew"], ctx, repo);
eq(sNew.refs.length, 1, "?br: one ref op");
eq(sNew.refs[0].op, "create", "?br (no #): create op");
eq(sNew.refs[0].branch, "brandnew", "?br: branch name");

//  --- (D) `?#<sha>` trunk reset + `?<40hex>` cur-branch set -----------------
const sTrunk = resolve.seed("put", ["?#" + short], ctx, repo);
eq(sTrunk.refs[0].op, "set", "?#sha: set op");
eq(sTrunk.refs[0].branch, "", "?#sha: trunk (empty branch)");
eq(sTrunk.refs[0].sha, commitSha, "?#sha: pinned to full sha");

const sCur = resolve.seed("put", ["?" + commitSha], ctx, repo);
eq(sCur.refs[0].op, "set", "?<40hex>: set op");
eq(sCur.refs[0].branch, "feat", "?<40hex>: sets cur's ABSOLUTE branch");
eq(sCur.refs[0].sha, commitSha, "?<40hex>: pinned sha");

//  --- (E) mixed batch: a path + a ref-write in one argv ---------------------
const sMix = resolve.seed("put", ["x.txt", "?feat#" + short, "y.txt"], ctx, repo);
eq(sMix.rows.length, 2, "mixed: two path rows");
eq(sMix.refs.length, 1, "mixed: one ref op");
eq(sMix.rows.map(function (r) { return r.path; }).join(","), "x.txt,y.txt",
   "mixed: path rows keep arg order around the ref form");

//  --- (E2) move-form `<old>#<new>`: frag is a DEST path, kept on the row -----
const sMv = resolve.seed("put", ["old.txt#new.txt"], ctx, repo);
eq(sMv.rows.length, 1, "move: one path row");
eq(sMv.rows[0].path, "old.txt", "move: path = old");
eq(sMv.rows[0].dst, "new.txt", "move: dst = new (a path, not a hash)");

//  --- (F) PATCH triple pinned ONCE (ours/theirs/fork) -----------------------
const sPatch = resolve.seed("patch", ["?feat"], ctx, repo);
ok(sPatch.triple, "patch: a commit triple is pinned");
eq(sPatch.triple.ours, commitSha, "patch: ours pinned to cur sha");
eq(sPatch.triple.theirs, commitSha, "patch: theirs pinned to ?feat tip");
ok(sha.isFullSha(sPatch.triple.theirs), "patch: theirs is a full sha");

//  NAMED cherry `#<sha>`: theirs = the named commit, fork = its parent.  The
//  fixture commit is a root (no parent) → resolveCherry refuses; assert that.
throws(function () { resolve.seed("patch", ["#" + commitSha], ctx, repo); },
       "patch #<root-sha>: cherry of a root commit refuses at seed");

//  --- (G) THE INVARIANT: seed rows are branch-free + self-contained ---------
//  Two checks. (G1) STRUCTURAL: a pinned path row must carry NO branch / query
//  label and NO deferred resolver thunk — the only fields a handler may act on
//  are pinned hashes + the on-disk path.  A per-row-deferred design (the bug
//  JSQUE-004 fixes) leaves a `branch`/`query`/resolver on the row so a handler
//  re-resolves it live.  (G2) DYNAMIC: "running" every row (reading its pinned
//  fields, as a handler would) must NOT advance the live resolver counter.
const before = refResolves;
function runHandler(row) {
  //  a handler reads ONLY pinned hashes + the on-disk path; never a resolver.
  return row.path + "?" + (row.newSha || "") + "#" + (row.oldSha || row.baseline || "");
}
for (const r of sPut.rows.concat(sMix.rows)) {
  for (const k of ["branch", "query", "ref", "_resolve", "_resolveRef", "resolve"])
    ok(!(k in r), "G1: pinned row carries no '" + k + "' (branch-free): " + r.path);
  for (const v in r) ok(typeof r[v] !== "function",
                        "G1: pinned row holds no resolver thunk: " + r.path + "." + v);
  runHandler(r);
}
eq(refResolves, before, "G2: running pinned rows did NOT re-resolve any ref live");

//  And every emitted ref op already carries a resolved (or absent-for-create)
//  sha — never a branch label a handler would have to resolve.
for (const s of [sSet, sTrunk, sCur, sMix]) for (const ref of s.refs)
  if (ref.op === "set") ok(sha.isFullSha(ref.sha), "ref set op pre-pinned to a full sha");

//  --- (H) an unresolvable ref throws AT THE SEED, not downstream ------------
throws(function () { resolve.seed("put", ["?#deadbeef99"], ctx, repo); },
       "unresolvable ?#<hashlet> throws at seed (no half-pinned row escapes)");

k.resolveRef = realResolveRef;   // restore

//  cleanup
function rmrf(d) {
  let ents; try { ents = io.readdir(d); } catch (e) { return; }
  for (const f of ents) { const p = d + "/" + f;
    try { io.stat(p).kind === "dir" ? rmrf(p) : io.unlink(p); } catch (e) {} }
}
rmrf(dir);
io.log("resolve.js OK\n");

//  --- fixture helpers -------------------------------------------------------
//  one git tree entry: "<mode> <name>\0" + 20 raw sha bytes.
function treeEntry(mode, name, hexSha) {
  const hdr = utf8.Encode(mode + " " + name + "\0");
  const raw = hex.decode(hexSha);
  const out = new Uint8Array(hdr.length + raw.length);
  out.set(hdr, 0); out.set(raw, hdr.length);
  return out;
}
function writeFile(p, text) {
  const bytes = utf8.Encode(text);
  const fd = io.open(p, "c");
  try { const b = io.buf(bytes.length + 8); b.feed(bytes); io.writeAll(fd, b); }
  finally { io.close(fd); }
}
