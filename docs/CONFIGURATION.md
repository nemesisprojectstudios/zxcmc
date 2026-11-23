# Configuration reference

This document was generated from the source (both `zxcmc.ahk` and `zxcmc.ks`; where the two intentionally diverge, it is called out). Line references use `zxcmc.ahk`; the `.ks` counterpart is at the same logic location a few lines later.

## Contents

1. [`keybinds.cfg` grammar](#keybindscfg-grammar)
2. [Key syntax](#key-syntax)
3. [Command actions and prefixes](#command-actions-and-prefixes)
4. [Shell detection + bash validation](#shell-detection--bash-validation)
5. [Key-remap output grammar](#key-remap-output-grammar)
6. [Macro token grammar (structured macros)](#macro-token-grammar-structured-macros)
7. [`zxcmcsettings.ini`](#zxcmcsettingsini)
8. [`theme.cfg`](#themecfg)

---

## `keybinds.cfg` grammar

One plain-text file, UTF-8, next to the script. Read as UTF-8; written as UTF-8 **without** BOM with CRLF line endings, atomically via `keybinds.cfg.tmp` + rename (`SaveConfig`, `zxcmc.ahk:1073`).

```conf
; comment lines start with a semicolon and are skipped entirely

; ---- Default profile (headerless): command bindings ----
KEY;PAYLOAD                     ; a command binding
*KEY;PAYLOAD                     ; "*" prefix = saved DISABLED
KEY[ahk_exe chrome.exe];PAYLOAD  ; "[wintitle]" suffix = per-app scope
*#Z[ahk_exe chrome.exe];start chrome   ; disabled + scoped, composable

; hotstring-triggered command binding (hs: prefix)
hs:btw;by the way

; pixel-triggered command binding (px: prefix)
px:100,200,FF0000,to;msgbox color hit

; ---- separator: 3+ dashes switches to the key-remap section ----
-------------

; ---- additional profiles get a header; each restarts in its own command section ----
[Profile:Work]
set:DoRepeatOutputs;1
set:ShellCmd;fish
macro:greet;hello world{Enter}

; ---- a remap whose per-remap Send mode was saved (Advanced mode) ----
#1;!Tab|SM:Event
```

Rules, exactly as implemented by the parser (`LoadConfig`, `zxcmc.ahk:855`) and writer (`SaveConfig`):

- A **binding line** is `keypart ; payload`, split at the **first** `;` only — extra semicolons stay in the payload. Both parts must be non-empty after trimming, else the line is rejected.
- `keypart` = optional `*` (disabled) + key + optional `[scope]` suffix. The scope is any AutoHotkey WinTitle criterion.
- A literal `;` inside an action is written `{SEMICOLON}` (unescaped on load, escaped on save).
- Lines beginning with `;` are comments; blank lines are skipped.
- `[Profile:Name]` starts a profile section; the **Default profile has no header**. After a profile header the section resets to *command* — each profile needs its own `---` separator before its remaps.
- `[Macros]` is a **legacy global-macro section** (`name;sequence` lines) that is read into the Default profile's macro library; it is never written back (the app writes `macro:` lines instead).
- `macro:Name;sequence` stores a macro in the enclosing profile's library; `set:Key;Value` stores a per-profile setting. Both may appear anywhere inside a profile section.
- `|SM:Mode` at the end of a remap payload is that binding's per-remap Send mode (Advanced mode only). It is always parsed, but only applied while Advanced mode is on.
- **Pixel triggers** (`px:`) must be `px:X,Y,RRGGBB,to|from`; **hotstring triggers** (`hs:`) must not contain `|`.
- Malformed lines, invalid keys, empty profile names and duplicate ids are **skipped, logged, and reported** (the report dialog shows up to 10 rejected lines, then "... and N more"). Duplicate ids: the last one wins.
- Saving writes every profile: settings (`set:`) first, macros (`macro:`), then command bindings, `-------------`, then remaps; disabled bindings get the `*` prefix, scoped ones the `[scope]` suffix.
- The active profile saved in the INI is restored at launch; if its name is not in the file, an empty profile is created rather than falling back to Default (so closing without saving never loses the selection).

---

## Key syntax

Accepted for both the bound key and (when the entire action is text syntax) remap outputs:

- **AHK symbols:** `#` = Win, `^` = Ctrl, `!` = Alt, `+` = Shift. Example: `#^G` = Win+Ctrl+G.
- **Text syntax:** `WIN+CTRL+ALT+G` — with or without plus signs (`win g` also works). Word boundaries are respected, so words like "waltz" are never mangled.
- **Single characters** are written as-is: any letter A–Z or digit 0–9 (case-insensitive; canonicalized to upper case).
- **Multi-character keys** must use their canonical AHK spellings from the built-in key list (`Escape`, `Numpad0`…`Numpad9`, `AppsKey`, `F1`–`F24`, `Media_Play_Pause`, `LButton`…`XButton2`, …). The complete list is shown at the bottom of the in-app **Usage Guide** tab and lives in `class Keys` (`Keys.List`) in the source — the single authoritative list shared by the editor picker and the macro recorder.

<details>
<summary>Full multi-character key list (from <code>Keys.List</code>)</summary>

Escape, Tab, Enter, Space, Backspace, Delete, Insert, PgUp, PgDn, Home, End, Up, Down, Left, Right, F1–F24, Numpad0–9, NumpadEnter, NumpadAdd, NumpadSub, NumpadMult, NumpadDiv, NumpadDot, NumpadIns, NumpadDel, NumpadClear, NumpadUp, NumpadDown, NumpadLeft, NumpadRight, NumpadHome, NumpadEnd, NumpadPgUp, NumpadPgDn, LButton, RButton, MButton, XButton1, XButton2, AppsKey, PrintScreen, Pause, ScrollLock, CapsLock, Media_Play_Pause, Media_Stop, Media_Next, Media_Prev, Volume_Mute, Volume_Up, Volume_Down, Browser_Back, Browser_Forward, Browser_Refresh, Browser_Stop, Browser_Search, Browser_Favorites, Browser_Home

</details>

---

## Command actions and prefixes

A *Command Mapper* action is dispatched by its first character(s) (`BindCmd`, `zxcmc.ahk:1820`):

| Action | Prefix | Behavior in `zxcmc.ahk` | Behavior in `zxcmc.ks` |
|---|---|---|---|
| `taskmgr` | *(none)* | Runs hidden through `cmd.exe`: `cmd /c taskmgr`. | Runs hidden through the **selected shell** (fallback `/bin/sh` off-Windows) — `cmd.exe` cannot be assumed off-Windows. |
| `&sudo apt update` | `&` | Runs through the shell selected in Settings (hidden or visible per the console setting). | Same (see [shell detection](#shell-detection--bash-validation)). |
| `>Hello world` | `>` | Sends text/keys (`Send`) instead of running a program. | Same. |
| `@MsgBox "hi"` | `@` | Runs AutoHotkey code by writing it to a temp script (`ZxCMC_expr_<id>.ahk` in `%TEMP%`) and launching `A_AhkPath` on it. **Not available in compiled builds** (status message + log). | Same, plus the usual Keysharp caveats around `A_AhkPath` (see KNOWN-ISSUES). |
| `&&foo`, `>>foo`, `@@foo` | doubled | Escape hatch: strip one character and run through the default (no-prefix) handler. | Same, except the default handler is the *selected shell* off-Windows. |

The editor's **Test** button does not apply prefix dispatch: in the `.ahk` it runs commands through `cmd.exe` directly; in the `.ks` it routes through the selected shell — the same dispatcher the binding will use.

### Shell detection + bash validation

The Settings tab's *Shell for & commands* control offers the shells actually installed on the device (`DetectShells`, `zxcmc.ahk:680`):

- **Windows:** `cmd` via `COMSPEC`, Windows PowerShell and `pwsh` at their standard locations or PATH, and Git Bash (explicitly preferred over a bare PATH search, which can surface WSL's `System32\bash.exe`). Detection is **runtime**-branched, so a cross-compiled assembly probes the platform it runs on.
- **Linux/macOS:** the user's `$SHELL` first, then every existing entry from `/etc/shells` (deduplicated by basename); the POSIX basics (`/bin/sh`, `/bin/bash`) are probed when `/etc/shells` is missing or unreadable. The list is never empty.

Semantics per shell family: `cmd` → `/c`; `powershell`/`pwsh` → `-NoProfile -Command`; everything else → `-c` with escaped internal quotes.

**Bash syntax validation:** when the selected shell is bash, every command is first validated with `bash -n` (temp file in `%TEMP%`, swept at startup); a failing command is logged and NOT executed. Other POSIX shells skip validation (their syntax differs and could be false-rejected).

---

## Key-remap output grammar

Accepted output forms (`BuildKeyOutput`, `zxcmc.ahk:1790`):

| You write | Sent as | Effect |
|---|---|---|
| `!Tab` | `!{Tab}` | Single key with modifiers: Alt+Tab. |
| `!Tab 2` (or `!{Tab} 2`) | `!{Tab 2}` | **Repeat form:** hold Alt, press Tab twice. |
| `{Enter}{Enter}abc` | as-is | **Macro string:** full AHK `Send` syntax, sent verbatim. |
| `zx` | as-is | **1:N remap:** types `z` then `x` (unknown word bases are macro text, not braced keys). |
| `macro:Name` | resolved | Replays the named library macro; a broken reference is reported instead of firing. |

Text syntax is accepted for outputs too (`WIN+CTRL+ALT+G`, `win g`) — but only when the *entire* action is text syntax, so macro strings containing words like "alt" are never mangled.

With **Advanced mode** on, a remap binding may also carry a per-remap Send mode (the editor's *Send mode* dropdown, persisted as the `|SM:Mode` marker) and each structured-macro key action may carry a per-token mode (`#SM:Mode`).

---

## Macro token grammar (structured macros)

A structured macro is a `|`-separated token sequence stored in the active profile's macro library like any other macro (`macro:Name;<tokens>`). A literal `|` inside a parameter is stored as `{PIPE}`. Example (`examples/keybinds-example.cfg`):

```
macro:Testing;mm:20,0,rel|w:500|mm:-40,0,rel|w:500|mm:20,0,rel|rw:echo "Hello there"|loop:Loop1:3|rw:echo "hs"|endloop:Loop1
```

| Token | Meaning |
|---|---|
| `trg:press\|release\|repeat\|pixel` | Trigger mode (default press). |
| `rbuf:ms` / `rdel:ms` | Repeat-mode buffer/delay. |
| `px:x,y,RRGGBB,to\|from` | Pixel trigger (a watcher fires the macro). |
| `kd:Key` / `ku:Key` | Key down / up. |
| `kp:Key[:holdMs][#SM:Mode]` | Key press, optionally held for holdMs. |
| `w:ms` | Wait. |
| `run:cmd` / `rw:cmd` | Shell command (proceeds immediately / waits for return). |
| `mm:x,y,rel\|abs[,hold:Key]` | Mouse move, optionally holding a key or button during the move. |
| `loop:Name:Count` … `endloop:Name` | Repetition (loops need unique names; every loop must be closed). |
| `sq:string` | Raw `Send`-syntax sequence. |
| `snd:string` | Full AHK `Send()` syntax (`{Raw}/{Blind}/{Text}`, `{VK}/{SC}/{U+}/{ASC nnnnn}`, `DownR/DownTemp`) — Advanced mode only. |
| `#SM:Mode` (trail of a key token) | Per-token Send mode (Advanced mode only). |

The interpreter (`RunMacroSequence` / `ExecuteMacroToken`) is fault-tolerant: bad numbers wait 0 ms, unknown tokens are logged and skipped, and a runaway loop is aborted after 100,000 actions.

---

## `zxcmcsettings.ini`

Section `[SETTINGS]`, next to the script. Encoding is normalized automatically on first load: **the AutoHotkey suite keeps it UTF-16 with a BOM** (the only Unicode encoding the Win32 INI APIs support); **the Keysharp port normalizes to BOM-less UTF-8**. Either suite can read the other's output for the ASCII values stored here. See `examples/zxcmcsettings-zxlinuxexample.ini`.

| Key | Default | Range | Meaning |
|---|---|---|---|
| `DoRepeatOutputs` | `0` | 0–1 | Keep repeating a remap's output while the bound key is physically held (remaps only — commands never repeat). |
| `RepeatBuffer` | `0` | 0–1000 ms | Pause after the first output, before the held-repeat loop starts. |
| `RepeatDelay` | `0` | 0–500 ms | Pause between repeats while held. |
| `ActiveProfile` | `Default` | any name | Profile active at startup. |
| `ShellCmd` | `cmd` | shell Id | Shell for `&` commands — a detected-shell Id. Backward compatible with the older `"cmd"`/`"powershell"` values; an unknown Id falls back to the first detected shell. |
| `ShellHidden` | `1` | 0–1 | `1` = hide the console when `&` commands run. |
| `GuiVisible` | `1` | 0–1 | `1` = show the window at launch. Set to `0` when you hide the window or launch with `--silent`; the state persists. |
| `StartSuspended` | `0` | 0–1 | `1` = start with all triggers suspended until you press Unsuspend. |
| `Autosave` | `0` | 0–1 | `1` = save `keybinds.cfg` silently ~0.5 s after every change. |
| `AdvancedMode` | `0` | 0–1 | `1` = show the Send-mode layer (default Send mode, per-remap/token overrides, AHK Send action). |

Notes:

- The repeat settings, shell selection and console visibility are **per-profile** — they are written through to the active profile's `set:` lines in `keybinds.cfg` on every change, and re-loaded on a profile switch. The INI copies are the app-level fallback.
- `DoRepeatOutputs`, `RepeatBuffer`, `RepeatDelay`, `ActiveProfile`, `ShellCmd` and `ShellHidden` are written by the single exit hook (every exit path).
- `StartSuspended`, `Autosave` and `AdvancedMode` are persisted **immediately** when toggled in the Settings tab.
- `DoStartup` is *not* persisted — it is seeded from whether the startup shortcut/launcher exists.

---

## `theme.cfg`

Optional, UTF-8, `Key=Value` lines; `;` comments; unknown keys ignored. Colors are `RRGGBB` hex (no `#`), validated — an invalid value is logged and the built-in preset is used for that key, so a hand-corrupted file can never break GUI construction. See `examples/theme-example.cfg`.

| Key | Example | Meaning |
|---|---|---|
| `Background` | `1E1E1E` | Window and list background. |
| `Control` | `3A3A3A` | Button/checkbox face color (effective under Keysharp; AutoHotkey ignores background colors on native buttons). |
| `Text` | `FFFFFF` | Text color. |
| `Hint` | `9E9E9E` | Dimmed empty-state text color. Preset per theme to pass WCAG AA (dark: `9E9E9E`, light: `595959`). |
| `Transparency` | `255` | Window opacity, 16–255 (255 = opaque; 0 would be unrecoverable, so it is clamped to 16). |
| `Auto` | `1` | `1` = follow the Windows dark/light app mode automatically (reads `HKCU\...\Themes\Personalize`, `AppsUseLightTheme`). **Windows-only** — elsewhere the registry read fails harmlessly and the dark preset is used. |

Built-in presets: **Dark** `1E1E1E / 3A3A3A / FFFFFF / 9E9E9E / 255` (default), **Light** `F3F3F3 / EDEDED / 1A1A1A / 595959 / 255` (chosen when `Auto=1` and the system uses light mode). Explicit keys override the chosen preset individually.
