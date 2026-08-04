#!/usr/bin/env python3
# CI-004 `v` button, through the REAL UI path.  Runs the FULL `jab ls` pager on
# a controlling pty (pty.fork), types real keystrokes, and reads the frames the
# pager paints back — no unit probe, no internal call.
#   argv[1] = jab binary   argv[2] = the fixture worktree (cwd for the jsrc-scan)
# The fixture carries a `ci.sh` that prints CIRAN, sleeps 3s and exits 0, so all
# three observable states (starting / in flight / verdict) are reachable in one
# session with room to spare on a loaded box.
import os, pty, select, sys, time

JAB = sys.argv[1]
WT  = sys.argv[2]
ENV = dict(os.environ, ASAN_OPTIONS="detect_leaks=0")

pid, fd = pty.fork()
if pid == 0:
    os.chdir(WT)
    for k, v in ENV.items(): os.environ[k] = v
    os.execv(JAB, [JAB, "ls"])
    os._exit(127)

buf = b""
def pump(seconds):
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
    """Drain until `needle` shows up in the frames, or the budget runs out."""
    global buf
    end = time.time() + seconds
    while time.time() < end:
        if needle in buf: return True
        pump(0.1)
    return needle in buf

def send(s): os.write(fd, s.encode())

fails = 0
def check(name, cond):
    global fails
    print(("ok   " if cond else "FAIL ") + name)
    if not cond:
        fails += 1
        print("     --- frames ---")
        print("     " + repr(buf[-900:]))

check("pager-entered", wait_for(b"\x1b[7m", 8))
check("no-badge-before-v", b"ci: " not in buf)

# --- press 1: the run starts ------------------------------------------------
buf = b""
send("v")
check("v-started-the-run", wait_for(b"ci: running ./ci.sh", 5))
check("v-message-names-the-log", b" log " in buf)

# --- press 2 while in flight: report, do NOT respawn ------------------------
buf = b""
send("v")
check("v-repress-reports-in-progress", wait_for(b"ci: already running", 5))

# Between presses the in-flight BADGE (no command line) rides the bar; `k` is a
# plain repaint that clears the transient message and leaves the badge alone.
buf = b""
send("k")
ok_badge = wait_for(b"ci: running", 3)
check("in-flight-badge", ok_badge and b"./ci.sh" not in buf)

# --- the child exits: the verdict reaches the screen with NO keystroke ------
buf = b""
check("verdict-badge-unprompted", wait_for(b"ci: ok", 15))

send("q")
pump(1.0)
try: os.close(fd)
except OSError: pass
try: os.waitpid(pid, 0)
except (ChildProcessError, OSError): pass

# The log file the runner captured must hold the child's stdout.
logs = []
tmp = os.path.join(os.environ.get("TMP", "/tmp"), "be-ci")
if os.path.isdir(tmp):
    for n in os.listdir(tmp):
        if n.endswith(".log"):
            with open(os.path.join(tmp, n), "rb") as f: logs.append(f.read())
check("log-file-captured-stdout", any(b"CIRAN" in l for l in logs))
# The tree itself stays clean: no log, no marker, no build droppings in the wt.
stray = [n for n in os.listdir(WT) if n.endswith(".log") or n.endswith(".rc")]
check("worktree-left-clean", stray == [])

print("DONE" if fails == 0 else "FAILS=%d" % fails)
sys.exit(1 if fails else 0)
