#!/usr/bin/env python3
# BRO-046: the IDLE pager's mapping census, through the REAL UI path.  Runs the
# FULL `jab log` pager on a controlling pty (pty.fork, the bro/ci civ.py kin),
# sends NO keystrokes at all, and counts the lines of /proc/<pid>/maps across an
# idle window.  The 100 ms key-wait spin used to re-resolve the ci badge's
# context worktree every pass — two `.be` mmaps per pass, never unmapped — so
# the count climbed ~19/s until vm.max_map_count wedged the process.
#   argv[1] = jab binary   argv[2] = the fixture worktree (cwd for the jsrc-scan)
import os, pty, select, sys, time

JAB = sys.argv[1]
WT  = sys.argv[2]
ENV = dict(os.environ, ASAN_OPTIONS="detect_leaks=0")

SETTLE = 2.0        # let the first frame + the first resolution land
WINDOW = 6.0        # the IDLE window the census spans
BUDGET = 8          # allowed growth over the window (RED is ~19 `.be` maps/s)

pid, fd = pty.fork()
if pid == 0:
    os.chdir(WT)
    for k, v in ENV.items(): os.environ[k] = v
    os.execv(JAB, [JAB, "log"])
    os._exit(127)

buf = b""
def pump(seconds):
    """Drain the pty (a full pipe would BLOCK the pager and hide the leak)."""
    global buf
    end = time.time() + seconds
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.1)
        if fd in r:
            try: chunk = os.read(fd, 65536)
            except OSError: return
            if not chunk: return
            buf += chunk

def wait_for(needle, seconds):
    end = time.time() + seconds
    while time.time() < end:
        if needle in buf: return True
        pump(0.1)
    return needle in buf

def bemaps():
    """How many VMAs map a `.be` ULOG right now — the leak, isolated from the
    anon-arena churn that makes the raw VMA total noisy on a small fixture."""
    n = 0
    try:
        with open("/proc/%d/maps" % pid) as f: lines = f.read().splitlines()
    except OSError: return -1
    for l in lines:
        p = l.split(None, 5)
        #  Both anchor shapes: the secondary `.be` FILE and a primary `.be/wtlog`.
        if len(p) > 5 and "/.be" in p[5].strip(): n += 1
    return n

fails = 0
def check(name, cond, note=""):
    global fails
    print(("ok   " if cond else "FAIL ") + name + (("  " + note) if note else ""))
    if not cond:
        fails += 1
        print("     --- frames ---")
        print("     " + repr(buf[-600:]))

check("pager-entered", wait_for(b"\x1b[7m", 8))

pump(SETTLE)
base = bemaps()
series = [base]
t0 = time.time()
while time.time() - t0 < WINDOW:
    pump(1.0)
    series.append(bemaps())
grew = max(series) - base

check("maps-readable", base >= 0, "base=%d" % base)
check("idle-pager-mappings-flat", grew <= BUDGET,
      "base=%d grew=%d budget=%d series=%s" % (base, grew, BUDGET, series))

# The pager must still be ALIVE and painting — a wedged/dead process is also flat.
buf = b""
os.write(fd, b"k")
check("pager-still-live", wait_for(b"\x1b[", 5))

os.write(fd, b"q")
pump(1.0)
try: os.close(fd)
except OSError: pass
try: os.waitpid(pid, 0)
except (ChildProcessError, OSError): pass

print("DONE" if fails == 0 else "FAILS=%d" % fails)
sys.exit(1 if fails else 0)
