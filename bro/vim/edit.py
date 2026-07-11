#!/usr/bin/env python3
# BE-047/BE-048 full-stack pager legs over a real pty (pty.fork).  Modes:
#   nav    — BE-047: `jab cat other.txt`, NAVIGATE `:/doc.txt` (rooted slot-
#            edit), `:vim` — the fake PATH vim edits the NAV'D file (doc.txt,
#            not the launch arg), the pager waits + refreshes (marker shown).
#   launch — BE-048: `jab cat doc.txt`, bare `:vim` IMMEDIATELY (no nav — the
#            launch arg's path folded into the context), then `:diff` targets
#            THAT file only (dirty other.txt absent), then `:why` blames it.
#   auth   — BE-048 guard: `jab status //wt` (authority-ONLY) gained NO phantom
#            path — bare `:diff` stays TREE-wide (both dirty files shown).
#   argv[1] = jab   argv[2] = the worktree (CWD; fake editors on PATH)
#   argv[3] = mode
import os, pty, re, select, sys, time

JAB = sys.argv[1]
WT  = sys.argv[2]
MODE = sys.argv[3]
ENV = dict(os.environ, ASAN_OPTIONS="detect_leaks=0")

# The pager syntax-paints body rows (SGR around '-' etc.), so match the frame
# with the ANSI escapes stripped, not the raw byte stream.
ANSI = re.compile(rb"\x1b\[[0-9;?]*[a-zA-Z]")
def plain(b): return ANSI.sub(b"", b)

ARGS = {"nav": ["cat", "other.txt"], "launch": ["cat", "doc.txt"],
        "auth": ["status", "//wt"]}[MODE]

pid, fd = pty.fork()
if pid == 0:
    os.chdir(WT)
    for k, v in ENV.items(): os.environ[k] = v
    os.execv(JAB, [JAB] + ARGS)
    os._exit(127)

out = b""
def read_more(t):
    global out
    r, _, _ = select.select([fd], [], [], t)
    if fd not in r: return False
    try: chunk = os.read(fd, 65536)
    except OSError: return False
    if not chunk: return False
    out += chunk
    return True

def expect(pattern, timeout=15.0):
    global out
    start = time.time()
    while pattern not in out and pattern not in plain(out):
        if time.time() - start > timeout: return False
        read_more(0.5)
    return True

def settle(t=1.0):                    # drain the burst after a keystroke
    end = time.time() + t
    while time.time() < end: read_more(0.3)

fails = 0
def check(name, cond):
    global fails
    print(("ok   " if cond else "FAIL ") + name)
    if not cond: fails += 1

check("pager-frame", expect(b"\x1b[2J"))

if MODE == "nav":
    check("initial-content", expect(b"OTHERFILE"))
    settle(0.3); out = b""
    os.write(fd, b":/doc.txt\r")      # rooted slot-edit: NAV to doc.txt (tracked)
    check("nav-shows-file", expect(b"ORIGINAL"))
    settle(0.3); out = b""
    os.write(fd, b":vim\r")           # the editor edits the NAV'D file, not other.txt
    check("refresh-shows-edit", expect(b"EDITED-BY-VIM"))

elif MODE == "launch":
    check("initial-content", expect(b"ORIGINAL"))
    settle(0.3); out = b""
    os.write(fd, b":vim\r")           # BE-048: NO nav — the launch arg IS the context
    check("launch-vim-edits", expect(b"EDITED-BY-VIM"))
    settle(0.3); out = b""
    os.write(fd, b":diff\r")          # bare :diff targets the launch file
    check("launch-diff-banner", expect(b"diff") and expect(b"doc.txt"))
                                      # (nav-authorized: `diff //wt/doc.txt`)
    settle(0.5)
    check("launch-diff-shows-edit", b"EDITED-BY-VIM" in plain(out))
    check("launch-diff-file-scoped", b"other.txt" not in plain(out))
    out = b""
    os.write(fd, b":why\r")           # bare :why blames the launch file
    check("launch-why-banner", expect(b"why"))
    settle(0.5)
    check("launch-why-shows-file", b"doc.txt" in plain(out))

elif MODE == "auth":
    settle(0.3); out = b""
    os.write(fd, b":vim\r")           # authority-only: NO phantom file — vim gets
    check("auth-vim-no-file", expect(b"err"))    # the wt DIR (fake vim exits 1)
    settle(0.3); out = b""
    os.write(fd, b":diff\r")          # ...and diff stays TREE-wide (no injection)
    check("auth-diff-tree-doc", expect(b"doc.txt"))
    check("auth-diff-tree-other", expect(b"other.txt"))

settle(0.3)
os.write(fd, b"q")

rc = None
start = time.time()
while time.time() - start < 15.0:
    try:
        wpid, status = os.waitpid(pid, os.WNOHANG)
    except ChildProcessError:
        break
    if wpid == pid:
        rc = os.waitstatus_to_exitcode(status)
        break
    read_more(0.3)
if rc is None:
    try: os.kill(pid, 9)
    except OSError: pass
    try: os.waitpid(pid, 0)
    except OSError: pass
check("exit0", rc == 0)

print("DONE" if fails == 0 else "FAILS=%d" % fails)
sys.exit(1 if fails else 0)
