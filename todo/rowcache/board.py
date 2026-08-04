#!/usr/bin/env python3
# TODO-006 pty driver — the REAL UI path: ONE live `jab todo` board in the
# universal pager (isatty(1)), re-fired by keystrokes only, with the watcher
# live for exactly as long as the pager loop is:
#   #1 the cold board             -> every block MISSES and fills the row cache
#   THE FIELD GESTURE (gritzko 2026-08-04): click a ticket, BACKSPACE back —
#      popView + _refresh IS the FIRST re-fire, and it must HIT.  Before the fix
#      the watcher only started AFTER the cold render, so that first re-fire
#      recomputed the whole board (field: 7.7 s, drops=1) and the gesture felt
#      no faster at all.
#   a file written under ONE wt   -> that row alone repaints
#   a POST to the tracked upstream from another process -> the ahbeh column
#      moves on every tracking row while the file frames stay put
#   `R` (the refresh key)         -> bumpRoot: the full board again, identically
# Each re-fire is an in-process re-entry, so loop.js prints the CFOLD-001
# `stats: obj=…` line to fd 2 — the pty reads those cumulative counters and the
# DELTAS are what say a re-fire did the work or skipped it.
#   argv[1]=jab  argv[2]=the project root (the pager's cwd)
import os, pty, re, select, struct, subprocess, sys, time
import fcntl, termios

sys.stdout.reconfigure(line_buffering=True)
JAB, WT = sys.argv[1], sys.argv[2]
ENV = dict(os.environ, ASAN_OPTIONS="detect_leaks=0", JAB_STATS="1")
ANSI = re.compile(rb"\x1b\[[0-9;<>?]*[a-zA-Z@]|\x1b[()][A-B0-9]|\x1b[=>]|\x1b\][^\x07]*\x07|\r")

fails = 0
def check(name, cond, extra=""):
    global fails
    print(("ok   " if cond else "FAIL ") + name + (("  " + extra) if not cond else ""))
    if not cond: fails += 1

pid, fd = pty.fork()
if pid == 0:
    os.chdir(WT)
    for k, v in ENV.items(): os.environ[k] = v
    os.execv(JAB, [JAB, "todo"])
    os._exit(127)
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 200, 0, 0))

OBJ = 0                                  # the last `stats: obj=` seen
RAW = b""                                # the last sip's RAW bytes (frames intact)
def sip(secs=2.5):
    global RAW
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
    RAW = out
    return ANSI.sub(b"", out).decode("utf8", "replace")

#  The pager REPAINTS on every keystroke, so a sip holds several whole frames.
#  Screen coordinates only mean anything in the LAST one — split on its clear.
def frame_lines():
    i = RAW.rfind(b"\x1b[2J")
    chunk = RAW[i:] if i >= 0 else RAW
    txt = ANSI.sub(b"", chunk).decode("utf8", "replace")
    return txt.replace("\r\n", "\n").replace("\r", "\n").split("\n")

def objs(frame):
    """the CUMULATIVE object-read counter this re-fire printed (fd 2), or None"""
    ms = re.findall(r"stats: obj=(\d+)", frame)
    return int(ms[-1]) if ms else None

def keys(s, secs=2.5):
    os.write(fd, s.encode()); return sip(secs)
def press(row, col):
    os.write(fd, ("\x1b[<0;%d;%dM" % (col, row)).encode()); return sip()

#  the painted ROWS — the bullet-led ticket lines, minus the pager's own chrome
#  (its command echo and the JAB_STATS lines this harness turned on).
def rows(frame):
    return [l.rstrip() for l in frame.split("\n") if l.lstrip().startswith(("●", "○"))]
def rowof(frame, key):
    for l in rows(frame):
        if key in l: return l
    return ""
def half(l, sigil):
    i = l.find(sigil)
    return "" if i < 0 else l[i:l.find("]", i) + 1]

