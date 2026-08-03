#!/usr/bin/env python3
# BRO-043 pty driver: the REAL UI path.  One `jab bro` pager on a pty (pty.fork)
# in a real worktree, driven by keystrokes only:
#   :status  #1 cold          -> MISS
#   :status  #2 warm          -> HIT, and its frame must be BYTE-IDENTICAL to #1
#   <write a file in the wt>
#   :status  #3               -> MISS (the watcher dropped the repo), shows it
#   :status  #4               -> HIT
#   R        (refresh key)    -> dropAll, and its own re-render is a MISS
#   :status  #5               -> HIT again
# Under JAB_STATS=1 the pager prints its cache line on exit, so the whole
# scenario reduces to hits=3 misses=3: without the `R` hook R would have been a
# HIT (hits=4 misses=2), and with no cache at all there is no line.
#   argv[1]=jab  argv[2]=wt (cwd)
import os, pty, re, select, struct, sys, time
import fcntl, termios

sys.stdout.reconfigure(line_buffering=True)
JAB, WT = sys.argv[1], sys.argv[2]
ENV = dict(os.environ, ASAN_OPTIONS="detect_leaks=0", JAB_STATS="1")
ESC_RE = re.compile(rb"\x1b\[[0-9;?<=>]*[A-Za-z]|\x1b[()][0-9A-Za-z]|\r")

fails = 0
def check(name, cond):
    global fails
    print(("ok   " if cond else "FAIL ") + name)
    if not cond: fails += 1

pid, fd = pty.fork()
if pid == 0:
    os.chdir(WT)
    for k, v in ENV.items(): os.environ[k] = v
    os.execv(JAB, [JAB, "bro"])
    os._exit(127)
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 200, 0, 0))

out = b""
def pump(sec):
    global out
    end = time.time() + sec
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.2)
        if fd in r:
            try: chunk = os.read(fd, 65536)
            except OSError: return
            if not chunk: return
            out += chunk

def keys(s, settle=2.5):
    global out
    mark = len(out)
    os.write(fd, s.encode())
    pump(settle)
    return ESC_RE.sub(b"", out[mark:]).decode("utf-8", "replace")

def spell(s, settle=2.5):
    return keys(":" + s + "\r", settle)

# The painted frame, minus the pager's own chrome (the command-line echo) and
# minus the JAB_STATS counter line this harness itself turned on — what a HIT
# must reproduce exactly.
def body(frame):
    lines = [l.rstrip() for l in frame.split("\n")]
    return "\n".join(l for l in lines
                      if l and not l.startswith(":") and not l.startswith("stats:"))

pump(2.0)                                   # the empty viewport paints
f1 = spell("status")                        # #1 cold  -> MISS
f2 = spell("status")                        # #2 warm  -> HIT
with open(os.path.join(WT, "brand-new.txt"), "w") as f:
    f.write("hello\n")
time.sleep(0.4)
f3 = spell("status")                        # #3 after a write -> MISS
f4 = spell("status")                        # #4 warm again    -> HIT
fR = keys("R")                              # R -> dropAll, its re-render MISSES
f5 = spell("status")                        # #5 warm again    -> HIT

os.write(fd, b"q")
pump(2.0)
try:
    os.waitpid(pid, 0)
except ChildProcessError:
    pass
try: os.close(fd)
except OSError: pass

tail = ESC_RE.sub(b"", out).decode("utf-8", "replace")
m = re.search(r"cache: hits=(\d+) misses=(\d+) drops=(\d+) dirs=(\d+)", tail)
check("pager reported a cache line", m is not None)
if m:
    hits, misses, drops, dirs = (int(x) for x in m.groups())
    print("   cache: hits=%d misses=%d drops=%d dirs=%d" % (hits, misses, drops, dirs))
    check("the warm re-fires HIT (hits==3)", hits == 3)
    check("cold + post-write + post-R are MISSES (misses==3)", misses == 3)
    check("the write and `R` both DROPPED (drops>=2)", drops >= 2)
    check("the walk armed real dirs (dirs>=1)", dirs >= 1)
check("the cached frame is BYTE-IDENTICAL to the computed one",
      body(f2) == body(f1) and len(body(f1)) > 0)
check("frame 3 shows the file written under the live watcher",
      "brand-new.txt" in f3)
check("frame 2 (the cached one) does not", "brand-new.txt" not in f2)
check("frames 3/4/5 stay identical across hit, R-drop and re-warm",
      body(f4) == body(f3) and body(f5) == body(f3))
print("bro/cache done" if fails == 0 else "bro/cache FAILS: %d" % fails)
sys.exit(1 if fails else 0)
