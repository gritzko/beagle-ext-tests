#!/usr/bin/env python3
# WORK-004 pty driver (getctx harness shape): run the FULL `jab work` pager on a
# real pty (pty.fork) and prove the ahbeh buttons render + click through the REAL
# UI path — not a TLV/unit probe.  The frame must show `[+N]`/`[-N]` (salad/salmon
# ahbeh buttons) and NO retired `[get]`; a real SGR mouse press on the behind
# `[-N]` button must be accepted (the pager stays alive, exits clean on `q`) and
# must NOT mutate the LAUNCH tree's .be (the row's ctx anchors the invite).
#   argv[1]=jab  argv[2]=launch cwd (the project root)  argv[3]=launch .be path
import os, pty, re, select, struct, sys, time
import fcntl, termios

sys.stdout.reconfigure(line_buffering=True)
JAB, CWD, BEFILE = sys.argv[1], sys.argv[2], sys.argv[3]
ENV = dict(os.environ, ASAN_OPTIONS="detect_leaks=0")
ESC_RE = re.compile(rb"\x1b\[[0-9;?<=>]*[A-Za-z]|\x1b[()][0-9A-Za-z]|\r")

fails = 0
def check(name, cond):
    global fails
    print(("ok   " if cond else "FAIL ") + name)
    if not cond: fails += 1

def frame_lines(out):
    segs = re.split(rb"\x1b\[H|\x1b\[2J", out)
    for seg in reversed(segs):
        txt = ESC_RE.sub(b"", seg).decode("utf-8", "replace")
        lines = txt.split("\n")
        if any("//PIN-" in l for l in lines):
            return lines
    return []

def find_button(lines, rowkey, btn):
    for i, l in enumerate(lines):
        if rowkey + " " in l or l.rstrip().endswith(rowkey):
            c = l.find(btn)
            if c >= 0:
                return (i + 1, c + 2)
    return None

class Sess:
    def __init__(self, fd, pid): self.fd, self.pid, self.out = fd, pid, b""
    def read_ready(self, wait):
        r, _, _ = select.select([self.fd], [], [], wait)
        if self.fd not in r: return False
        try: chunk = os.read(self.fd, 65536)
        except OSError: return False
        if not chunk: return False
        self.out += chunk
        return True
    def wait_for(self, pred, timeout):
        end = time.time() + timeout
        while time.time() < end:
            if pred(self.out): return True
            self.read_ready(0.3)
        return pred(self.out)
    def absorb(self, sec):
        end = time.time() + sec
        while time.time() < end:
            self.read_ready(0.2)
    def reap(self, timeout):
        end = time.time() + timeout
        while time.time() < end:
            try: wpid, status = os.waitpid(self.pid, os.WNOHANG)
            except ChildProcessError: return None
            if wpid == self.pid: return os.waitstatus_to_exitcode(status)
            self.read_ready(0.2)
        try: os.kill(self.pid, 9)
        except OSError: pass
        try: os.waitpid(self.pid, 0)
        except ChildProcessError: pass
        return "KILLED"

with open(BEFILE, "rb") as f: be_before = f.read()

pid, fd = pty.fork()
if pid == 0:
    os.chdir(CWD)
    for k, v in ENV.items(): os.environ[k] = v
    os.execv(JAB, [JAB, "work"])
    os._exit(127)
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 220, 0, 0))
s = Sess(fd, pid)
painted = s.wait_for(lambda o: b"[diff]" in o and b"//PIN-1" in o, 15)
check("frame painted", painted)
if painted:
    time.sleep(0.3); os.write(fd, b"\x1b"); s.absorb(1.0)  # nudge a repaint
    lines = frame_lines(s.out)
    joined = "\n".join(lines)
    # RENDER: the ahbeh counts are buttons; [get] is retired.
    check("frame shows a [-N] behind button", "[-1]" in joined)
    check("frame shows a [+N] ahead button", "[+1]" in joined)
    check("frame has NO retired [get] button", "[get]" not in joined)
    rc = find_button(lines, "//PIN-1", "[-1]")
    check("behind [-1] locatable on the //PIN-1 row", rc is not None)
    if rc is not None:
        mark = len(s.out)
        os.write(fd, ("\x1b[<0;%d;%dM" % (rc[1], rc[0])).encode())
        os.write(fd, ("\x1b[<0;%d;%dm" % (rc[1], rc[0])).encode())
        s.wait_for(lambda o: len(o) > mark, 10)
        s.absorb(1.0)
        post = ESC_RE.sub(b"", s.out[mark:]).decode("utf-8", "replace")
        for l in [l for l in post.split("\n") if l.strip()][-3:]:
            print("click | " + l.strip()[:200])
    else:
        print("FRAME:\n" + joined)
os.write(fd, b"q")
s.absorb(0.5)
code = s.reap(8.0)
check("pager exit clean", code == 0 or code is None)
try: os.close(fd)
except OSError: pass

with open(BEFILE, "rb") as f: be_after = f.read()
check("the LAUNCH tree's .be is byte-identical after the click", be_before == be_after)

print("pty session done" if fails == 0 else "pty FAILS: %d" % fails)
sys.exit(1 if fails else 0)
