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

#  TODO-005: a button is 2 cells of COLOURED FOREGROUND on the default bg, so it
#  is read off the PAINTED SGR (its own truecolor fg across the whole face and
#  NO background anywhere; a disabled slot wears plain grey).  The raw bytes of
#  the last frame are kept beside the stripped text.
RAW = {"last": b""}
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
#  row `<●> KEY [VALUE] title` — TODO-005 put the severity bullet first, so at
#  100 columns the value of row N sits on columns 12-15 (`●` 1, ` ` 2, `CLK-001`
#  3-9, ` ` 10, `[` 11).  Screen row 1 is the banner, so CLK-001 is row 2,
#  CLK-002 row 3, CLK-003 row 4.
pid, fd = start(["todo", "CLK", "Now:*"])
base = sip(fd)
check("base-painted-open", "CLK-001 [OPEN]" in base, repr(base[:200]))
check("base-painted-done", "CLK-003 [DONE]" in base, repr(base[:200]))

press(fd, 2, 13)                                   # the [OPEN] of CLK-001
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

press(fd, 4, 13)                                   # the [DONE] of CLK-003
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
#  `todo CLK Now:* Sev:*` paints `● CLK-001 [OPEN] [HIGH]` — `[` 18, `HIGH` 19-22.
#  Clicking HIGH must rewrite ONLY the `Sev:` token, in place.
pid, fd = start(["todo", "CLK", "Now:*", "Sev:*"])
two = sip(fd)
check("two-key-painted", "CLK-001 [OPEN] [HIGH]" in two, repr(two[:200]))
press(fd, 2, 20)
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
#  TODO-011: the page is the `ticket` view now, and a FILTER click stays a
#  `todo` spell wherever it is rendered — that cross-view landing is the point.
for label, col, want in (("key", 2, "todo CLK Now:*"), ("value", 7, "todo CLK Now:OPEN")):
    pid, fd = start(["ticket", "CLK-001"])
    before = sip(fd)
    check("page-painted-" + label, "Now: OPEN" in before, repr(before[:160]))
    press(fd, 3, col)
    after = sip(fd)
    stop(pid, fd)
    check("page-click-%s-argline" % label, want in after, repr(after[:200]))
    check("page-click-%s-listed" % label, "CLK-001" in after, repr(after[:200]))

