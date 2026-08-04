#!/usr/bin/env python3
# status/okay-btn pty driver.  Forks a pty, execs the REAL `jab status` in it
# (isatty(1) -> the universal bro pager, JAB-030), reads the painted frame, feeds
# a real SGR left-press report at the cell the `[okay]` button paints on, and
# reads the repainted frame back.  The evidence is the PAINTED FRAME flipping —
# the pager is arg-blind, so the click can only have driven the row's hidden `O`
# spell and let the `put` VERB resolve the arg (BE-039).
#
# What this pins (gritzko's order, 2026-08-04):
#   * a CONFLICTED row carries `[okay]`; a mod row keeps `[put]`; a clean file
#     paints no row at all, so it can carry no button;
#   * `[okay]` wears the same paint as `[put]` — it is the same act;
#   * a click on it runs `put <path>` and REFRESHES the status view in place
#     (BE-041: a mutation verb never pushes a result screen);
#   * the row flips `...!` -> staged, the summary loses its `con` tally, and the
#     wtlog grows a `put f.txt` row AFTER the `con f.txt` row (DIS-080 §4: that
#     row order is what acks the conflict).
#   argv[1] = jab binary   argv[2] = the fixture worktree (the run's cwd)
import os, pty, select, sys, time, re, fcntl, termios, struct

JAB, WT = sys.argv[1], sys.argv[2]
ENV = dict(os.environ, ASAN_OPTIONS="detect_leaks=0")
#  Strip the SGR/cursor control bytes so an assertion reads the painted TEXT.
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
    #  A known window: the pager lays rows out against it, so the click cell is
    #  known too (and 100 columns keeps the short fixture rows unwrapped).
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    return pid, fd

RAW = {"last": b""}
def sip(fd, secs=3.0):
    """Read one settled frame: drain until the child goes quiet for a beat."""
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
    RAW["last"] = out
    return ANSI.sub(b"", out).decode("utf8", "replace")

#  The SGR parameters of the escape IMMEDIATELY before `needle` — "" when the
#  cell just continues the previous run (same colour), None when absent.
def sgr_before(raw, needle):
    i = raw.find(needle)
    if i < 0: return None
    m = re.search(rb"\x1b\[([0-9;]*)m$", raw[:i])
    return m.group(1).decode() if m else ""

def stop(pid, fd):
    try: os.kill(pid, 9)
    except OSError: pass
    try: os.waitpid(pid, 0)
    except ChildProcessError: pass
    try: os.close(fd)
    except OSError: pass

def press(fd, row, col):
    os.write(fd, ("\x1b[<0;%d;%dM" % (col, row)).encode())

def lines(frame): return frame.split("\n")
def rowof(frame, needle):
    """1-based SCREEN row of the first line carrying `needle` (-1 if absent)."""
    for i, l in enumerate(lines(frame)):
        if needle in l: return i + 1
    return -1
def lineof(frame, needle):
    for l in lines(frame):
        if needle in l: return l
    return ""
def readfile(rel):
    try:
        with open(os.path.join(WT, rel)) as fh: return fh.read()
    except OSError as e:
        check("readable-" + rel, False, str(e)); return ""

#  --- 1.  the button paints on the CONFLICTED row, and only there -------------
pid, fd = start(["status"])
base = sip(fd)
frow = rowof(base, "f.txt")
check("status-frame-painted", frow > 0 and "mod.txt" in base, repr(base[:300]))
check("okay-on-the-conflicted-row", "[okay]" in lineof(base, "f.txt"),
      repr(lineof(base, "f.txt")))
check("put-still-on-the-mod-row", "[put]" in lineof(base, "mod.txt"),
      repr(lineof(base, "mod.txt")))
check("no-okay-on-the-mod-row", "[okay]" not in lineof(base, "mod.txt"),
      repr(lineof(base, "mod.txt")))
#  a clean file paints NO row, so it can carry no button (the button lives in
#  the file-bucket loop and `ok` rows never reach it).
check("no-row-for-the-clean-file", "ok.txt" not in base, repr(base[:300]))
check("exactly-one-okay-button", base.count("[okay]") == 1, repr(base.count("[okay]")))

#  `[okay]` IS `[put]` — same act, so the same paint.  Asserted as a comparison
#  against the row beside it, not a hardcoded SGR: whichever slot the put button
#  wears, the okay button wears it too.
sg_okay = sgr_before(RAW["last"], "[okay]".encode())
sg_put  = sgr_before(RAW["last"], "[put]".encode())
check("okay-button-is-painted", sg_okay not in (None, ""), repr(sg_okay))
check("okay-button-wears-the-put-paint", sg_okay == sg_put, repr((sg_okay, sg_put)))

#  --- 2.  the click stages the resolution -------------------------------------
#  The face IS the click zone; `[okay]` opens right after the path, so take its
#  column off the painted line (1-based, glyph-per-cell once SGR is stripped).
#  RED-first: with no button on the row there is nothing to click, so say so
#  once and stop — the remaining names would all be noise.
if "[okay]" not in lineof(base, "f.txt"):
    stop(pid, fd)
    check("okay-click-runs-put", False, "no [okay] button to click (RED)")
    print("FAILS=%d" % fails); sys.exit(1)
col = lineof(base, "f.txt").index("[okay]") + 2      # a cell INSIDE the label
before_log = readfile(".be/wtlog")
check("wtlog-has-no-put-yet", "\tput\tf.txt" not in before_log.split("\tcon\tf.txt")[-1],
      "a put row already follows the con row — the fixture is not RED")

press(fd, frow, col)
after = sip(fd)
stop(pid, fd)

#  BE-041: `put` is a mutation verb — it runs and the CURRENT view refreshes in
#  place.  So the frame we read back is still the status view, minus the button.
check("okay-click-stayed-in-status", "mod.txt" in after and "[put]" in after,
      repr(after[:300]))
check("okay-click-cleared-the-okay-button", "[okay]" not in after, repr(after[:300]))
check("okay-click-flipped-the-row", "f.txt" in after and "1 staged" in after,
      repr(after[:300]))
check("okay-click-cleared-the-con-tally", "con" not in lineof(after, "staged"),
      repr(lineof(after, "staged")))

#  DIS-080 §4: the ack is the ROW ORDER — a `put` row LATER than the `con` row.
log = readfile(".be/wtlog")
check("okay-click-wrote-the-put-row", "\tput\tf.txt" in log, repr(log[-200:]))
check("okay-click-put-row-follows-the-con-row",
      log.rfind("\tput\tf.txt") > log.rfind("\tcon\tf.txt"),
      repr(log[-200:]))
#  the bytes staged are the ones on disk RIGHT NOW (the user's resolution), not
#  either merge side.
check("resolution-bytes-on-disk", readfile("f.txt") == "a\nXY\nc\n", repr(readfile("f.txt")))

print("DONE" if fails == 0 else "FAILS=%d" % fails)
sys.exit(1 if fails else 0)
