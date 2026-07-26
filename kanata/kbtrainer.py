#!/usr/bin/env python3
"""kbtrainer - a tiny keyboard muscle-memory trainer for the new layout.

Stages (in order):
  1  letters: home row
  2  letters: + top row
  3  letters: all 26
  4  letters: common words
  5  layers : the Symbol layer   [ ]  (backslash)  |  { } ( )  ` = - +

One keypress at a time, live feedback, tracks accuracy + speed, shows the
recommended finger for each key, and highlights the keys you miss most.
Score >=90% to pass a stage and unlock the next one.   ('f' = focus drill.)
Progress is saved to ~/.kbtrainer.json.   Esc = end a drill,  Ctrl-C = quit.

Run:  python3 kbtrainer.py
"""

import json
import os
import random
import sys
import time

ESC = chr(27)
CR = chr(13)
BSL = chr(92)            # backslash, built without typing one

GREEN, RED, CYAN, DIM, BOLD, YELL, UNDER = "32", "31", "36", "2", "1", "33", "4"


def ansi(code, s):
    return ESC + "[" + code + "m" + s + ESC + "[0m"


# ---- read a single keypress without waiting for Enter ----
try:
    import termios
    import tty

    def getch():
        fd = sys.stdin.fileno()
        old = termios.tcgetattr(fd)
        try:
            tty.setcbreak(fd)
            return sys.stdin.read(1)
        finally:
            termios.tcsetattr(fd, termios.TCSADRAIN, old)
except ImportError:                      # Windows
    import msvcrt

    def getch():
        return msvcrt.getwch()


HOME = "asdfghjkl"
TOP = "qwertyuiop"
BOT = "zxcvbnm"
SYMS = "[]" + BSL + "|{}()" + "`=-+"

WORDS = ("the and for you are with this that have from they will your what when "
         "make code type hand home keys list move fast slow over jump lazy dog").split()

SYM_HINT = ("  Hint: hold Fn (Corne right-outer thumb) or Tab (MacBook), then right hand:" +
            chr(10) + "        H J K L = [ ] " + BSL + " |     Y U I O = { ( ) }     N M = - +")


def _fset(keys, label, d):
    for ch in keys:
        d[ch] = label


# recommended touch-typing finger for every key
FINGER = {}
_fset("`1qaz", "L pinky", FINGER)
_fset("2wsx", "L ring", FINGER)
_fset("3edc", "L mid", FINGER)
_fset("45rtfgvb", "L index", FINGER)
_fset("67yuhjnm", "R index", FINGER)
_fset("8ik,", "R mid", FINGER)
_fset("9ol.", "R ring", FINGER)
_fset("0p;/-=", "R pinky", FINGER)

# on the Symbol layer each symbol sits on an alpha key, so its finger is that
# key's finger (you also hold Fn / Tab to reach the layer)
SYM_FINGER = {
    "{": "R index", "(": "R index", ")": "R mid", "}": "R ring", "`": "R pinky",
    "[": "R index", "]": "R index", BSL: "R mid", "|": "R ring", "=": "R pinky",
    "-": "R index", "+": "R index",
}


STAGES = [
    {"key": "home",    "name": "Letters - home row",     "chars": HOME,             "prereq": None},
    {"key": "top",     "name": "Letters - + top row",    "chars": HOME + TOP,       "prereq": "home"},
    {"key": "bottom",  "name": "Letters - all 26",       "chars": HOME + TOP + BOT, "prereq": "top"},
    {"key": "words",   "name": "Letters - common words", "words": WORDS,            "prereq": "bottom"},
    {"key": "symbols", "name": "Layers  - Symbol layer", "chars": SYMS, "prereq": "bottom", "hint": SYM_HINT},
]

PASS = 0.90
PROG_PATH = os.path.expanduser("~/.kbtrainer.json")


def load_progress():
    try:
        with open(PROG_PATH) as f:
            p = json.load(f)
        p.setdefault("passed", [])
        p.setdefault("best", {})
        return p
    except Exception:
        return {"passed": [], "best": {}}


def save_progress(p):
    try:
        with open(PROG_PATH, "w") as f:
            json.dump(p, f)
    except Exception:
        pass


def shown(ch):
    return "space" if ch == " " else ch


def pct(a):
    return ansi(GREEN if a >= PASS else YELL, "{:.0f}%".format(a * 100))


def summarize(tries, miss, correct, done, times):
    if done == 0:
        print("  (nothing attempted)")
        return 0.0
    acc = correct / done
    print()
    print("  " + ansi(BOLD, "accuracy") + "  " + pct(acc) +
          ansi(DIM, "   ({}/{})".format(correct, done)))
    if times:
        avg = sum(times) / len(times)
        kpm = 60.0 / avg if avg > 0 else 0
        print("  " + ansi(BOLD, "speed   ") + "  {:.2f}s/key".format(avg) +
              ansi(DIM, "   (~{:.0f} keys/min)".format(kpm)))
    weak = sorted([c for c in tries if miss.get(c, 0) > 0], key=lambda c: -miss[c])[:6]
    if weak:
        print("  " + ansi(YELL, "work on ") + " " +
              "   ".join(ansi(BOLD, shown(c)) + ansi(DIM, " x" + str(miss[c])) for c in weak))
    return acc