#  --- 4.  TODO-005: a BUTTON click MUTATES the worktree -----------------------
#  `work/CLK-001` is a real wt with ONE modified tracked file at the top and ONE
#  inside a MOUNTED sub, so its file frame reads `[ i ~2    +2  ∞]` — the count
#  is 2 only because the sub folded in (bare `put`/`delete` descend mounts).
#  At 100 columns the row reads `●` 1, ` ` 2, `CLK-001` 3-9, the KEYW dotted
#  leader 10-18, ` ` 19, `[` 20, the ` i` button 21-22, a gap 23, the changed
#  button 24-25 — the face IS the button, so the stage click is column 25.
#  It drives the O spell `//CLK-001/: put`.  `put` MUTATES, so there is no
#  result screen: the pager runs it in the wt's own context and repaints in
#  place.  Witnesses, none of them a tlv probe:
#    a. the changed cell is PAINTED as a button before — its own truecolor fg,
#       spelled by the slot's own hidden O, and NO background;
#    b. that fg covers the WHOLE face and stops at the gap beside it;
#    c. after the click the same cell is GREY — the class has nothing left to
#       stage, so it shows its STAGED count and mints nothing;
#    d. the wt's AND the sub's own wtlogs carry the `put` rows the click wrote.
#  resolved from view/theme.js BTN + pale() at BTN_PALE 0.88 — this golden
#  carries the resolved values, the DERIVATION is asserted in test/todo/rows.
FG_CHG  = "38;2;54;71;201"       # BTN.chg    #3647c9 (file panel: blue)
BG_CHG  = "48;2;231;233;249"     # pale       #e7e9f9
FG_STAT = "38;2;0;133;202"       # BTN.status #0085ca
BG_STAT = "48;2;224;240;249"     # pale       #e0f0f9
FG_LOG  = "38;2;255;208;46"      # BTN.log    #ffd02e (Pantone Dandelion)
BG_LOG  = "48;2;255;249;230"     # pale       #fff9e6
FG_PAT  = "38;2;132;32;223"      # BTN.patch  #8420df (commit panel: violet)
BG_PAT  = "48;2;240;228;251"     # pale       #f0e4fb
FG_CI   = "38;2;0;169;92"        # BTN.ci     #00a95c
BG_CI   = "48;2;224;245;235"     # pale       #e0f5eb
pid, fd = start(["todo", "CLK"])
board = sip(fd)
check("frame-painted", "[ i ~2    +2  ∞]" in board, repr(board[:300]))
check("frame-painted-subfold", "[ i ~2" in board, repr(board[:300]))
check("frame-painted-commit", "[ ≡ +1      ]" in board, repr(board[:300]))
#  the three named brand buttons, at the SGR level: the exact truecolor fg, and
#  NO background anywhere on a button (the inversion was reverted).
st = sgr_before(RAW["last"], " i".encode())
check("status-button-fg", st is not None and FG_STAT in st, repr(st))
check("status-button-bg-is-pale", st is not None and BG_STAT in st, repr(st))
lg = sgr_before(RAW["last"], " ≡".encode())
check("log-button-fg", lg is not None and FG_LOG in lg, repr(lg))
check("log-button-bg-is-pale", lg is not None and BG_LOG in lg, repr(lg))
lit = sgr_before(RAW["last"], b"~2")
check("stage-button-fg", lit is not None and FG_CHG in lit, repr(lit))
check("stage-button-bg-is-pale", lit is not None and BG_CHG in lit, repr(lit))
#  the fg covers BOTH cells of the face and STOPS at the gap: the only SGR
#  inside the face is the one that opened it, and the next one closes it.
face = RAW["last"].find(b"~2")
check("stage-button-face-unbroken", b"\x1b" not in RAW["last"][face:face + 2],
      repr(RAW["last"][face:face + 8]))
gap = re.match(rb"\x1b\[([0-9;]*)m", RAW["last"][face + 2:])
check("stage-button-colour-stops-at-the-gap",
      gap is not None and (("39" in gap.group(1).decode().split(";")
                            and "49" in gap.group(1).decode().split(";"))
                           or gap.group(1) == b"0"),
      repr(RAW["last"][face:face + 16]))

press(fd, 2, 25)                                   # the changed-count button
f4 = sip(fd)
stop(pid, fd)
check("stage-click-ran-put", "put" in f4, repr(f4[-300:]))
check("stage-click-stayed-on-the-board", "CLK-001" in f4 and "CLK-002" in f4,
      repr(f4[:300]))
#  the staged tally KEEPS its class colour (no-grey ruling 2026-08-03) but
#  sheds the wash — colour says WHAT it is, the wash alone says "clickable".
after = sgr_before(RAW["last"], b"~2")
check("stage-click-slot-kept-its-colour", after is not None and FG_CHG in after,
      repr(after))
check("stage-click-slot-shed-the-wash", after is not None and "48;" not in after,
      repr(after))
#  …and the ci button, dead a moment ago, is now live green over its pale wash.
ci = sgr_before(RAW["last"], " ✓".encode())
check("stage-click-lit-the-ci-button", ci is not None and FG_CI in ci, repr(ci))
check("stage-click-ci-bg-is-pale", ci is not None and BG_CI in ci, repr(ci))
#  a secondary wt into a shared store keeps its wtlog IN the `.be` FILE itself;
#  the mounted sub is a colocated primary, so its rows land in `.be/wtlog`.
def readfile(rel):
    try:
        with open(os.path.join(WT, rel)) as fh: return fh.read()
    except OSError as e:
        check("readable-" + rel, False, str(e)); return ""
