#!/usr/bin/env python3
# CI-004: the BOARD's ` ∞` button and the `ci` VIEW it pushes, through the REAL
# UI path.  Runs the real `jab todo` on a pty, finds the button on the painted
# frame, presses it with a real SGR left-press report, and reads the frames back.
# What it pins (ruling 2026-08-04):
#   - the click PUSHES the ci view: the address bar shows the plain view spell
#     and the hunk banner shows the detected COMMAND LINE;
#   - the tail is positioned at the END (a >1-screen log opens on its last page);
#   - the tail GROWS WITH NO KEYPRESSES while the job appends (the ~1s tick);
#   - `r` re-reads and re-tails;
#   - the settle swaps `⋯ running` for the toned `── PASS rc=0 ──` footer, with
#     no keypress, and the ticking STOPS there (no further repaints);
#   - BACKSPACE pops back to the board.
#   argv[1] = jab binary   argv[2] = the fixture tree (cwd)
import fcntl, os, pty, select, struct, sys, termios, time

JAB, WT = sys.argv[1], sys.argv[2]

pid, fd = pty.fork()
if pid == 0:
    os.chdir(WT)
    os.environ["ASAN_OPTIONS"] = "detect_leaks=0"
    os.execv(JAB, [JAB, "todo", "CIB"])
    os._exit(127)
# A DETERMINISTIC window: the fixture log is longer than one screen, which is
# what makes "positioned at the end" observable at all.
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))

RAW = {"last": b"", "all": b""}


def pump(seconds):
    """Drain for `seconds`; returns the bytes read in this call."""
    got, end = b"", time.time() + seconds
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.1)
        if fd in r:
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                break
            if not chunk:
                break
            got += chunk
    if got:
        RAW["last"] = got
        RAW["all"] += got
    return got


def frame(quiet=0.6, budget=8.0):
    """Read until the child goes quiet for a beat, then return ALL of it."""
    buf, end, last = b"", time.time() + budget, time.time()
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.1)
        if fd in r:
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                break
            if not chunk:
                break
            buf += chunk
            last = time.time()
        elif buf and time.time() - last > quiet:
            break
    if buf:
        RAW["last"] = buf
        RAW["all"] += buf
    return buf


def strip(b):
    out, i = [], 0
    s = b.decode("utf-8", "replace")
    while i < len(s):
        if s[i] == "\x1b" and i + 1 < len(s) and s[i + 1] == "[":
            j = i + 2
            while j < len(s) and not s[j].isalpha():
                j += 1
            i = j + 1
            continue
        out.append(s[i])
        i += 1
    return "".join(out)


def screen(b):
    """The LAST complete frame in `b` — the pager clears + repaints per frame."""
    parts = b.split(b"\x1b[2J")
    return strip(parts[-1] if len(parts) > 1 else b)


def press(row, col):
    os.write(fd, ("\x1b[<0;%d;%dM" % (col, row)).encode())
    os.write(fd, ("\x1b[<0;%d;%dm" % (col, row)).encode())


def until(pred, seconds):
    """Repaint-driven wait: keep draining until pred(last screen) or timeout."""
    end = time.time() + seconds
    while time.time() < end:
        if pred(screen(RAW["last"])):
            return True
        pump(0.2)
    return pred(screen(RAW["last"]))


fails = 0


def check(name, cond, extra=""):
    global fails
    print(("ok   " if cond else "FAIL ") + name + ("  " + extra if not cond else ""))
    if not cond:
        fails += 1


board = strip(frame())
check("board-painted", "CIB-001" in board, repr(board[:300]))
# The ruling's layout: the ∞ ends the FILE frame, the ✓ ends the COMMIT frame.
check("run-button-at-the-file-frame-end", "  ∞]" in board, repr(board[:400]))
check("commit-frame-ends-in-the-check", "✓]" in board or " ≡" in board,
      repr(board[:400]))
# TODO 11: this tree never ran, so the button wears the NEVER-RAN grey (#808080)
# over its derived pale wash — not a slot colour, the remembered verdict.
check("never-ran-button-is-grey", b"38;2;128;128;128" in RAW["last"],
      repr(RAW["last"][:200]))

