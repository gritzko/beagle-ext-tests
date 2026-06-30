//  GIT-012: be/test/wire.js — wire transport classify() routing + smart-HTTP
//  advert parsing.  Asserts http(s) URLs route to the new curl adapter (NOT
//  ssh), ssh/be/local routes stay put, and the HTTP advert drainer skips the
//  `# service=…`+flush preamble.  Hermetic: classify is pure, the advert is a
//  recorded pkt-line fixture run through the parser (no network).
"use strict";

const { eq, ok, throws } = require("./lib/assert.js");
//  Derive the be/ code dir from THIS script's path (cf. test/store.js _req).
const wire = _req("shared/wire.js");
const pkt = _req("shared/pkt.js");
function _req(mod) {
  const self = (typeof process !== "undefined" && process.argv && process.argv[1]) || "";
  if (self) {
    const d = self.slice(0, self.lastIndexOf("/test/"));
    if (d && d !== self) { try { return require(d + "/" + mod); } catch (e) {} }
  }
  return require(mod);
}

//  --- classify routing ---------------------------------------------------
//  https → curl adapter ({http, url}), not an ssh spawn.
let c = wire.classify("https://host/owner/repo.git", "upload-pack");
ok(c.http === true, "https routes to http adapter");
eq(c.url, "https://host/owner/repo.git", "https base url verbatim");
eq(c.ssh, false, "https is not ssh");
ok(c.bin == null, "https has no spawn bin");

//  http (plain, with port) → same adapter.
c = wire.classify("http://host:8080/o/r.git", "upload-pack");
ok(c.http === true, "http routes to http adapter");
eq(c.url, "http://host:8080/o/r.git", "http base url keeps port");

//  An in-band `?<sel>` is stripped from the curl base URL (not a path part).
c = wire.classify("https://host/owner/repo.git?/repo", "upload-pack");
eq(c.url, "https://host/owner/repo.git", "https base drops ?sel");

//  ssh:// stays a vanilla git-over-ssh spawn (BYTE-IDENTICAL to before).
c = wire.classify("ssh://host/owner/repo.git", "upload-pack");
eq(c.bin, "ssh", "ssh keeps ssh bin");
eq(c.ssh, true, "ssh stays ssh");
ok(c.http == null, "ssh is not http");
eq(JSON.stringify(c.argv), JSON.stringify(
   ["ssh", "host", "git-upload-pack 'owner/repo.git'"]), "ssh argv unchanged");

//  Scheme-less //host: pre-existing routing (NOT http) — must be untouched.
c = wire.classify("//host/owner/repo.git", "upload-pack");
ok(c.http == null, "//host is not http");

//  be://host → ssh keeper (keeper protocol), NOT http.
c = wire.classify("be://host/p", "upload-pack");
eq(c.ssh, true, "be://host stays ssh");
ok(c.http == null, "be://host is not http");

//  file:// (local keeper exec) — unchanged.
c = wire.classify("file:///abs/store", "upload-pack");
eq(c.ssh, false, "file:// is local");
ok(c.http == null, "file:// is not http");

//  --- smart-HTTP advert preamble drain -----------------------------------
//  A recorded info/refs body: `# service`+flush preamble, then one ref +caps,
//  then the closing flush.  parseAdvLine must read the ref AFTER the preamble.
const SHA = "7dabf5e3d5837e1b5be6f3dd94c4de049436a8ff";
function plines() {
  const parts = [];
  parts.push(pkt.frame("# service=git-upload-pack\n"));
  parts.push(pkt.flushPkt());
  parts.push(pkt.frame(SHA + " refs/heads/master\0multi_ack ofs-delta\n"));
  parts.push(pkt.flushPkt());
  let n = 0; for (const p of parts) n += p.length;
  const b = new Uint8Array(n); let o = 0;
  for (const p of parts) { b.set(p, o); o += p.length; }
  return b;
}
const body = plines();
//  Walk it as the adapter does: skip preamble line+flush, then parse the ref.
let pos = 0;
function nextLine() {
  const total = pkt.readLen(body, pos);
  if (total === 0) { pos += 4; return { flush: true }; }
  const payload = body.slice(pos + 4, pos + total); pos += total;
  return { payload };
}
let ev = nextLine();
ok(utf8.Decode(ev.payload).indexOf("# service=") === 0, "preamble service line");
ev = nextLine(); ok(ev.flush, "preamble flush");
ev = nextLine();
const a = wire.parseAdvLine(ev.payload);
ok(a, "ref line parses");
eq(a.sha, SHA, "ref sha");
eq(a.name, "refs/heads/master", "ref name");
ok(a.caps.indexOf("ofs-delta") >= 0, "caps carried after NUL");

io.log("PASS be-js-unit-wire");