check("stage-click-staged-the-file", "\tput\ta.txt" in readfile("work/CLK-001/.be"),
      "top-level put row missing")
check("stage-click-staged-the-SUB-file",
      "\tput\tb.txt" in readfile("work/CLK-001/lib/.be/wtlog"),
      "the click must stage inside the mount too")

#  --- 5.  the DIVERGED patch button runs `patch` ------------------------------
#  `work/CLK-002` tracks the CLK-001 WORKTREE (a uriTrack — the common `work/`
#  shape, where attachedBranch names no branch at all) and both sides have
#  moved, so its commit frame paints the `A⇄B` patch button.  The arg is the TRACK
#  ADDRESS: `#<hashlet>` would be a patchscope NAMED scope — a cherry-pick with
#  fork = parent — not the LINE absorb `?branch` performs.  CLK-002 is row 3;
#  frame 2 opens at column 37, ` ≡` 38-39, gap 40, the 5-cell pair 41-45.
#  CLK-002 is row 4 (prio-then-number puts the Sev-less CLK-004 above it).
pid, fd = start(["todo", "CLK"])
two = sip(fd)
check("diverged-painted", "[ ≡   1⇄1   ]" in two, repr(two[:400]))
#  the pair face is 5 cells (`  1⇄1`), so the button's SGR opens before its
#  leading pad — the whole face is one unbroken coloured run.
pat = sgr_before(RAW["last"], "  1⇄1".encode())
check("patch-button-fg", pat is not None and FG_PAT in pat, repr(pat))
check("patch-button-bg-is-pale", pat is not None and BG_PAT in pat, repr(pat))
press(fd, 4, 43)                                   # the `1⇄1` patch button
f5 = sip(fd)
stop(pid, fd)
check("patch-click-ran-patch", "patch" in f5, repr(f5[-400:]))
check("patch-click-stayed-on-the-board", "CLK-002" in f5, repr(f5[:300]))
check("patch-click-recorded-the-absorb", "\tpatch\t" in readfile("work/CLK-002/.be"),
      "no patch provenance row in the wt's ulog")

#  --- 6.  the [go] mint button on a wt-LESS `Rep:` row ------------------------
#  CLK-004 has no worktree but its head names the repo it relates to, so its
#  frames region opens with the BRACKETED 4-cell `[go]` button — it stands alone
#  with no frame around it — and keeps the ┄ leader behind it — the title column does not move.  The button is the standard live form
#  (Shocking Orange over pale(orange)); a `Rep:`-less wt-less row shows leader
#  only.  CLK-004 is row 4 (prio-then-number: 001, 002, 004 — 003 is closed).
FG_GO = "38;2;255;109;43"        # BTN.go   #ff6d2b (Pantone Shocking Orange)
BG_GO = "48;2;255;237;230"       # pale     #ffede6
pid, fd = start(["todo", "CLK"])
six = sip(fd)
check("go-painted", "CLK-004" in six and "[go]" in six, repr(six[:400]))
#  the brackets are dim CHROME outside the click zone, so the button's own SGR
#  opens between `[` and the 2-cell face — search the FACE, not the frame.
g = sgr_before(RAW["last"], b"go")
check("go-button-fg", g is not None and FG_GO in g, repr(g))
check("go-button-bg-is-pale", g is not None and BG_GO in g, repr(g))
#  the leader runs on behind it, so the title column matches the frame rows'.
#  (the `[go]` text is contiguous only when SGR is stripped — the raw frame
#  carries the button's escape between the bracket and the face.)
def titlecol(frame, key, title):
    for line in frame.split("\n"):
        if key in line and title in line: return line.index(title)
    return -1
check("go-row-title-column",
      titlecol(six, "CLK-004", "delta") == titlecol(six, "CLK-001", "alpha"),
      repr((titlecol(six, "CLK-004", "delta"), titlecol(six, "CLK-001", "alpha"))))
