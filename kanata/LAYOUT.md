# Effective layout (Corne / borne)

Drawn to match the **Corne's physical keys** — the board you're learning on. The MacBook
gets the same *logical* layers via kanata, just in standard key positions (note at the end).

Legend: `^`=Ctrl · `Cmd`=⌘ · `Opt`=⌥ · `Sh`=⇧ · `·`=unchanged · `(O)`=rotary knob.

---

## BASE layer (normal typing)

```
 `    1    2    3    4    5                      6    7    8    9    0    -
Tab   Q    W    E    R    T    PgUp      Home    Y    U    I    O    P    [
Caps  A    S    D    F    G    PgDn      End     H    J    K    L    ;    '
Shift Z    X    C    V    B   (O)L       (O)R    N    M    ,    .    /    ]
                Ctrl Cmd  Ent          Space Cmd  Fn
                  (hold Ent = Nav)
```

- `Caps` = tap **Esc** / hold **Command layer**  ·  `Fn` (right-outer thumb) = **Symbol layer**
  (both holds come from Corne firmware — no kanata needed on the Corne)
- Left thumb: **Ctrl · Cmd · Enter** — and **hold the Enter thumb = Nav layer** (tap still = Enter)
- Right thumb: **Space · Cmd · Fn**
- Right-pinky column: `-  [  '  ]`   ·   Inner columns: **PgUp/PgDn** (left), **Home/End** (right)
- `(O)L` left knob: turn = arrow left/right, press = Mute   ·   `(O)R` right knob: turn = Volume, press = RGB

---

## NAV layer  —  hold the **left-inner (Enter) thumb**

```
     U          I          O
   word<       Up        word>
     J          K          L
   Left       Down       Right
```

- Hold the **Enter thumb** (its tap is still Enter); the right hand drives `IJKL`.
- Add **Shift** (left pinky) to select — e.g. Nav+Shift+`O` = select word-right, Nav+Shift+`L` = select right char.
- `U`/`O` = word-left/right (Option+arrow on macOS). Everything else passes through.
- *(Firmware nav today, so word-moves are macOS-flavored. The OS-flavored version moves into kanata when you switch it on.)*

---

## SYMBOL layer  —  hold **Fn** (Corne right-outer thumb)   *(Corne only)*

```
num    F1   F2   F3   F4   F5         F6   F7   F8   F9   F10
top     ·    ·    ·    ·    ·          {    (    )    }    `
home    ·    ·    ·    ·    ·          [    ]    \    |    =
bot     ·    ·    ·    ·    ·          -    +    ·    ·    ·
```

- Right **home row** carries your priority keys: `H`=`[`, `J`=`]`, **`K`=backslash**, **`L`=pipe**.
- Left hand keeps typing letters; the number row gives `F1`-`F10`.

---

## COMMAND layer  —  hold **Caps**  (Corne firmware; macOS flavor)

```
num    F1   F2   F3   F4   F5        F6   F7   F8   F9   F10    (the - key -> F11)
top    ^Q   ^W   ^E   ^R   ^T       ShCmdZ ^U  ^I   ^O   ^P
home  CmdA  ^S   ^D   ^F   ^G        ^H   ^J   ^K   ^L   ^;
bot   CmdZ CmdX CmdC CmdV  ^B        ^N   ^M   ^,   ^.   ^/
```

- **Cmd** on the clipboard cluster (`Cmd A` select-all, `Cmd C/V/X`, `Cmd Z` undo, `Y`=`Sh Cmd Z` redo);
  **Ctrl** everywhere else (great for terminal/readline).
- Cursor motion lives on the **Nav layer** above.
- *Firmware can't auto-switch OS, so this layer is macOS-baked.* On Windows the clipboard
  keys would send Win+key — use the physical **Ctrl** thumb there (Ctrl+C etc. is native on
  Windows), or ask me to add a Mac/Win toggle.

---

## Per-board differences (physical only)

| Function | MacBook | Corne (borne) |
|---|---|---|
| Esc / Command-layer | Caps (tap/hold) | Caps, left-pinky home (tap/hold) |
| Symbol layer | *not on MacBook* — use physical `[ ] \` `|` | **Fn** thumb (firmware) |
| Space | spacebar | right **inner** thumb |
| Enter / **Nav-layer** | Return | left **inner** thumb (tap = Enter, hold = Nav) |
| Cmd | beside spacebar | both **middle** thumbs |
| Ctrl | normal | left-**outer** thumb |
| Arrows | arrow cluster | **Nav layer** on `IJKL` (hold Enter thumb) |
| Home/End/PgUp/PgDn | nav/fn keys | inner columns |
| `[  ]  '  -` | top-right keys | right-pinky column |
| backslash, pipe | physical / shifted | Symbol layer (`K`, `L`) |
| Knobs | none | turn = arrows / Volume; press = Mute / RGB |

---

## What kanata does now (and doesn't)

**kanata is a MacBook-only helper** — it adds the **Caps-hold Command layer**, mirroring
what the Corne's firmware does natively. It does **not** add a Symbol or Nav layer on the
MacBook (the MacBook has physical `[ ] \ |` and arrow keys; use them). Config is a single
self-contained file per OS, no includes:

- `~/src/dotfiles/kanata/kanata.macos.kbd` -> `~/.config/kanata/kanata.kbd` (macOS flavor)
- `~/src/dotfiles/kanata/kanata.ctrl.kbd`  (Windows/Linux flavor; clean Ctrl everywhere)

**Corne:** fully self-sufficient in Vial firmware — BASE, NAV, SYMBOL, and COMMAND all
work with no kanata at all.

**To (re)start kanata on macOS** after config edits:
`sudo launchctl kickstart -k system/com.github.jtroo.kanata`
