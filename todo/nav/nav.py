#!/usr/bin/env python3
# TODO-008 pty nav driver.  Forks a pty, execs the REAL `jab todo …` in it
# (isatty(1) -> the universal bro pager), feeds a real SGR left-press mouse
# report at the cell a meta-pair VALUE paints on, and reads the repainted frame
# back.  The evidence is the PAINTED FRAME landing on the TARGET TICKET's page
# — the pager is arg-blind, so the click can only have driven the O spell and
# let the `todo` verb resolve it.
#   argv[1] = jab binary   argv[2] = the fixture worktree (the run's cwd)
import os, pty, select, sys, time, re, fcntl, termios, struct

JAB, WT = sys.argv[1], sys.argv[2]
ENV = dict(os.environ, ASAN_OPTIONS="detect_leaks=0")
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
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    return pid, fd

def sip(fd, secs=2.5):
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
    return ANSI.sub(b"", out).decode("utf8", "replace")

def stop(pid, fd):
    try: os.kill(pid, 9)
    except OSError: pass
    try: os.waitpid(pid, 0)
    except ChildProcessError: pass
    try: os.close(fd)
    except OSError: pass

def press(fd, row, col):
    os.write(fd, ("\x1b[<0;%d;%dM" % (col, row)).encode())

#  BRO-024: the ADDRESS BAR is the last painted line — the `//WT/dir/: ` invite
#  then the invocation.  A landing is asserted on BOTH the bar and the body, so
#  a filter answer that merely MENTIONS the code cannot pass for a page.
def bar(frame):
    for line in reversed(frame.split("\n")):
        if "h: help" in line: return line.strip()
    return ""
def landed(frame, key, title):
    """the frame IS that ticket's page: the bar names it and the body is it.
    TODO-011: the page is the `ticket` view now, so the bar must say so —
    a `todo` answer that merely mentions the code can no longer pass."""
    return ("/: ticket " + key) in bar(frame) and ("#   " + key + ": " + title) in frame

#  --- 1.  the ticket-view meta block ------------------------------------------
#  NAV-001 paints `Now: OPEN` on row 3, `See: NAV-002` on row 4 and
#  `Zzz: NAV-003` on row 5; a key is columns 1-4, a value columns 6-13.
pid, fd = start(["ticket", "NAV-001"])
page = sip(fd)
check("page-painted", "See: NAV-002" in page and "Zzz: NAV-003" in page, repr(page[:200]))

press(fd, 4, 8)                                    # the NAV-002 of `See:`
f1 = sip(fd)
check("see-value-navigates", landed(f1, "NAV-002", "beta"), repr((bar(f1), f1[:200])))
check("see-value-is-not-a-filter", "See:NAV-002" not in f1, repr(f1[:200]))

os.write(fd, b"-")                                 # the pager BACK key
back1 = sip(fd)
check("back-to-the-page", "See: NAV-002" in back1, repr(back1[:200]))

#  the VALUE's lexical class alone decides — `Zzz:` is registered nowhere.
press(fd, 5, 8)                                    # the NAV-003 of `Zzz:`
f2 = sip(fd)
check("unknown-key-value-navigates", landed(f2, "NAV-003", "gamma"),
      repr((bar(f2), f2[:200])))

os.write(fd, b"-")
back2 = sip(fd)
check("back-to-the-page-again", "See: NAV-002" in back2, repr(back2[:200]))

#  the KEY half keeps its TODO-004 behaviour: the presence filter, on the whole
#  arg line (the page's id carries its topic).
press(fd, 4, 2)                                    # the `See:` key half
f3 = sip(fd)
stop(pid, fd)
check("key-half-still-filters", "todo NAV See:*" in f3, repr(f3[:200]))
check("key-half-answers", "NAV-001" in f3 and "beta" not in f3, repr(f3[:200]))

#  --- 2.  the board's INLINE value --------------------------------------------
#  `todo NAV See:*` paints one row, `● NAV-001 [NAV-002] alpha`: `●` 1, ` ` 2,
#  `NAV-001` 3-9, ` ` 10, `[` 11, `NAV-002` 12-18.  Screen row 1 is the banner,
#  so the row is row 2.
pid, fd = start(["todo", "NAV", "See:*"])
board = sip(fd)
check("board-painted", "NAV-001 [NAV-002]" in board, repr(board[:200]))
press(fd, 2, 14)                                   # the inline [NAV-002]
f4 = sip(fd)
stop(pid, fd)
check("board-inline-value-navigates", landed(f4, "NAV-002", "beta"),
      repr((bar(f4), f4[:200])))
check("board-inline-value-is-not-a-filter", "See:NAV-002" not in f4, repr(f4[:200]))

#  --- 3.  TODO-011: a topic list's KEY ROW click lands in `ticket` -----------
#  `todo NAV` paints three rows; row 1 is `● NAV-001 ┄… alpha`, so screen row 2
#  is NAV-001 and row 3 is NAV-002: `●` 1, ` ` 2, the key 3-9.  The pager is
#  arg-blind, so a landing on the PAGE can only have driven the row's O spell.
pid, fd = start(["todo", "NAV"])
lst = sip(fd)
check("list-painted", "NAV-002" in lst and "beta" in lst, repr(lst[:200]))
press(fd, 3, 5)                                    # the NAV-002 key row
f5 = sip(fd)
stop(pid, fd)
check("list-key-row-opens-the-ticket-view", landed(f5, "NAV-002", "beta"),
      repr((bar(f5), f5[:200])))

print("DONE" if fails == 0 else "FAILS=%d" % fails)
sys.exit(1 if fails else 0)