t0 = time.time()
f1 = sip(4.0)                                   # #1 the cold board
cold_s = time.time() - t0
check("board-painted", len(rows(f1)) == 5, repr(rows(f1)[:2]))
check("board-has-frames", "[ i" in f1 and "[ ≡" in f1, repr(rows(f1)[:1]))

#  --- THE FIELD GESTURE: click a ticket, BACKSPACE back ----------------------
#  Bare `todo` is the topic-headered board: screen row 1 is the banner, 2 `BUG`,
#  3 BUG-001, 4 BUG-002, 5 `TIC`, 6 TIC-001.  Its rows indent by 2, so the key
#  spans columns 5-11 (2 indent + `●` 3 + ` ` 4).
f2 = press(6, 7)
check("click-opened-the-ticket-page", "the first ticket" in f2, repr(f2[:300]))
check("click-carried-the-right-ticket", "TIC-001" in f2 and "TIC-002" not in f2,
      repr(f2[:300]))
CLICK = objs(f2)              # the counter as the page view left it
t0 = time.time()
f3 = keys("\x7f")                               # BACKSPACE: popView + _refresh
back_s = time.time() - t0
check("backspace-came-back-to-the-board", len(rows(f3)) == 5, repr(rows(f3)[:2]))
check("the-first-re-fire-repaints-identically", rows(f3) == rows(f1),
      repr((rows(f1)[:2], rows(f3)[:2])))
FIRST = objs(f3)
print("   gesture: cold %.2fs -> first re-fire %.2fs (obj %s -> %s)"
      % (cold_s, back_s, CLICK, FIRST))

#  The next re-fire with nothing changed is the FLOOR — and the gesture's OWN
#  delta (click counter -> gesture counter) has to sit at that floor.  That IS
#  "the first re-fire hits": before the fix it cost a whole cold board more.
f4 = keys(":todo\r")
WARM = objs(f4)

#  --- a write under ONE wt repaints THAT row only -----------------------------
before = rowof(f4, "BUG-001")
with open(os.path.join(WT, "work/BUG-001/pty-new.txt"), "w") as fh:
    fh.write("hello\n")
time.sleep(0.4)
f5 = keys(":todo\r")
ONEROW = objs(f5)
check("the-touched-row-repainted", rowof(f5, "BUG-001") != before,
      repr((before, rowof(f5, "BUG-001"))))
check("…showing-the-new-untracked-file", "+1" in rowof(f5, "BUG-001"),
      repr(rowof(f5, "BUG-001")))
check("every-other-row-is-unchanged",
      [l for l in rows(f5) if "BUG-001" not in l] ==
      [l for l in rows(f4) if "BUG-001" not in l],
      repr((rows(f4), rows(f5))))

