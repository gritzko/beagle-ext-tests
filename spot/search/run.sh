#!/bin/sh
# test/js/spot/search — JAB-021/022/023 parity for the `spot:` / `grep:` /
# `regex:` search VIEWs over the resident loop (`jab loop.js <verb> <uri>`; the
# scheme is the verb).  Pure JS over tok + classify + the abc.index u64 lane +
# emit; the handler spawns NO dog binary and reads NO /proc.
#
# Fixtures keep every match near file TOP so the context window starts at line 1
# — native then emits `path#Lnn` with NO `#func` (the DEF S->N retag the URI's
# func segment needs has no JS binding; that is a separate MUST-ASK).  Cases:
#   grep: literal-substring hit; regex: native RegExp; spot: structural match
#   (placeholder N); zero-hit (no hunks, OK exit); `.ext` gate (spot w/o ext);
#   no-body hint (grep:/spot: with empty body → stderr + non-zero exit).
. "$(dirname "$0")/../lib/spotcase.sh"

WT=$(new_wt search)
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
# many.c: several top-region hits in one + across files (coalesce + ordering)
cat > many.c <<'EOF'
int foo(int a) { return a; }
int bar(int b) { return b; }
int baz(int c) { return c; }
EOF
# slice.c: the C-test flagship structural {A[0], A[1]} bracket-balance case
cat > slice.c <<'EOF'
void f() {
    u8cs a = {arr[0], arr[1]};
    u8cs b = {(*fp)[0], (*fp)[1]};
}
EOF
"$BE" post -m base >/dev/null 2>&1 || "$BE" post base >/dev/null 2>&1
# TEST-003: jab's `sha1:?` prints `sha1?<hex40>` (scheme prefix); the historic
# `?ref` trail arg wants BARE hex, so grep the 40-hex tip out.
TIP=$("$BE" 'sha1:?' --plain 2>/dev/null | grep -oE '[0-9a-f]{40}' | head -1)

# --- grep: literal substring (one hit, top region) ------------------------
spot_eq "grep literal hit"        'grep:.c#beta'
# --- grep: multi-hit, multi-file (coalesce + BFS file ordering) -----------
spot_eq "grep multi-file/coalesce" 'grep:.c#int'
spot_eq "grep return all"         'grep:.c#return'
# --- grep: zero hits (no hunks, OK exit) ----------------------------------
spot_zero "grep zero hits"        'grep:.c#zzznotfound'
# --- regex: native RegExp -------------------------------------------------
spot_eq "regex match"             'regex:.c#na.es'
spot_eq "regex anchored"          'regex:.c#^int'
# --- spot: structural placeholder (N binds a token block) -----------------
spot_eq "spot structural"         'spot:.c#int g = N'
# --- spot: bracket-balanced block bind ({A[0], A[1]}) ---------------------
spot_eq "spot bracket block"      'spot:.c#{A[0], A[1]}'
# --- spot: lowercase single-token + uppercase block on one needle ---------
spot_eq "spot lower+upper"        'spot:.c#int a = b'
# --- spot: zero hits ------------------------------------------------------
spot_zero "spot zero hits"        'spot:.c#nosuch q = Z'

# --- historic ?ref search (canonical trail-arg form: ref is a SEPARATE arg)
spot_eq "grep historic ?tip"      'grep:.c#alpha' "?$TIP"

# --- spot: requires a .ext (the gate) -------------------------------------
spot_err "spot .ext gate"         'spot:#alpha'   'requires a .ext'
# --- grep: no body hint ---------------------------------------------------
spot_err "grep no-body hint"      'grep:'         'needs a search body'
# --- spot: no body hint ---------------------------------------------------
spot_err "spot no-body hint"      'spot:'         'needs a search body'

pass