check("rep-less-row-is-leader-only",
      "[go]" not in [l for l in six.split("\n") if "CLK-002" in l][0],
      repr([l for l in six.split("\n") if "CLK-002" in l]))
stop(pid, fd)

#  --- 7.  the DONE/DONT panel: both halves of closing, from a click ----------
#  The trailing `[done]` is now a PANEL of two live buttons.  At 100 columns the
#  row ends flush right, so the panel sits on columns 94-100: `[` 94, ` ✓` 95-96,
#  the dim gap 97, ` ✗` 98-99, `]` 100 — each face its OWN click zone.
#  Clicking ✓ must do BOTH acts (ruling): the ticket head's `Now:` pair becomes
#  DONE, and the ticket's worktree lands under work/done/.  The repaint then
#  drops the ticket entirely — a closed ticket is hidden by the implicit `Now:`
#  default — which also proves wtIndex no longer matches the moved wt.
#  These MUTATE the fixture, so they run last.
FG_DONE = "38;2;59;196;61"       # BTN.done #3bc43d
BG_DONE = "48;2;231;248;232"     # pale     #e7f8e8
FG_DONT = "38;2;194;128;61"      # BTN.dont #c2803d
BG_DONT = "48;2;248;240;232"     # pale     #f8f0e8
def isdir(rel): return os.path.isdir(os.path.join(WT, rel))
#  the pager's message line echoes the spell that ran, so "did the ROW go away?"
#  must read the ROWS — the bullet-led lines — not the whole frame.
def rows(frame): return [l for l in frame.split("\n") if l.lstrip().startswith("●")]

pid, fd = start(["todo", "CLK"])
pan = sip(fd)
check("panel-painted", "[ ✔  ✗]" in pan, repr(pan[:400]))
check("panel-replaced-the-done-label", "[done]" not in pan, repr(pan[:400]))
dn = sgr_before(RAW["last"], " ✗".encode())
check("dont-button-fg", dn is not None and FG_DONT in dn, repr(dn))
check("dont-button-bg-is-pale", dn is not None and BG_DONT in dn, repr(dn))
check("wt-present-before", isdir("work/CLK-001") and not isdir("work/done/CLK-001"))

press(fd, 2, 96)                                   # the panel's ✓ on CLK-001
f7 = sip(fd)
stop(pid, fd)
check("done-click-set-the-Now-pair", "Now: DONE" in readfile("todo/CLK/CLK-001.mkd"),
      repr(readfile("todo/CLK/CLK-001.mkd")[:120]))
check("done-click-moved-the-wt",
      isdir("work/done/CLK-001") and not isdir("work/CLK-001"))
check("done-click-dropped-the-row",
      not any("CLK-001" in l for l in rows(f7)) and any("CLK-002" in l for l in rows(f7)),
      repr(rows(f7)))

#  ✗ on a wt-LESS ticket: the pair changes, there is no worktree to move, and
#  nothing errors.  CLK-001 is closed now, so CLK-004 has moved up to row 2.
pid, fd = start(["todo", "CLK"])
pan2 = sip(fd)
check("dont-row-painted", "CLK-004" in pan2, repr(pan2[:300]))
press(fd, 2, 99)                                   # the panel's ✗ on CLK-004
f8 = sip(fd)
stop(pid, fd)
check("dont-click-set-the-Now-pair", "Now: DONT" in readfile("todo/CLK/CLK-004.mkd"),
      repr(readfile("todo/CLK/CLK-004.mkd")[:120]))
check("dont-click-needs-no-wt", not isdir("work/done/CLK-004"))
check("dont-click-dropped-the-row",
      not any("CLK-004" in l for l in rows(f8)), repr(rows(f8)))

print("DONE" if fails == 0 else "FAILS=%d" % fails)
sys.exit(1 if fails else 0)
