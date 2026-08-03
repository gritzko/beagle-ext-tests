#!/usr/bin/env python3
# TODO-004 pty click driver.  Forks a pty, execs the REAL `jab todo …` in it
# (isatty(1) -> the universal bro pager), feeds a real SGR left-press mouse
# report at the cell a meta pair paints on, and reads the repainted frame back.
# The evidence is the PAINTED FRAME flipping — the pager is arg-blind, so the
# click can only have driven the O spell and let the `todo` verb resolve it.
#
# What this proves (ruling 2026-08-03): a click REPLACES that key's filter and
# leaves the REST of the arg line alone.  The whole arg line rides the spell, so
# the repainted BANNER (the address bar) reads the new line verbatim:
#   `todo CLK Now:*`         click OPEN  -> `todo CLK Now:OPEN`   (topic kept)
#     back, then             click DONE  -> `todo CLK Now:DONE`   (REPLACED, not
#                                                                  two filters)
#   `todo CLK Now:* Sev:*`   click HIGH  -> `todo CLK Now:* Sev:HIGH`
#   `todo CLK-001` (a page)  click OPEN  -> `todo CLK Now:OPEN`
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
    #  known too (and 100 columns keeps the fixture's short rows unwrapped).
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
#  followed by the invocation, then the right-aligned `<pos>  h: help`.  Reading
#  it separately from the body is what distinguishes the BAR from the hunk
#  BANNER: both carry the spell text, only the bar carries the invite.
def bar(frame):
    for line in reversed(frame.split("\n")):
        if "h: help" in line: return line.strip()
    return ""
def bar_reads(frame, spell):
    b = bar(frame)
    return ("/: " + spell) in b, b

#  --- 1.  the ARG LINE REPLACEMENT round-trip ---------------------------------
#  `todo CLK Now:*` lists every Now-carrying ticket, topic+number ordered, each
#  row `KEY [VALUE]: title` — so at 100 columns the value of row N sits on
#  columns 10-13 (`CLK-001` 1-7, ` ` 8, `[` 9).  Screen row 1 is the banner, so
#  CLK-001 is row 2, CLK-002 row 3, CLK-003 row 4.
pid, fd = start(["todo", "CLK", "Now:*"])
base = sip(fd)
check("base-painted-open", "CLK-001 [OPEN]" in base, repr(base[:200]))
check("base-painted-done", "CLK-003 [DONE]" in base, repr(base[:200]))

press(fd, 2, 11)                                   # the [OPEN] of CLK-001
f1 = sip(fd)
check("click-OPEN-argline", "todo CLK Now:OPEN" in f1, repr(f1[:200]))
#  BRO-024: the bar shows the invocation AS DRIVEN.  A clicked word-spell now
#  records its `disp` like the typed path does — before that fix the bar fell
#  back to verb + relative ADDRESS, and a verb ARG is not an address, so it
#  painted a bare `todo` with the filter gone.
ok1, b1 = bar_reads(f1, "todo CLK Now:OPEN")
check("click-OPEN-address-bar", ok1, repr(b1))
check("click-OPEN-kept-topic", "todo CLK" in f1 and "todo Now:OPEN" not in f1, repr(f1[:200]))
check("click-OPEN-answer", "CLK-001" in f1 and "CLK-002" in f1 and "CLK-003" not in f1,
      repr(f1[:200]))

os.write(fd, b"-")                                 # the pager BACK key
back = sip(fd)
check("back-restored-the-base", "todo CLK Now:*" in back and "CLK-003 [DONE]" in back,
      repr(back[:200]))

press(fd, 4, 11)                                   # the [DONE] of CLK-003
f2 = sip(fd)
stop(pid, fd)
#  THE point of the ruling: the second click REPLACED `Now:`, it did not append
#  a second filter and it did not start a fresh line.
check("click-DONE-argline", "todo CLK Now:DONE" in f2, repr(f2[:200]))
check("click-DONE-replaced-not-appended", "Now:OPEN" not in f2 and "Now:*" not in f2,
      repr(f2[:200]))
check("click-DONE-kept-topic", "todo CLK Now:DONE" in f2, repr(f2[:200]))
check("click-DONE-answer", "CLK-003" in f2 and "CLK-001" not in f2, repr(f2[:200]))
ok2, b2 = bar_reads(f2, "todo CLK Now:DONE")
check("click-DONE-address-bar", ok2, repr(b2))          # the bar REPLACED too

#  --- 2.  the REST of the line is left alone ----------------------------------
#  `todo CLK Now:* Sev:*` paints `CLK-001 [OPEN] [HIGH]` — `[` 16, `HIGH` 17-20.
#  Clicking HIGH must rewrite ONLY the `Sev:` token, in place.
pid, fd = start(["todo", "CLK", "Now:*", "Sev:*"])
two = sip(fd)
check("two-key-painted", "CLK-001 [OPEN] [HIGH]" in two, repr(two[:200]))
press(fd, 2, 18)
f3 = sip(fd)
stop(pid, fd)
check("two-key-click-argline", "todo CLK Now:* Sev:HIGH" in f3, repr(f3[:200]))
check("two-key-click-answer", "CLK-001" in f3 and "CLK-002" not in f3, repr(f3[:200]))
ok3, b3 = bar_reads(f3, "todo CLK Now:* Sev:HIGH")
check("two-key-address-bar", ok3, repr(b3))

#  --- 3.  a ticket PAGE's meta block ------------------------------------------
#  CLK-001's file line 2 is `Now: OPEN`, painted on screen row 3: `Now:` on
#  columns 1-4, `OPEN` on 6-9.  The page's arg line is the ticket id, which
#  carries its TOPIC — so a pair click opens `todo CLK <Key>:<value>`.
for label, col, want in (("key", 2, "todo CLK Now:*"), ("value", 7, "todo CLK Now:OPEN")):
    pid, fd = start(["todo", "CLK-001"])
    before = sip(fd)
    check("page-painted-" + label, "Now: OPEN" in before, repr(before[:160]))
    press(fd, 3, col)
    after = sip(fd)
    stop(pid, fd)
    check("page-click-%s-argline" % label, want in after, repr(after[:200]))
    check("page-click-%s-listed" % label, "CLK-001" in after, repr(after[:200]))

print("DONE" if fails == 0 else "FAILS=%d" % fails)
sys.exit(1 if fails else 0)
