#!/bin/sh
# test/js/bro/view — `bin/bro.js --plain` vs native `bro --plain` (JS-053
# TODO#2).  Asserts byte-identical stdout for the file/dir SYNTAX view: a
# syntax-highlighted source file (.c and .js), a file opened at #line and at
# #symbol, a directory listing, and multiple-file args — plus the edge cases
# (no-trailing-newline file, empty dir, missing URI).
. "$(dirname "$0")/../lib/brocase.sh"

# A small tree under $WORK so the listing/contents are deterministic.
mkdir -p "$WORK/src/sub"
cat > "$WORK/src/a.c" <<'EOF'
// a comment
#include <stdio.h>
int main(void) { return 42; }
EOF
cat > "$WORK/src/b.js" <<'EOF'
"use strict";
const x = 1;        // number + keyword
function f() { return "ok"; }
EOF
printf 'plain text, no extension\n' > "$WORK/src/notes"
printf 'no-trailing-newline' > "$WORK/src/nonl.txt"
printf 'hidden\n' > "$WORK/src/.dotfile"
mkdir -p "$WORK/empty"

cd "$WORK/src"

# 1. syntax-highlighted source files (.c and .js).
bro_eq "c-file"   a.c
bro_eq "js-file"  b.js

# 2. open at #line and at #symbol (the fragment rides the banner; text is full).
bro_eq "file#line"   a.c#2
bro_eq "file#symbol" a.c#main

# 3. directory listing (FILE_SCAN_ALL: includes the dotfile; dirs get '/').
bro_eq "dir-bare"  .
bro_eq "dir-slash" "$WORK/src/"

# 4. multiple-file args (multiple banners + bodies, in order).
bro_eq "multi"      a.c b.js
bro_eq "multi-mix"  a.c . notes

# 5. edge cases.
bro_eq "no-ext-file"   notes
bro_eq "no-newline"    nonl.txt
bro_eq "empty-dir"     "$WORK/empty/"
bro_eq "missing"       does-not-exist.xyz

pass
