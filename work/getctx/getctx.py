#!/usr/bin/env python3
# WORK-002 pty driver: run the FULL `jab work` pager on a pty (pty.fork) from
# the LAUNCH tree and click row buttons with REAL SGR mouse reports — the exact
# byte path a terminal produces.  Three sessions:
#   R1 [diff]  on //PIN-1: the click must not err (status line captured);
#   R2 refusal on //PIN-2: the wt is rm -rf'ed AFTER the frame paints, so the
#      O invite's context anchors NO worktree — the click must refuse loudly
#      in the status line and mutate nothing (run.sh asserts the files);
#   R3 [get]   on //PIN-1: the mutation must land in PIN-1 (run.sh asserts).
#   argv[1]=jab  argv[2]=BASE (launch wt, cwd)  argv[3]=META work/ dir
import os, pty, re, select, shutil, struct, sys, time
import fcntl, termios

sys.stdout.reconfigure(line_buffering=True)
JAB, BASE, WORKD = sys.argv[1], sys.argv[2], sys.argv[3]
ENV = dict(os.environ, ASAN_OPTIONS="detect_leaks=0")
ESC_RE = re.compile(rb"\x1b\[[0-9;?<=>]*[A-Za-z]|\x1b[()][0-9A-Za-z]|\r")

fails = 0
def check(name, cond):
    global fails
    print(("ok   " if cond else "FAIL ") + name)
    if not cond: fails += 1

def frame_lines(out):
    # The LAST painted frame: split on cursor-home/clear, strip SGR, split rows.
    segs = re.split(rb"\x1b\[H|\x1b\[2J", out)
    for seg in reversed(segs):
        txt = ESC_RE.sub(b"", seg).decode("utf-8", "replace")
        lines = txt.split("\n")
        if any("//PIN-" in l for l in lines):
            return lines
    return []

def find_button(lines, rowkey, btn):
    # 1-based (row, col) of the 2nd char of `btn` on the `rowkey` row.
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
            try:
                wpid, status = os.waitpid(self.pid, os.WNOHANG)
            except ChildProcessError:
                return None
            if wpid == self.pid:
                return os.waitstatus_to_exitcode(status)
            self.read_ready(0.2)
        try: os.kill(self.pid, 9)
        except OSError: pass
        try: os.waitpid(self.pid, 0)
        except ChildProcessError: pass
        return "KILLED"

def session(name, rowkey, btn, expect, rm=None):
    pid, fd = pty.fork()
    if pid == 0:
        os.chdir(BASE)
        for k, v in ENV.items(): os.environ[k] = v
        os.execv(JAB, [JAB, "work"])
        os._exit(127)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 220, 0, 0))
    s = Sess(fd, pid)
    painted = s.wait_for(lambda o: b"[get]" in o and rowkey.encode() in o, 15)
    check(name + " frame painted", painted)
    if painted:
        time.sleep(0.3); os.write(fd, b"\x1b")      # nudge a repaint at 220 cols
        s.absorb(1.0)
        rc = find_button(frame_lines(s.out), rowkey, btn)
        check(name + " frame has " + btn + " on " + rowkey, rc is not None)
        if rc is not None:
            if rm: shutil.rmtree(rm)                # yank the wt UNDER the invite
            mark = len(s.out)
            os.write(fd, ("\x1b[<0;%d;%dM" % (rc[1], rc[0])).encode())
            os.write(fd, ("\x1b[<0;%d;%dm" % (rc[1], rc[0])).encode())
            s.wait_for(lambda o: len(o) > mark, 10)
            s.absorb(1.5)                           # the drive + repaint
            post = ESC_RE.sub(b"", s.out[mark:]).decode("utf-8", "replace")
            for l in [l for l in post.split("\n") if l.strip()][-3:]:
                print(name + " | " + l.strip()[:200])
            for pat, want in expect:
                check(name + " " + repr(pat) + (" present" if want else " absent"),
                      (pat in post) == want)
        else:
            print("FRAME:\n" + "\n".join(frame_lines(s.out)))
    os.write(fd, b"q")
    s.absorb(0.5)
    code = s.reap(8.0)
    check(name + " pager exit clean", code == 0 or code is None)
    try: os.close(fd)
    except OSError: pass

# R1: [diff] on //PIN-1 — no `err:` on the status line after the click.
session("R1-diff", "//PIN-1", "[diff]", [("err:", False)])
# R2: refusal — //PIN-2's wt vanishes between paint and click; the mutation
# must refuse in plain words, not fall back to the launch tree.
session("R2-refuse", "//PIN-2", "[get]", [("no worktree", True)],
        rm=os.path.join(WORKD, "PIN-2"))
# R3: [get] on //PIN-1 — the row's wt takes the mutation (files asserted by run.sh).
session("R3-get", "//PIN-1", "[get]", [])

print("getctx sessions done" if fails == 0 else "getctx FAILS: %d" % fails)
sys.exit(1 if fails else 0)
