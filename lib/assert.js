"use strict";
//  Tiny assert helpers for the test/js/* JABC scripts (mirrors the
//  inline `fail`/`eq` style in js/test/*.js).  Each throws on failure,
//  which JABCRun turns into a non-zero exit so ctest reports red.

function fail(m) { throw "FAIL " + m; }

//  Strict scalar equality (numbers, strings, booleans).
function eq(a, b, m) { if (a !== b) fail((m || "eq") + ": " + a + " !== " + b); }

//  Truthy assertion.
function ok(v, m) { if (!v) fail((m || "ok") + ": not truthy"); }

//  Byte-for-byte equality of two array-likes (Uint8Array / array).
function bytesEq(a, b, m) {
  if (a.length !== b.length) fail((m || "bytesEq") + ": len " + a.length + " !== " + b.length);
  for (let i = 0; i < a.length; i++)
    if (a[i] !== b[i]) fail((m || "bytesEq") + ": byte " + i + " " + a[i] + " !== " + b[i]);
}

//  Assert that `fn` throws (any error).
function throws(fn, m) {
  let threw = false;
  try { fn(); } catch (e) { threw = true; }
  if (!threw) fail((m || "throws") + ": did not throw");
}

module.exports = { fail, eq, ok, bytesEq, throws };
