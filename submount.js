//  SUBS-047: shared/submount.js same-source child addressing.  Two repro'd
//  defects off `jab get ssh://localhost/src/beagle`:
//  (A) sameSourceUri hand-concatenated `"//" + u.authority` where u.authority
//      already carries the `//` → `ssh:////localhost/...` (URI-013) — the child
//      fetch NEVER hit the source.  Composition must go through URI.make.
//  (B) a git source WITH a worktree (path not ending `.git`) serves each sub's
//      own checkout at `<path>/<subpath>` — that same-source form is tried
//      FIRST, the `.gitmodules` url is only the fallback ([Submodules] §1).
//      A nested sub (`dog/abc`) is declared in `dog/.gitmodules` as `abc`,
//      so the fallback resolves against the NEAREST enclosing `.gitmodules`
//      (the root-only lookup returned "" and the whole mount threw SUBFETCH).
"use strict";

const { eq, ok } = require("./lib/assert.js");
//  DIS-054: resolve the module under test off THIS script's own path first,
//  so an isolated ticket clone tests ITS code, not the live shard's.
const submount = _req("shared/submount.js");
function _req(mod) {
  const self = (typeof process !== "undefined" && process.argv && process.argv[1]) || "";
  if (self) {
    const d = self.slice(0, self.lastIndexOf("/test/"));
    if (d && d !== self) { try { return require(d + "/" + mod); } catch (e) {} }
  }
  return require(mod);
}

//  --- (A)+(B) sameSourceUris: table-driven over source × sub ---------------
//  `source` mirrors get.js parseRemote ({ raw, local }); expected candidates
//  are asserted slot-by-slot via the URI class, plus a NO-`:////` guard.
const CASES = [
  { name: "ssh worktree source, top-level sub",
    source: { raw: "ssh://localhost/src/beagle", local: false },
    title: "libdog", subpath: "dog",
    want: [{ scheme: "ssh", host: "localhost", path: "/src/beagle/dog" }] },
  { name: "ssh worktree source, nested sub",
    source: { raw: "ssh://localhost/src/beagle", local: false },
    title: "libabc", subpath: "dog/abc",
    want: [{ scheme: "ssh", host: "localhost", path: "/src/beagle/dog/abc" }] },
  { name: "ssh worktree source, trailing slash",
    source: { raw: "ssh://localhost/src/beagle/", local: false },
    title: "libdog", subpath: "dog",
    want: [{ scheme: "ssh", host: "localhost", path: "/src/beagle/dog" }] },
  { name: "bare .git source has no same-source sub",
    source: { raw: "ssh://git@github.com/gritzko/beagle.git", local: false },
    title: "libdog", subpath: "dog",
    want: [] },
  { name: "https bare .git source has no same-source sub",
    source: { raw: "https://github.com/gritzko/beagle.git", local: false },
    title: "libdog", subpath: "dog",
    want: [] },
  { name: "beagle store over ssh: project swap",
    source: { raw: "be://host/store/.be?/par", local: false },
    title: "sub", subpath: "vendor/sub",
    want: [{ scheme: "be", host: "host", path: "/store/.be", query: "/sub" }] },
  { name: "local file: store: project swap",
    source: { raw: "file:/w/par/.be?/par", local: true },
    title: "sub", subpath: "vendor/sub",
    want: [{ scheme: "file", path: "/w/par/.be", query: "/sub" }] },
  { name: "scheme-less local store: project swap",
    source: { raw: "/w/par/.be", local: true },
    title: "sub", subpath: "vendor/sub",
    want: [{ path: "/w/par/.be", query: "/sub" }] },
  { name: "no source",
    source: null, title: "sub", subpath: "vendor/sub", want: [] },
];

for (const c of CASES) {
  const got = submount.sameSourceUris(c.source, c.title, c.subpath);
  eq(got.length, c.want.length, c.name + ": candidate count");
  for (let i = 0; i < c.want.length; i++) {
    const raw = got[i], w = c.want[i];
    ok(raw.indexOf(":////") < 0, c.name + ": doubled authority `:////` in " + raw);
    const u = new URI(raw);
    if (w.scheme !== undefined) eq(u.scheme, w.scheme, c.name + ": scheme of " + raw);
    if (w.host !== undefined) eq(u.host, w.host, c.name + ": host of " + raw);
    eq(u.path, w.path, c.name + ": path of " + raw);
    if (w.query !== undefined) eq(u.query, w.query, c.name + ": query of " + raw);
  }
}

//  --- (B) declaredUrl: the NEAREST enclosing .gitmodules wins ---------------
//  wt/.gitmodules declares `dog`; wt/dog/.gitmodules declares `abc` — the
//  nested sub's official url must resolve through the walk, root-only misses it.
const TMP = io.getenv("TMP") || "/tmp";
const wt = TMP + "/js-submount-" + Date.now() + "-" + (Math.random() * 1e9 | 0);
io.mkdir(wt); io.mkdir(wt + "/dog");
function writeFile(p, s) {
  const u = utf8.Encode(s); const b = io.buf(u.length + 8); b.feed(u);
  const fd = io.open(p, "c"); io.write(fd, b); io.close(fd);
}
writeFile(wt + "/.gitmodules",
  '[submodule "dog"]\n\tpath = dog\n\turl = https://github.com/gritzko/libdog.git\n');
writeFile(wt + "/dog/.gitmodules",
  '[submodule "abc"]\n\tpath = abc\n\turl = https://github.com/gritzko/libabc.git\n');

eq(submount.declaredUrl(wt, "dog"), "https://github.com/gritzko/libdog.git",
   "declaredUrl: root-declared sub");
eq(submount.declaredUrl(wt, "dog/abc"), "https://github.com/gritzko/libabc.git",
   "declaredUrl: nested sub via dog/.gitmodules");
eq(submount.declaredUrl(wt, "dog/nosuch"), "", "declaredUrl: undeclared nested");
eq(submount.declaredUrl(wt, "nosuch"), "", "declaredUrl: undeclared top-level");

//  The nested official url also names the [Title]: `libabc`, not the basename.
eq(submount.titleFromUrl(submount.declaredUrl(wt, "dog/abc")), "libabc",
   "nested sub title derives from its own declared url");

function w(s){const u=utf8.Encode(s+"\n");const b=io.buf(u.length+8);b.feed(u);io.write(1,b);}
w("PASS submount.js");