# --- find the ∞ cell and press it ------------------------------------------
row = col = None
for i, line in enumerate(board.split("\n")):
    if "∞" in line and "CIB-001" in line:
        row, col = i + 1, line.index("∞") + 1
        break
check("run-button-located", row is not None, repr(board[:400]))
if row is None:
    print("FAILS=%d" % max(fails, 1))
    sys.exit(1)

press(row, col)
after = strip(frame())
# The click PUSHED a view — the address bar carries the plain view spell (the
# board mints `ci //CIB-001`, the wt as the ARG exactly as the ` i`/` ≡` buttons
# do, and BRO-024 paints it context-relative once the click has navigated).
check("bar-shows-the-view-spell", "//CIB-001/: ci" in after, repr(after[-400:]))
# ...whose BANNER is the detected command line.
check("banner-is-the-command-line", "./ci.sh" in after, repr(after[:400]))

# --- the tail: at the END, and growing with NO keystrokes -------------------
# The fixture prints 60 seed lines (more than one 24-row screen) and then one
# `grow NN` line a second, so both properties are observable on the screen.
check("tail-positioned-at-the-end",
      until(lambda s: "seed 59" in s and "seed 00" not in s, 6),
      repr(screen(RAW["last"])[:600]))
# THE TICK: no key is sent between here and the next check.
before = screen(RAW["last"])
check("tail-grows-with-no-keypress", until(lambda s: "grow 03" in s, 8),
      "before=" + repr(before[-200:]) + " now=" + repr(screen(RAW["last"])[-200:]))
check("running-footer", "⋯ running" in screen(RAW["last"]),
      repr(screen(RAW["last"])[-300:]))

# `r` re-reads and re-tails through the same path (the banner is off the top of
# a tailing screen — what `r` puts on the bar is its own word).
os.write(fd, b"r")
check("r-refreshes", until(lambda s: "refreshed" in s and "grow" in s, 5),
      repr(screen(RAW["last"])[-400:]))

# --- the settle: the toned PASS footer arrives unprompted -------------------
check("verdict-footer-unprompted", until(lambda s: "── PASS rc=0 ──" in s, 20),
      repr(screen(RAW["last"])[-400:]))
# TODO 11: PASS wears the ok tone #1fe033 (the same the board button reads).
check("footer-wears-the-verdict-tone", b"38;2;31;224;51" in RAW["last"],
      repr(RAW["last"][-300:]))
# ...and the ticking STOPS with it: a settled view wakes the pager no more.
pump(0.8)                                   # let the last repaint drain
quiet = pump(2.5)
check("tick-stops-after-the-settle", quiet == b"", repr(quiet[:200]))

# --- BACKSPACE pops back to the board ---------------------------------------
os.write(fd, b"\x7f")
back = strip(frame())
check("backspace-pops-to-the-board", "CIB-001" in back and "[ i" in back,
      repr(back[:400]))
# TODO 11: the landed verdict tints the button ok-green.
check("board-button-wears-the-verdict", b"38;2;31;224;51" in RAW["last"],
      repr(RAW["last"][:400]))

os.write(fd, b"q")
frame(0.3, 2.0)
try:
    os.close(fd)
except OSError:
    pass
try:
    os.waitpid(pid, 0)
except (ChildProcessError, OSError):
    pass

# --- TODO 11: the verdict survives a FRESH pager process --------------------
# A second `jab todo CIB`, nothing live in it: the button colour is read COLD
# off the {wt: status} map beside the logs — no watcher, no memo, no run.
pid2, fd2 = pty.fork()
if pid2 == 0:
    os.chdir(WT)
    os.environ["ASAN_OPTIONS"] = "detect_leaks=0"
    os.execv(JAB, [JAB, "todo", "CIB"])
    os._exit(127)
fcntl.ioctl(fd2, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
fd = fd2                                     # frame()/pump() read the new pty
cold = frame()
check("verdict-survives-a-fresh-process", b"38;2;31;224;51" in cold,
      repr(strip(cold)[:400]))
os.write(fd2, b"q")
frame(0.3, 2.0)
try:
    os.close(fd2)
except OSError:
    pass
try:
    os.waitpid(pid2, 0)
except (ChildProcessError, OSError):
    pass

print("DONE" if fails == 0 else "FAILS=%d" % fails)
sys.exit(1 if fails else 0)
