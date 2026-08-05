//  CODE-030: be/test/acyclic.js — the require graph of be/ must be a DAG.
//  A cycle is a misplaced symbol: two files each reaching into the other for a
//  primitive that belongs to neither.  `Object.assign(module.exports, …)` makes
//  a cycle load-order-SAFE but does not remove it, and an in-body `require()`
//  defers the LOAD, not the DEPENDENCY — so BOTH forms count as edges here.
//  Scanned: every .js under core/ shared/ verbs/ views/ view/ plus the root
//  entries.  Resolved spec forms: "./rel", "../rel", bareword "core/x.js",
//  `_here + "/x"` (be root), `__dirname + "/x"`, `libDir() + "/x"` (file dir).
//  EXCLUDED: core/registry.js's runtime `req(f)` verb dispatch — the one
//  legitimate upward edge; folding it in collapses ~50 modules into one SCC.
//  Verdict by Tarjan: no strongly-connected component of size > 1.
"use strict";

const { ok, fail } = require("./lib/assert.js");
//  Derive the be/ code dir from THIS script's path (cf. test/registry.js _req).
const ROOT = (function () {
  const self = (typeof process !== "undefined" && process.argv && process.argv[1]) || "";
  const d = self.slice(0, self.lastIndexOf("/test/"));
  return (d && d !== self) ? d : ".";
})();
const { readFileBytes } = require(ROOT + "/shared/wtread.js");

//  ---- file enumeration -----------------------------------------------------
const DIRS = ["core", "shared", "verbs", "views", "view"];
const ROOTFILES = ["main.js", "ci.js"];

const files = [];
for (const d of DIRS) {
  let names;
  try { names = io.readdir(ROOT + "/" + d, { recursive: true }); } catch (e) { names = []; }
  for (const n of names) if (n.slice(-3) === ".js") files.push(d + "/" + n);
}
for (const f of ROOTFILES) { try { if (io.stat(ROOT + "/" + f)) files.push(f); } catch (e) {} }
ok(files.length > 50, "acyclic: expected the whole be/ shard, got " + files.length + " files");

function slurp(rel) {
  const st = io.stat(ROOT + "/" + rel);
  const b = readFileBytes(ROOT + "/" + rel, st.size);
  if (b === null) fail("acyclic: cannot read " + rel);
  return utf8.Decode(b);
}

//  ---- comment / string stripping -------------------------------------------
//  Blank out line comments, block comments and template literals so a
//  `require(` inside prose (registry.js's own doc lines) is not read as an edge.
//  Quoted strings are KEPT — the specs live in them — but their contents are
//  never scanned for `require(` since the scanner matches the call syntax.
function strip(src) {
  let out = "", i = 0, n = src.length;
  while (i < n) {
    const c = src[i];
    if (c === "/" && src[i + 1] === "/") { while (i < n && src[i] !== "\n") i++; continue; }
    if (c === "/" && src[i + 1] === "*") { i += 2; while (i < n && !(src[i] === "*" && src[i + 1] === "/")) i++; i += 2; continue; }
    if (c === '"' || c === "'" || c === "`") {
      const q = c; out += c; i++;
      while (i < n && src[i] !== q) { if (src[i] === "\\") { out += src[i]; i++; } out += src[i]; i++; }
      out += q; i++; continue;
    }
    out += c; i++;
  }
  return out;
}

//  ---- spec extraction ------------------------------------------------------
//  One regex per accepted argument shape; the "…" forms build a path at load
//  time from a directory handle, so they resolve exactly like a literal.
const RE_LIT = /require\(\s*"([^"]+)"\s*\)/g;
const RE_HERE = /require\(\s*_here\s*\+\s*"([^"]+)"\s*\)/g;
const RE_DIRNAME = /require\(\s*__dirname\s*\+\s*"([^"]+)"\s*\)/g;
const RE_LIBDIR = /require\(\s*libDir\(\)\s*\+\s*"([^"]+)"\s*\)/g;

function all(re, src) {
  const out = []; re.lastIndex = 0;
  let m; while ((m = re.exec(src)) !== null) out.push(m[1]);
  return out;
}

//  Collapse "a/b/../c" and "a/./b" — no io, pure lexical, as jab's normalize().
function normalize(p) {
  const parts = p.split("/"), st = [];
  for (const s of parts) {
    if (s === "" || s === ".") continue;
    if (s === "..") { st.pop(); continue; }
    st.push(s);
  }
  return st.join("/");
}

//  Resolve a spec found in `from` (a ROOT-relative file path) to a ROOT-relative
//  module path, or null when it points outside the shard / does not exist.
function resolve(from, spec, base) {
  const dir = from.indexOf("/") < 0 ? "" : from.slice(0, from.lastIndexOf("/"));
  const p = normalize(base === "here" ? spec
                    : base === "dir" ? dir + "/" + spec
                    : (spec[0] === "." ? dir + "/" + spec : spec));
  try { if (io.stat(ROOT + "/" + p)) return p; } catch (e) {}
  return null;
}

const edges = {};        // file -> [file]
const unresolved = [];
for (const f of files) {
  const src = strip(slurp(f));
  const out = [];
  const add = (specs, base) => {
    for (const s of specs) {
      const t = resolve(f, s, base);
      if (t === null) { unresolved.push(f + " -> " + s); continue; }
      if (t !== f && out.indexOf(t) < 0) out.push(t);
    }
  };
  add(all(RE_LIT, src), "rel");
  add(all(RE_HERE, src), "here");
  add(all(RE_DIRNAME, src), "dir");
  add(all(RE_LIBDIR, src), "dir");
  edges[f] = out;
}
//  Every spec must resolve inside the shard; an unresolved one means the scanner
//  missed a form and the graph would be under-reported (a false green).
ok(unresolved.length === 0, "acyclic: unresolved require specs:\n  " + unresolved.join("\n  "));

//  ---- Tarjan ---------------------------------------------------------------
//  Iterative (the graph is 100+ nodes deep in places and jab's stack is small).
function tarjan(nodes, adj) {
  const index = {}, low = {}, onstack = {}, stack = [], sccs = [];
  let counter = 0;
  for (const root of nodes) {
    if (index[root] !== undefined) continue;
    const work = [[root, 0]];
    while (work.length) {
      const top = work[work.length - 1];
      const v = top[0];
      if (top[1] === 0) { index[v] = low[v] = counter++; stack.push(v); onstack[v] = true; }
      let recursed = false;
      const succ = adj[v] || [];
      while (top[1] < succ.length) {
        const w = succ[top[1]++];
        if (index[w] === undefined) { work.push([w, 0]); recursed = true; break; }
        if (onstack[w] && low[v] > index[w]) low[v] = index[w];
      }
      if (recursed) continue;
      if (low[v] === index[v]) {
        const comp = [];
        for (;;) { const w = stack.pop(); onstack[w] = false; comp.push(w); if (w === v) break; }
        sccs.push(comp);
      }
      work.pop();
      if (work.length) { const p = work[work.length - 1][0]; if (low[p] > low[v]) low[p] = low[v]; }
    }
  }
  return sccs;
}

const cycles = tarjan(files, edges).filter((c) => c.length > 1);
if (cycles.length) {
  const lines = cycles.map((c) => "  " + c.slice().sort().join("  <->  ")).join("\n");
  fail("acyclic: " + cycles.length + " require cycle(s) in be/:\n" + lines);
}

io.log("acyclic.js: " + files.length + " modules, " +
       files.reduce((n, f) => n + edges[f].length, 0) + " edges, no cycles\n");
