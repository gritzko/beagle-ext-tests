#!/usr/bin/env python3
# TODO-005 `[go]` pty click driver (the test/todo/click model).  Forks a pty,
# execs the REAL `jab todo GO` in it (isatty(1) -> the universal bro pager),
# presses the `[go]` face, and reads the RESULT off the FILESYSTEM: the board's
# one CREATE button must leave a populated `work/GO-001` behind.
#   argv[1] = jab binary   argv[2] = the fixture project root (the run's cwd)
import os, pty, select, sys, time, re, fcntl, termios, struct

JAB, WT = sys.argv[1], sys.argv[2]
ENV = dict(os.environ, ASAN_OPTIONS="detect_leaks=0")
ANSI = re.compile(rb"\x1b\[[0-9;<>?]*[a-zA-Z@]|\x1b[()][A-B0-9]|\x1b[=>]|\x1b\][^\x07]*\x07")

fails = 0
def check(name, cond, extra=""):
    global fails
    print(("ok   " if cond else "FAIL ") + name + (("  " + extra) if not cond else ""))
    if not cond: fails += 1

def start(args, rows=24, cols=100):
    pid, fd = pty.fork()
    if pid == 0:
        os.chdir(WT)
        for k, v in ENV.items(): os.environ[k] = v
        os.execv(JAB, [JAB] + args)
        os._exit(127)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    return pid, fd

def sip(fd, secs=3.0):
    out, deadline = b"", time.time() + secs
    while time.time() < deadline:
        r, _, _ = select.select([fd], [], [], 0.3)
        if fd in r:
            try: chunk = os.read(fd, 1 << 16)
            except OSError: break
            if not chunk: break
            out += chunk
        elif out:
            break
    return ANSI.sub(b"", out).decode("utf8", "replace")

def stop(pid, fd):
    try: os.kill(pid, 9)
    except OSError: pass
    try: os.waitpid(pid, 0)
    except ChildProcessError: pass
    try: os.close(fd)
    except OSError: pass

def press(fd, row, col):
    os.write(fd, ("\x1b[<0;%d;%dM" % (col, row)).encode())

def rowof(frame, key):
    for i, line in enumerate(frame.split("\n")):
        if key in line: return i + 1, line
    return -1, ""

def readfile(rel):
    try:
        with open(os.path.join(WT, rel)) as fh: return fh.read()
    except OSError: return None

#  --- the button is painted, on a wt-LESS `Rep:` row --------------------------
pid, fd = start(["todo", "GO"])
board = sip(fd)
r1, line1 = rowof(board, "GO-001")
check("go-painted", "[go]" in line1, repr(board[:400]))
check("rep-less-row-has-no-go", "[go]" not in rowof(board, "GO-002")[1],
      repr(rowof(board, "GO-002")[1]))
check("no-worktree-yet", not os.path.isdir(os.path.join(WT, "work", "GO-001")))

#  the face is the 2 cells inside the dim brackets; columns are 1-based.
col = line1.index("[go]") + 2
press(fd, r1, col)
after = sip(fd)
stop(pid, fd)

#  THE assertion: the click MINTED the worktree.  Everything else is evidence.
wtdir = os.path.join(WT, "work", "GO-001")
check("click-minted-the-worktree", os.path.isdir(wtdir),
      "no work/GO-001 — the frame said: " + repr(after[-400:]))
check("click-anchored-the-worktree", os.path.exists(os.path.join(wtdir, ".be")),
      "work/GO-001 carries no `.be` anchor")
#  TRAP B: `Rep: ///sub` carries NO trailing slash, so a verbatim clone lands on
#  the parent's DE-JURE gitlink pin (s1).  The live rev is s2.
check("click-cloned-the-LIVE-rev", readfile("work/GO-001/f.txt") == "s2\n",
      "f.txt reads %r — want 's2\\n' (s1 = the stale parent pin)"
      % (readfile("work/GO-001/f.txt"),))
#  a mutation runs IN PLACE (BE-041): the board is still the view underneath.
check("click-stayed-on-the-board", "GO-001" in after and "GO-002" in after,
      repr(after[:300]))

print("DONE" if fails == 0 else "FAILS=%d" % fails)
sys.exit(1 if fails else 0)
