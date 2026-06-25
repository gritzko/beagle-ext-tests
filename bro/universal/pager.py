#!/usr/bin/env python3
# JAB-030 universal-pager integration: every jab view renders through ONE output
# gate — on a TTY the interactive bro Pager, on a PIPE the plain hunk dump.  Runs
# the FULL `jab <cmd>` two ways: under a pty (isatty(1) true → a pager frame with
# the inverse-video status bar ESC[7m, quit on 'q', exit 0) and through a pipe
# (no raw frame, same content, exit 0).  Covers a content view (cat/grep, the
# hunk sink) AND a columnar view (ls, the emit sink wrapped as one hunk).
#   argv[1] = jab binary   argv[2] = the worktree (CWD for the be/-scan)
import os, pty, select, sys, time, subprocess

JAB = sys.argv[1]
WT  = sys.argv[2]
ENV = dict(os.environ, ASAN_OPTIONS="detect_leaks=0")

def run_pty(args, timeout=10.0):
    pid, fd = pty.fork()
    if pid == 0:
        os.chdir(WT)
        for k, v in ENV.items(): os.environ[k] = v
        os.execv(JAB, [JAB] + args)
        os._exit(127)
    out, sent, start = b"", False, time.time()
    while True:
        if time.time() - start > timeout:
            try: os.kill(pid, 9)
            except OSError: pass
            os.waitpid(pid, 0)
            return ("TIMEOUT", out)
        r, _, _ = select.select([fd], [], [], 0.5)
        if fd in r:
            try: chunk = os.read(fd, 65536)
            except OSError: break
            if not chunk: break
            out += chunk
            if not sent and (b"\x1b[7m" in out or b"\x1b[2J" in out):
                time.sleep(0.2); os.write(fd, b"q"); sent = True
        else:
            try:
                wpid, status = os.waitpid(pid, os.WNOHANG)
                if wpid == pid:
                    try:
                        while True:
                            c = os.read(fd, 65536)
                            if not c: break
                            out += c
                    except OSError: pass
                    return (os.waitstatus_to_exitcode(status), out)
            except ChildProcessError: break
    wpid, status = os.waitpid(pid, 0)
    return (os.waitstatus_to_exitcode(status), out)

def run_pipe(args):
    p = subprocess.run([JAB] + args, cwd=WT, env=ENV,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return (p.returncode, p.stdout)

def frame(out): return b"\x1b[7m" in out or b"\x1b[2J" in out

fails = 0
def check(name, cond):
    global fails
    print(("ok   " if cond else "FAIL ") + name)
    if not cond: fails += 1

VIEWS = [("cat", ["cat", "cat:core/job.js"]),
         ("grep", ["grep", "grep:#JSQUE"]),
         ("ls",  ["ls"])]

for label, args in VIEWS:
    rc, out = run_pty(args)
    check(f"tty-{label}-entered-pager", frame(out))
    check(f"tty-{label}-exit0", rc == 0)
for label, args in VIEWS:
    rc, out = run_pipe(args)
    check(f"pipe-{label}-no-frame", not frame(out))
    check(f"pipe-{label}-has-output", len(out) > 0)
    check(f"pipe-{label}-exit0", rc == 0)

print("DONE" if fails == 0 else "FAILS=%d" % fails)
sys.exit(1 if fails else 0)
