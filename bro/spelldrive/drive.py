#!/usr/bin/env python3
# CODE-030 pty driver: the address-bar SPELL DRIVE moved out of views/bro/bro.js
# into core/loop.js (buildHunks/spellCall/driveSpell) and bro's pager branch now
# calls loop.openPager.  Prove all three still work THROUGH THE REAL UI — a
# pty.fork'd `jab bro <spell>`, a typed `:` spell and a real SGR mouse CLICK —
# not a TLV/unit probe.  Three legs, each asserting the frame actually swapped:
#   1. LAUNCH  `jab bro cat:hello.txt` -> broRun -> loop.driveSpell (spellCall +
#      the --tlv cli re-entry) -> loop.openPager: the frame shows the file body.
#   2. TYPED   `:cat sub/notes.txt` + Enter -> pager._runSpell -> loop.driveSpell:
#      the frame swaps to the other file.
#   3. CLICK   a real SGR press on a body word -> the pager's click dispatch ->
#      loop.driveSpell: the frame swaps to that word's `grep` view.
# Then `q` must leave the pager cleanly (exit 0).
#   argv[1] = jab   argv[2] = the fixture worktree (cwd)   argv[3] = $BE_ROOT
import os, pty, re, select, struct, sys, time, fcntl, termios

sys.stdout.reconfigure(line_buffering=True)
JAB, CWD, BEROOT = sys.argv[1], sys.argv[2], sys.argv[3]
ENV = dict(os.environ, ASAN_OPTIONS="detect_leaks=0", BE_ROOT=BEROOT)
ESC_RE = re.compile(rb"\x1b\[[0-9;?<=>]*[A-Za-z]|\x1b[()][0-9A-Za-z]|\r")

fails = 0
def check(name, cond):
    global fails
    print(("ok   " if cond else "FAIL ") + name)
    if not cond: fails += 1

out = b""
def pump(sec):
    global out
    end = time.time() + sec
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.2)
        if fd not in r: continue
        try: chunk = os.read(fd, 65536)
        except OSError: return
        if not chunk: return
        out += chunk

def wait_for(needle, timeout, since=0):
    end = time.time() + timeout
    while True:
        if needle in ESC_RE.sub(b"", out[since:]): return True
        if time.time() > end: return False
        pump(0.3)

def press(row, col):                       # SGR mouse press + release, 1-based
    os.write(fd, ("\x1b[<0;%d;%dM" % (col, row)).encode())
    os.write(fd, ("\x1b[<0;%d;%dm" % (col, row)).encode())

pid, fd = pty.fork()
if pid == 0:
    os.chdir(CWD)
    for k, v in ENV.items(): os.environ[k] = v
    os.execv(JAB, [JAB, "bro", "cat:hello.txt"])
    os._exit(127)
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 120, 0, 0))

# --- 1. LAUNCH: the arg is a SPELL, driven before the pager opens -----------
painted = wait_for(b"beta UNI-1 two", 15)
check("launch spell drove the cat view into the pager frame", painted)
check("the pager really entered raw mode (alt screen / inverse bar)",
      b"\x1b[?1049h" in out or b"\x1b[7m" in out)

if painted:
    # --- 2. TYPED `:` spell: the pager re-enters the loop ------------------
    mark = len(out)
    os.write(fd, b":cat sub/notes.txt\r")
    check("typed `:cat sub/notes.txt` swapped the frame",
          wait_for(b"delta four", 15, mark))

    # --- 3. real MOUSE CLICK on a body word -------------------------------
    mark = len(out)
    os.write(fd, b"-")                     # back to the hello.txt view
    wait_for(b"beta UNI-1 two", 10, mark)
    mark = len(out)
    press(3, 8)                            # row 3 = `beta UNI-1 two`, inside the key
    check("a real SGR click drove a NEW view (the word's grep)",
          wait_for(b"grep //UNI/hello.txt", 15, mark))

os.write(fd, b"q")
pump(1.0)
end = time.time() + 8
code = "KILLED"
while time.time() < end:
    try: wpid, status = os.waitpid(pid, os.WNOHANG)
    except ChildProcessError: code = None; break
    if wpid == pid: code = os.waitstatus_to_exitcode(status); break
    pump(0.2)
if code == "KILLED":
    try: os.kill(pid, 9); os.waitpid(pid, 0)
    except OSError: pass
check("the pager exited clean on `q`", code == 0 or code is None)
try: os.close(fd)
except OSError: pass

if fails:
    print("--- last frame ---")
    for seg in re.split(rb"\x1b\[H|\x1b\[2J", out)[-3:]:
        print(ESC_RE.sub(b"", seg).decode("utf-8", "replace"))
print("DONE" if fails == 0 else "FAILS=%d" % fails)
sys.exit(1 if fails else 0)
