#!/usr/bin/env python3
# BRO-034 loading state, through the REAL UI path.  Runs the FULL `jab ls` pager
# on a controlling pty (pty.fork, the bro/ci kin), types real keystrokes, and
# reads the frames back — no unit probe, no internal call.
#   argv[1] = jab binary   argv[2] = the fixture worktree (cwd for the jsrc-scan)
# The fixture holds a few thousand text files, so `grep:#needle` takes a couple
# hundred ms IN PROCESS and the yellow bar is observable MID-LOAD.
import fcntl, os, pty, select, struct, sys, termios, time

JAB = sys.argv[1]
WT = sys.argv[2]
ROWS, COLS = 24, 80

# The pager writes the loading bar as "go to the last row" + the banner band
# (view/theme.js BANNER_SGR, black on pale yellow).  The cursor-address prefix is
# what makes it UNMISTAKABLE: a hunk banner inside a frame wears the same colour
# pair but is never preceded by ESC[24;1H.
MARK = b"\x1b[%d;1H\x1b[38;5;0;48;5;230m" % ROWS
NORM = b"\x1b[7m"                                  # the ordinary inverse bar
CLR = b"\x1b[2J"                                   # a fresh frame starts here

pid, fd = pty.fork()
if pid == 0:
    os.chdir(WT)
    os.environ["ASAN_OPTIONS"] = "detect_leaks=0"
    os.execv(JAB, [JAB, "ls"])
    os._exit(127)
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLS, 0, 0))

buf = b""


def pump(seconds):
    global buf
    end = time.time() + seconds
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.005)
        if fd in r:
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                return
            if not chunk:
                return
            buf += chunk


def wait_for(needle, seconds):
    end = time.time() + seconds
    while time.time() < end:
        if needle in buf:
            return True
        pump(0.02)
    return needle in buf


def send(s):
    os.write(fd, s.encode())


fails = 0


def check(name, cond):
    global fails
    print(("ok   " if cond else "FAIL ") + name)
    if not cond:
        fails += 1
        print("     --- frames ---")
        print("     " + repr(buf[-900:]))


def last_frame():
    return buf.rsplit(CLR, 1)[-1]


def load(spell, budget=20.0):
    """Type a spell, then watch for the loading bar WHILE the verb runs.
    Returns (saw_mark_mid_load, settled_ok) — settled_ok means the frame that
    arrived afterwards carries the ORDINARY bar and no leftover yellow."""
    global buf
    buf = b""
    send(spell + "\r")
    mid = False
    end = time.time() + budget
    while time.time() < end:
        if MARK in buf:
            #  MID-LOAD iff no frame has been painted since the yellow bar —
            #  the verb is still running and the terminal is showing yellow.
            if CLR not in buf.split(MARK)[-1]:
                mid = True
            break
        pump(0.01)
    pump(1.5)                                      # let the view land + settle
    fr = last_frame()
    return mid, (MARK not in fr and NORM in fr)


check("pager-entered", wait_for(NORM, 8))
check("no-yellow-bar-at-rest", MARK not in buf)

# --- a SLOW load: the yellow bar must be on screen while the verb runs -------
mid, settled = load(":grep #needle")
check("slow-load-paints-yellow-mid-load", mid)
check("slow-load-clears-on-arrival", settled)

# --- R refresh re-runs the same view: paints too ----------------------------
buf = b""
send("R")
check("refresh-paints-yellow", wait_for(MARK, 20))
pump(1.5)
check("refresh-clears-on-arrival", MARK not in last_frame() and NORM in last_frame())

# --- `-` back REPLAYS the previous view: paints too -------------------------
buf = b""
send("-")
check("back-paints-yellow", wait_for(MARK, 20))
pump(1.0)
check("back-clears-on-arrival", MARK not in last_frame() and NORM in last_frame())

# --- the NO-HUNKS path: painted, then cleared with the note -----------------
mid, settled = load(":grep #zzqqnosuchbodyzz")
check("no-hunks-paints-yellow", mid or MARK in buf)
check("no-hunks-clears-the-bar", settled)
check("no-hunks-note-shows", b"no hunks:" in buf)

# --- the ERROR path: painted, then cleared with the error -------------------
mid, settled = load(":cat zzz-no-such-file.txt")
check("error-paints-yellow", mid or MARK in buf)
check("error-clears-the-bar", settled)

# --- Enter FOLLOWS the row's URI (the click/nav drive site) -----------------
buf = b""
send("\r")
check("follow-paints-yellow", wait_for(MARK, 20))
pump(1.0)
check("follow-clears-on-arrival", MARK not in last_frame() and NORM in last_frame())

send("q")
pump(1.0)
try:
    os.close(fd)
except OSError:
    pass
try:
    os.waitpid(pid, 0)
except (ChildProcessError, OSError):
    pass

print("DONE" if fails == 0 else "FAILS=%d" % fails)
sys.exit(1 if fails else 0)
