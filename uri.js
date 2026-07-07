//  URI-015: be/test/uri.js — the git scp-form remote (`git@host:path`) is NOT
//  a URI (native lexer throws `malformed`), so uri.fromGit must DETECT git's
//  colon-before-slash grammar and recompose ssh:// strictly via URI.make; every
//  non-scp shape passes through verbatim.  Hermetic: fromGit + wire.classify
//  are pure (no network, no store).
"use strict";

const { eq, ok } = require("./lib/assert.js");
//  Derive the be/ code dir from THIS script's path (cf. test/wire.js _req).
const uri = _req("shared/uri.js");
const wire = _req("shared/wire.js");
function _req(mod) {
  const self = (typeof process !== "undefined" && process.argv && process.argv[1]) || "";
  if (self) {
    const d = self.slice(0, self.lastIndexOf("/test/"));
    if (d && d !== self) { try { return require(d + "/" + mod); } catch (e) {} }
  }
  return require(mod);
}

//  --- fromGit: the scp form recomposes to ssh:// ---------------------------
eq(uri.fromGit("git@github.com:gritzko/jab.git"),
   "ssh://git@github.com/gritzko/jab.git", "scp form -> ssh://");
//  A beagle branch selector / pin on the tail rides into its URI slot.
eq(uri.fromGit("git@github.com:gritzko/jab.git?master"),
   "ssh://git@github.com/gritzko/jab.git?master", "scp tail keeps ?branch");
eq(uri.fromGit("git@github.com:gritzko/jab.git?b#7dabf5e3"),
   "ssh://git@github.com/gritzko/jab.git?b#7dabf5e3", "scp tail keeps ?b#sha");

//  --- fromGit: non-scp shapes pass through VERBATIM ------------------------
eq(uri.fromGit("ssh://git@github.com/gritzko/jab.git"),
   "ssh://git@github.com/gritzko/jab.git", "ssh:// untouched");
eq(uri.fromGit("be:/home/u/.be?/proj"), "be:/home/u/.be?/proj", "be:-local untouched");
eq(uri.fromGit("keeper:local/p"), "keeper:local/p", "keeper: untouched");
eq(uri.fromGit("//host/owner/repo.git"), "//host/owner/repo.git", "cached //host untouched");
eq(uri.fromGit("https://github.com/gritzko/jab.git"),
   "https://github.com/gritzko/jab.git", "https:// untouched");
eq(uri.fromGit("shared/wire.js"), "shared/wire.js", "bare path untouched");
eq(uri.fromGit("host:8080"), "host:8080", "no user@ head -> untouched");
eq(uri.fromGit("fix the bug @ 10:30"), "fix the bug @ 10:30", "prose untouched");
eq(uri.fromGit(""), "", "empty untouched");

//  --- classify: the scp remote routes as vanilla git-over-ssh --------------
const c = wire.classify("git@github.com:gritzko/jab.git", "upload-pack");
eq(c.ssh, true, "scp remote routes to ssh");
ok(c.http == null, "scp remote is not http");
eq(JSON.stringify(c.argv), JSON.stringify(
   ["ssh", "git@github.com", "git-upload-pack 'gritzko/jab.git'"]),
   "scp argv = git's own scp handling (userinfo dest, HOME-relative path)");

io.log("PASS be-js-unit-uri");