#  --- a POST to the tracked UPSTREAM: the ahbeh column only -------------------
#  Another process pushes TIC-002's commit into the shared store, so the tip
#  every wt tracks moves.  No file under TIC-001 changes: its FILE frame must
#  come back byte-identical while its COMMIT frame picks up the new count.
fbefore = half(rowof(f5, "TIC-001"), "[ i")
subprocess.run([JAB, "post"], cwd=os.path.join(WT, "work/TIC-002"),
               env=ENV, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(0.4)
f6 = keys(":todo\r")
POSTED = objs(f6)
check("the-upstream-post-moved-the-ahbeh-column",
      "-1" in rowof(f6, "TIC-001"), repr(rowof(f6, "TIC-001")))
check("…while-the-FILE-frame-stayed-byte-identical",
      half(rowof(f6, "TIC-001"), "[ i") == fbefore,
      repr((fbefore, half(rowof(f6, "TIC-001"), "[ i"))))

#  --- TODO-007: EVERY button of the FILE frame, clicked by SCREEN CELL --------
#  The field bug: clicking a lit count staged nothing and threw the view to the
#  TOP.  Key-nav coverage never touched these — they sit deep in the row behind
#  several hidden `O` runs.  One wt is made dirty in BOTH classes so the `~`
#  (changed → bare `put`) and `+` (untracked → `put +`) buttons are both lit.
with open(os.path.join(WT, "work/TIC-001/src/f1.txt"), "w") as fh:
    fh.write("clicked\n")                       # a TRACKED file, now modified
time.sleep(0.4)
f7 = keys(":todo\r")
row7 = rowof(f7, "TIC-001")
check("the-row-lights-both-classes", "~" in half(row7, "[ i") and "+" in half(row7, "[ i"),
      repr(row7))

def cellof(frame, key, sigil):
    """1-based (screen row, column) of a face inside the row's FILE frame,
    read off the LAST painted frame (screen coordinates live only there)"""
    for i, l in enumerate(frame_lines()):
        if key not in l: continue
        m = re.search(r"\[ i[^\]]*\][^\]]*\]", l)     # BOTH frames, one span
        if not m: continue
        c = l.find(sigil, m.start(), m.end())
        if c < 0: return None
        return (i + 1, c + 1)
    return None

def staged(wt):
    """the target worktree's own `be status`, read from ANOTHER process"""
    p = subprocess.run([JAB, "status", "--plain"], cwd=os.path.join(WT, "work", wt),
                       env=ENV, capture_output=True, text=True)
    return p.stdout

def isStaged(wt, path):
    """True iff `path`'s status letters are the STAGED (upper) case — the row is
    listed either way, so the presence of the name proves nothing."""
    for l in staged(wt).split("\n"):
        f = l.split()
        if len(f) >= 2 and f[-1] == path:
            return any(c.isupper() for c in f[-2])
    return False

#  the `~` button: bare `put` in the row's OWN worktree, in place
cell = cellof(f7, "TIC-001", "~")
check("the-~-count-face-was-located-on-screen", cell is not None, repr(row7))
if cell:
    f8 = press(cell[0], cell[1])
    check("the-~-click-STAGED-the-changed-file", isStaged("TIC-001", "src/f1.txt"),
          repr(staged("TIC-001")[:220]))
    check("…with-no-err-in-the-bar", "err:" not in f8, repr(f8[-120:]))
    #  CI-004: the commit ✓ is the HISTORY surface's last slot — it lights in the
    #  `[ ≡` frame while ANY row is staged, not in the `[ i` staging frame (whose
    #  last slot is the ` ∞` run button).
    check("…and-the-row-grew-the-staged-tick", "✓" in half(rowof(f8, "TIC-001"), "[ ≡"),
          repr(rowof(f8, "TIC-001")))
#  the `+` button: `put +` stages the untracked file of the SAME row
cell = cellof(keys(":todo\r"), "TIC-001", "+")
if cell:
    f9 = press(cell[0], cell[1])
    check("the-+-click-STAGED-the-untracked-file", isStaged("TIC-001", "fresh.txt"),
          repr(staged("TIC-001")[:220]))
    check("…with-no-err-in-the-bar", "err:" not in f9, repr(f9[-120:]))
#  THE regression: a wholly STAGED count is info, not a button — its `O` carries
#  a colour and NO spell.  The click must be INERT (nothing pushed, scroll kept),
#  never the old fall-through that re-followed the board and jumped to the top.
fA = keys(":todo\r")
QUIET = objs(fA)                           # the counter before the inert click
cell = cellof(fA, "TIC-001", "~")
check("the-staged-count-is-still-painted", cell is not None, repr(rowof(fA, "TIC-001")))
if cell:
    fB = press(cell[0], cell[1])
    check("an-ALREADY-STAGED-count-click-says-so-in-the-bar",
          "nothing to click" in fB, repr(fB[-160:]))
    #  and it RAN NOTHING: the old fall-through re-followed the board banner,
    #  which re-fires the verb (a fresh `stats:` line) and lands at the top.
    check("…and-re-fired-NO-verb: the click was inert",
          objs(fB) is None or objs(fB) == QUIET, repr((QUIET, objs(fB))))
#  the two VIEW buttons of the frames, same row, same hidden-run depth
cell = cellof(keys(":todo\r"), "TIC-001", "i")
if cell:
    fD = press(cell[0], cell[1])
    check("the-status-button-opened-its-worktree", "status" in fD, repr(fD[:160]))
    keys("\x7f")
cell = cellof(keys(":todo\r"), "TIC-001", "≡")
check("the-log-face-was-located-in-the-COMMIT-frame", cell is not None)
if cell:
    fE = press(cell[0], cell[1])
    check("the-log-button-opened-its-worktree", "log" in fE or "post" in fE, repr(fE[:160]))
    keys("\x7f")

#  the `-` (del) button: a tracked file REMOVED lights it, and the click stages
#  the deletion.  The remaining frame buttons (the ci tick, and the ahbeh
#  post/get/patch pair) drive COMMITS and the wire — painted and asserted, never
#  clicked from a test.
os.remove(os.path.join(WT, "work/TIC-001/src/f2.txt"))
time.sleep(0.4)
fF = keys(":todo\r")
check("the-removed-file-lights-the-del-count", "-1" in half(rowof(fF, "TIC-001"), "[ i"),
      repr(rowof(fF, "TIC-001")))
cell = cellof(fF, "TIC-001", "-")
if cell:
    fG = press(cell[0], cell[1])
    check("the---click-STAGED-the-deletion", isStaged("TIC-001", "src/f2.txt"),
          repr(staged("TIC-001")[:220]))
    check("…with-no-err-in-the-bar", "err:" not in fG, repr(fG[-120:]))

fPre = keys(":todo\r")                          # the board as it stands now
fR = keys("R")                                  # the refresh key: bumpRoot
FULL = objs(fR)
check("R-repaints-identically", rows(fR) == rows(fPre) or rows(keys(":todo\r")) == rows(fPre),
      repr((rows(fPre)[:2], rows(fR)[:2])))
#  THE quantitative claim: `R` drops every block and pays the full board, so its
#  delta is the yardstick — a warm re-fire, the one-row repaint and the upstream
#  post must each cost a fraction of it.
if None not in (CLICK, FIRST, WARM, ONEROW, POSTED, FULL):
    dFirst, dWarm = FIRST - CLICK, WARM - FIRST
    dRow, dPost, dFull = ONEROW - WARM, POSTED - ONEROW, FULL - POSTED
    print("   obj deltas: FIRST(gesture)=%d warm=%d one-row=%d upstream-post=%d R(full)=%d"
          % (dFirst, dWarm, dRow, dPost, dFull))
    #  THE bug this ticket was re-opened for: the gesture's re-fire used to pay a
    #  whole board.  It must now sit at the warm floor, not near `R`'s full cost.
    check("THE FIELD GESTURE: the FIRST re-fire hits (warm-floor work, not a board)",
          dFirst * 4 < dFull, repr((dFirst, dWarm, dFull)))
    check("a warm re-fire costs a fraction of a full board", dWarm * 4 < dFull,
          repr((dWarm, dFull)))
    check("an upstream post costs a fraction of a full board", dPost * 2 < dFull,
          repr((dPost, dFull)))

os.write(fd, b"q")
tail = sip(2.0)
try: os.waitpid(pid, 0)
except ChildProcessError: pass
try: os.close(fd)
except OSError: pass

m = re.search(r"cache: hits=(\d+) misses=(\d+) drops=(\d+) dirs=(\d+)", tail)
check("the pager reported its rev-tree line", m is not None, repr(tail[-200:]))
if m:
    hits, misses, drops, dirs = (int(x) for x in m.groups())
    print("   cache: hits=%d misses=%d drops=%d dirs=%d" % (hits, misses, drops, dirs))
    check("the warm re-fires found revs STANDING STILL (hits>0)", hits > 0)
    check("the write and `R` DROPPED (drops>=2)", drops >= 2)
    check("the walk armed real dirs (dirs>=1)", dirs >= 1)

print("todo/rowcache pty done" if fails == 0 else "todo/rowcache pty FAILS: %d" % fails)
sys.exit(1 if fails else 0)