def drill_chars(chars, rounds=30, hint=None, fingers=None):
    weights = {c: 1.0 for c in chars}
    miss = {c: 0 for c in chars}
    tries = {c: 0 for c in chars}
    times = []
    correct = done = 0
    print()
    if hint:
        print(ansi(DIM, hint))
        print()
    print("  Type the highlighted key.  " + ansi(DIM, "Esc to stop."))
    print()
    pool = list(weights)
    while done < rounds:
        target = random.choices(pool, weights=[weights[c] for c in pool])[0]
        fh = (fingers or {}).get(target, "")
        sys.stdout.write("  " + ansi(DIM, "{:>2}/{}".format(done + 1, rounds)) +
                         "   " + ansi(BOLD + ";" + CYAN, " " + shown(target) + " ") +
                         (("   " + ansi(YELL, fh)) if fh else "") + "   ")
        sys.stdout.flush()
        t0 = time.time()
        k = getch()
        dt = time.time() - t0
        if k == ESC:
            print()
            break
        done += 1
        tries[target] += 1
        if k == target:
            correct += 1
            times.append(dt)
            weights[target] = max(0.4, weights[target] * 0.8)
            print(ansi(GREEN, "OK") + ansi(DIM, "  {:.2f}s".format(dt)))
        else:
            miss[target] += 1
            weights[target] += 2.5
            got = "space" if k == " " else repr(k)[1:-1]
            print(ansi(RED, "miss") + ansi(DIM, "  got " + got))
    return summarize(tries, miss, correct, done, times)


def render_word(word, pos):
    out = ""
    for i, w in enumerate(word):
        if i < pos:
            out += ansi(GREEN, w)
        elif i == pos:
            out += ansi(UNDER + ";" + BOLD, w)
        else:
            out += ansi(DIM, w)
    sys.stdout.write(CR + "  " + out + "        ")
    sys.stdout.flush()


def drill_words(words, count=12):
    miss, tries, times = {}, {}, []
    correct = total = 0
    print()
    print("  Type each word.  " + ansi(DIM, "Esc to stop."))
    print()
    for _ in range(count):
        word = random.choice(words)
        pos = 0
        aborted = False
        while pos < len(word):
            render_word(word, pos)
            t0 = time.time()
            k = getch()
            dt = time.time() - t0
            if k == ESC:
                aborted = True
                break
            exp = word[pos]
            total += 1
            tries[exp] = tries.get(exp, 0) + 1
            if k == exp:
                correct += 1
                times.append(dt)
                pos += 1
            else:
                miss[exp] = miss.get(exp, 0) + 1
        if aborted:
            print()
            break
        render_word(word, pos)
        print("  " + ansi(GREEN, "OK"))
    return summarize(tries, miss, correct, total, times)


def menu(prog):
    print()
    print(ansi(BOLD, "  Keyboard trainer") + ansi(DIM, "    (q to quit)"))
    print()
    for i, st in enumerate(STAGES):
        passed = st["key"] in prog["passed"]
        unlocked = (st["prereq"] is None) or (st["prereq"] in prog["passed"])
        best = prog["best"].get(st["key"])
        num = str(i + 1)
        if not unlocked:
            print(ansi(DIM, "  " + num + ". " + st["name"] + "   (locked)"))
            continue
        status = ansi(GREEN, "passed") if passed else ansi(CYAN, "open  ")
        extra = ansi(DIM, "  best " + "{:.0f}%".format(best * 100)) if best is not None else ""
        print("  " + num + ". " + st["name"] + "   [" + status + "]" + extra)
    print("  f. focus drill (pick your own keys)")
    print()
    sys.stdout.write("  choose 1-" + str(len(STAGES)) + ", f, or q: ")
    sys.stdout.flush()
    return getch()


def main():
    prog = load_progress()
    while True:
        choice = menu(prog)
        print()
        if choice in ("q", "Q", ESC):
            print("  bye - keep practicing!")
            return
        if choice in ("f", "F"):
            try:
                keys = input("  keys to drill (e.g. cp): ").strip()
            except EOFError:
                keys = ""
            keys = "".join(dict.fromkeys(ch for ch in keys if not ch.isspace()))
            if keys:
                drill_chars(keys, rounds=max(20, len(keys) * 10),
                            hint="Focus drill - use the finger shown, every rep.",
                            fingers=FINGER)
                print()
                sys.stdout.write(ansi(DIM, "  press any key for the menu..."))
                sys.stdout.flush()
                getch()
            continue
        if not choice.isdigit():
            continue
        idx = int(choice) - 1
        if idx < 0 or idx >= len(STAGES):
            continue
        st = STAGES[idx]
        if not ((st["prereq"] is None) or (st["prereq"] in prog["passed"])):
            print(ansi(YELL, "  Locked - pass '" + st["prereq"] + "' first."))
            continue
        if "words" in st:
            acc = drill_words(st["words"])
        else:
            fingers = SYM_FINGER if st["key"] == "symbols" else FINGER
            acc = drill_chars(st["chars"], hint=st.get("hint"), fingers=fingers)
        if acc > prog["best"].get(st["key"], 0.0):
            prog["best"][st["key"]] = acc
        if acc >= PASS and st["key"] not in prog["passed"]:
            prog["passed"].append(st["key"])
            print()
            print(ansi(GREEN, "  Passed!") + " next stage unlocked.")
        elif acc < PASS and acc > 0:
            print()
            print(ansi(YELL, "  {:.0f}% - reach {:.0f}% to pass.".format(acc * 100, PASS * 100)))
        save_progress(prog)
        print()
        sys.stdout.write(ansi(DIM, "  press any key for the menu..."))
        sys.stdout.flush()
        getch()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print()
        print("  bye - keep practicing!")
