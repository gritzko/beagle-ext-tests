#!/bin/sh
# test/js/regex/regex — JAB-023 parity for the `regex:` search VIEW over the
# resident loop (`jab loop.js regex <uri>`; the scheme is the verb).  The regex
# MODE of the shared search scaffold (JAB-021): native JS RegExp REPLACES the
# Thompson NFA, line-search per drained line, ±3-line context window, the
# `path#Lnn` URI + trailing-`\n`+blank-line plain framing.  Pure JS over tok +
# classify + the abc.index u64 lane + emit; spawns NO dog, reads NO /proc.
#
# Fixtures keep every match near file TOP so the context window starts at line 1
# — native then emits `path#Lnn` with NO `#func` (the DEF S->N retag the URI's
# func segment needs has no JS binding; that is a separate MUST-ASK, shared with
# JAB-021).  Cases: literal hit; `.`/`*+?`/`{n,m}`/class/`\d\w\s` dialect;
# alternation; anchors; zero-hit; bad-regex stderr+exit; no-body hint; `.ext`
# wrong-slot hint.  Sources the shared spotcase harness with NEED_VERB=regex.
NEED_VERB=regex
export NEED_VERB
. "$(dirname "$0")/../../spot/lib/spotcase.sh"

WT=$(new_wt regex)
cd "$WT"
cat > a.c <<'EOF'
int alpha = 1;
int beta = 2;
int gamma = 3;
EOF
cat > b.c <<'EOF'
char *names[] = { "one", "two" };
int count = 2;
EOF
cat > note.txt <<'EOF'
plain text line one
plain text line two
EOF
"$BE" post -m base >/dev/null 2>&1 || "$BE" post base >/dev/null 2>&1

# --- literal hit (one hit, top region) ------------------------------------
spot_eq "regex literal hit"        'regex:.c#beta'
# --- `.` wildcard (ANY) ---------------------------------------------------
spot_eq "regex dot wildcard"       'regex:.c#na.es'
# --- char class + range ---------------------------------------------------
spot_eq "regex class range"        'regex:.c#a[0-9a-z]'
# --- negated class --------------------------------------------------------
spot_eq "regex negated class"      'regex:.c#[^ ]nt'
# --- `\d` shorthand -------------------------------------------------------
spot_eq "regex \\d shorthand"      'regex:.c#= \d'
# --- `\w` shorthand -------------------------------------------------------
spot_eq "regex \\w shorthand"      'regex:.c#\w\w\w\w'
# --- `\s` shorthand -------------------------------------------------------
spot_eq "regex \\s shorthand"      'regex:.c#int\sbeta'
# --- quantifiers `* + ?` --------------------------------------------------
spot_eq "regex star quant"         'regex:.c#ga*mma'
spot_eq "regex plus quant"         'regex:.c#l+pha'
spot_eq "regex opt quant"          'regex:.c#alpha?'
# --- counted `{n}` `{n,}` `{n,m}` `{,m}` -----------------------------------
# TEST-003: `l{2}` (=`ll`) has no match in the fixture (alpha has one l); use
# `m{2}` (=`mm`, in `gamma`) so the `{n}` quantifier genuinely hits.
spot_eq "regex {n} counted"        'regex:.c#m{2}'
spot_eq "regex {n,} counted"       'regex:.c#a{1,}'
spot_eq "regex {n,m} counted"      'regex:.c#l{1,3}'
spot_eq "regex {,m} counted"       'regex:.c#l{,3}'
# --- alternation ----------------------------------------------------------
spot_eq "regex alternation"        'regex:.c#alpha|gamma'
# --- grouping -------------------------------------------------------------
spot_eq "regex grouping"           'regex:.c#(al|ga)'
# --- anchors `^` / `$` (line-bound) ---------------------------------------
spot_eq "regex BOL anchor"         'regex:.c#^int'
spot_eq "regex EOL anchor"         'regex:.c#3;$'
# --- zero hits (no hunks, OK exit) ----------------------------------------
spot_zero "regex zero hits"        'regex:.c#zzznotfound'
# --- ext gate: only .c searched (txt skipped even though it would match) --
# TEST-003: `line` lives ONLY in note.txt; with the `.c` gate no .c file matches,
# so the result is EMPTY — proving the txt (which WOULD match) was skipped.
spot_zero "regex ext gate skips txt" 'regex:.c#line'

# --- bad regex -> stderr 'bad regex' + non-zero exit ----------------------
spot_err "regex bad pattern"       'regex:.c#a['   'bad regex'
# --- no body hint ---------------------------------------------------------
spot_err "regex no-body hint"      'regex:'        'needs a search body'
spot_err "regex empty-frag hint"   'regex:#'       'needs a search body'
# --- body in wrong slot (path, not fragment) ------------------------------
spot_err "regex wrong-slot hint"   'regex:beta'    'goes in the URI fragment'

pass
