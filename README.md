# ZxCMC

**Zx's Crossplatform Macro Client** - cross-platform hotkey remapping, hotstrings, pixel triggers and macros, inspired by TGMacro.

ZxCMC is a keyboard remapper and command launcher for power users: bind any key combination to a shell command, to another key press, or to a recorded macro, optionally scoped to a single application window. It is a single, binary-free script with no installer and no runtime dependencies beyond the interpreter — written in [AutoHotkey](https://www.autohotkey.com/) v2 syntax and shipped as several runnables: `zxcmc.ahk` (AutoHotkey v2.0, Windows-only) and `zxcmc.ks` (a mechanical mirror of the same code for [Keysharp](https://github.com/keysharp-org/Keysharp), the cross-platform .NET port, covering Windows/Linux/macOS). All bindings live in one plain-text file, `keybinds.cfg`, next to the script, and every feature is also reachable from a borderless GUI and a tray menu.  
Pre-compiled binaries live in the `dist` directory (compiled via Keysharp):
- zxcmc.cks - corresponds to zxcmc.ahk
- zxcmc-ks.cks - corresponds to zxcmc.ks
- zxcmc-ks-noprocesspriority - corresponds to zxcmc.ks, with lines 47-50 removed, as some Linux distributions/desktop environments refuse to parse `try ProcessSetPriority("AboveNormal")` properly, which results in exceptions.

---

## Contents

1. [Features](#features)
2. [Requirements & installation](#requirements--installation)
3. [Quick start](#quick-start)
4. [Configuration reference](#configuration-reference)
5. [Usage guide](#usage-guide)
6. [Troubleshooting](#troubleshooting)
7. [Project layout](#project-layout)
8. [Status & caveats](#status--caveats)
9. [License](#license)

---

## Features

**Binding types**

- **Command mapper** — bind a hotkey to a shell command. Actions support prefixes: none (hidden `cmd.exe`), `&` (run through the shell selected in Settings, with bash syntax validation when the shell is bash — see [Shell detection](#shell-detection--bash-validation-in-progress)), `>` (send text/keys instead of running a program), `@` (run AutoHotkey code via a temporary script), and doubled `&&`/`>>`/`@@` (literal prefix passthrough).
- **Key remapper** — bind a hotkey to another key or combination (`!Tab`), with a repeat form (`!Tab 2` = hold Alt, press Tab twice) full macro strings sent as-is (`{Enter}{Enter}abc`), and 1:N remaps (`zx` types `z` then `x`).
- **Trigger kinds** — every command binding can trigger on a **hotkey**, a **hotstring** (typed text + ending character) or a **pixel** (screen pixel turns to/from a color); remaps stay hotkey-only; hotkey triggers offer interception types (`~` passthrough, `$` force hook, `*` wildcard, combinable). Bindings can be scoped to one program (`[ahk_exe chrome.exe]`).
- **Macro Builder** — build macros one action at a time (key press/down/up with hold duration, waits, shell commands with wait-until-return, mouse moves with a held key, raw Send sequences), with named loops, per-macro trigger modes (press/release/repeat-while-held/pixel-watch), in-place Clone of the selected actions, an AHK Send action for full `Send()` syntax (Advanced mode) and a Test-run button.
- **Profiles** — bindings, macros, repeat settings, the shell selection and (Advanced) Send modes bundled per profile: switch/clone/create/rename/export/import/delete, plus copy-the-selection-to-any-profile (Save to..., picked from a dropdown of existing profiles).
- **Macro recorder** — record your keystrokes from the tray menu (`InputHook`-based, keyboard-only, `Esc` stops, recorded text auto-escaped for `Send`); recordings are saved into the macro library (per profile).
- **Macros tab** — a dedicated tab managing the macro library (create/edit/delete, run once as a test, and "Assign to key..."). A key remap whose output is `macro:Name` replays the named library entry, so editing a macro updates every binding that references it. The library persists per profile as `macro:` lines in `keybinds.cfg` (a legacy `[Macros]` section is still read into the Default profile).
- **Per-app window scoping** — append a WinTitle criterion such as `[ahk_exe chrome.exe]` to any binding to make it fire only in matching windows.

**Management**

- **Profiles** — unlimited profiles in one file (`[Profile:Name]` sections; the `Default` profile is headerless), switchable from the tray (radio-checked submenu, `New…` via InputBox) or the Settings tab; the active profile persists across restarts.
- **Per-binding enable/disable** — a `Status` column, a *Toggle On/Off* sidebar button for selected rows, a right-click *Enable/Disable* menu item, and a `*` prefix in the config file for bindings saved disabled.
- **Conflict detection** — saving a binding that already exists (same key + scope) prompts to overwrite; the same key+scope registered in the *other* type (command vs. remap) warns that only the later registration responds.
- **Undo** — 10-level undo stack (Ctrl+Z, sidebar *Undo*, tray), snapshotting the active profile's name and full binding set.
- **Live filters** — a filter box above each list narrows rows as you type (case-insensitive substring over key + action + scope), with distinct empty states for "no bindings" vs. "no matches".

**GUI & feedback**

- **Tray menu** — single-click show/hide, Save/Load, Import…/Export…, a Profiles submenu, *Record Macro…*, Exit.
- **Suspend / Start as suspended** — the sidebar *Suspend* button pauses ALL trigger interception until unsuspended (F1, the window and the tray stay live); the Settings tab can start the app suspended, so triggers arm only after a manual unsuspend.
- **Autosave** — optional: changes persist silently a moment after every edit.
- **Advanced mode** — reveals the Send-mode layer: a default Send mode (per profile), per-remap Send mode overrides in the binding editor, per-action modes and the AHK Send action in the Macro Builder (Send/Input/Event/Play/InputThenPlay, doc-verified on both engines).
- **Validated import with a confirmation gate** — imported configs are parsed fully first; malformed lines are rejected and reported; nothing activates until you choose *Yes* (activate) / *No* (import disabled) / *Cancel* (undo).
- **Themes + auto dark/light** — `theme.cfg` with validated `RRGGBB` colors and window transparency; `Auto=1` follows the Windows dark/light app mode (Windows-only; the Keysharp port falls back to the dark preset).
- **Repeat-while-held** — optional: remap outputs keep repeating while the bound key is physically held, with buffer/delay settings.
- **Status strip** — transient feedback bar at the bottom (auto-clears after ~4 s), alongside tray tips.
- **Keyboard navigation** — F1 show/hide, Del delete, Enter edit, Ctrl+Z undo, right-click row menus; F1 itself is rebindable.
- **Tooltips** on the settings controls and filter boxes (Windows-only in the Keysharp port).
- **Row icons** — shipped `icons/gear.ico` (commands) and `icons/keyboard.ico` (remaps); degrade silently if missing.
- **Error log** — timestamped entries in `%APPDATA%\ZxCMC\error.log`; logging never throws.
- **Atomic config saves** — writes go to a `.tmp` file that atomically replaces the target, so a crash or disk-full can never destroy your config.
- **Dirty-state exit protection** — every exit path funnels through one vetoable exit hook that prompts about unsaved changes.

---

## Requirements & installation

### Windows — AutoHotkey v2.0 (canonical)

1. Install [AutoHotkey v2.0](https://www.autohotkey.com/) or later v2.x. The script declares `#Requires AutoHotkey v2.0` and deliberately avoids v2.1-only syntax, so plain v2.0 works.
2. Run `zxcmc.ahk` (double-click it, or `AutoHotkey.exe zxcmc.ahk` from a terminal).
3. Optional: launch with `--silent` to start with the window hidden (this is the argument the built-in *Run at startup* shortcut uses).
4. Optional static check: `AutoHotkey.exe /Validate /ErrorStdOut zxcmc.ahk` (exit code 0 = clean load).

Expected files next to the script (all optional — sensible defaults apply if missing): `keybinds.cfg`, `theme.cfg`, `zxcmcsettings.ini`, `icons/`.

### Windows / Linux / macOS — Keysharp

1. Install [Keysharp](https://github.com/keysharp-org/Keysharp) ([docs](https://keysharp-org.github.io/KeysharpDocs), [releases](https://github.com/keysharp-org/Keysharp/releases)). It is a .NET-based reimplementation targeting AutoHotkey v2.1-alpha.33 compatibility and requires the **.NET 10** runtime. Per its own README it is *under active development and not yet recommended for production*; Windows has the broadest compatibility.
2. Run `zxcmc.ks` with the `keysharp` executable. Note the port adds `#Requires capability InputMonitoring, InputControl, WindowMonitoring` — off-Windows, first runs may show authorization dialogs, and a denied capability makes Keysharp exit with an error naming it.
3. Running through Keysharp on Linux devices defaults to using the active user's GTK theme. A misconfigured GTK theme may cause visual artifacting or discoloration on the UI. Linux therefore does not support configuration through `theme.cfg` (see later), while Windows defaults to applying the `theme.cfg` configuration as Keysharp runs GUI operations through native WinUI. 

**Runtime support caveat:** hotkeys, `InputHook`, `Send` and `GetKeyState` are **Full on Windows but Partial on Linux/macOS** per the porting notes — X11 support is broader; on Wayland, global hotkey capture varies by compositor (foreign windows on COSMIC/generic wlroots expose no PID). See [Status & caveats](#status--caveats).

### The `.cks` files in `dist/`

`dist/` contains Keysharp assembly builds (`--compile asm` output) of both scripts, produced during validation:

| File | Compiled from | Changes |
|---|---|---|
| `dist/zxcmc.cks` | `zxcmc.ahk` | Unchanged |
| `dist/zxcmc-ks.cks` | `zxcmc.ks` | Unchanged |
| `dist/zxcmc-ks-noprocesspriority.cks` | `zxcmc.ks` | Lines 47-50 removed |
---

## Quick start

### First launch

Run any `zxcmc` script or compiled assembly. On first launch ZxCMC loads `keybinds.cfg` from the script's folder (creating an empty `Default` profile if the file is missing), shows the main window, and puts a tray icon in the notification area. Nothing else is installed.

Press **F1** at any time — in any application — to hide or show the ZxCMC window. A single left-click on the tray icon does the same.

### An example keybinds.cfg (Windows)

```ahk
#ESCAPE;taskmgr
#Q;alacritty
#Z;start zen.exe
#^!U;alacritty --hold -e winget upgrade --all --include-unknown
-------------
#1;!Tab
#C;!F4
+!z;!Tab 2
```

| Line | Meaning |
|---|---|
| `#ESCAPE;taskmgr` | **Win+Esc → open Task Manager.** `#` = Win. The key name is case-insensitive (`ESCAPE` canonicalizes to `Escape`). No prefix on the action → runs hidden through `cmd.exe`. |
| `#Q;alacritty` | **Win+Q → launch Alacritty** (must be on PATH), hidden `cmd.exe`. |
| `#Z;start zen.exe` | **Win+Z → launch Zen.** Uses cmd's `start` so the browser detaches from the hidden console. |
| `#^!U;alacritty --hold -e winget upgrade --all --include-unknown` | **Win+Ctrl+Alt+U** (`^` = Ctrl, `!` = Alt) → upgrade all winget packages in an Alacritty window that stays open afterwards (`--hold -e`). |
| `-------------` | **Separator** (any line of 3+ dashes): everything above is in the *command* section of the profile; everything below is the *key remap* section. |
| `#1;!Tab` | **Win+1 → send Alt+Tab** — the classic window switcher. Single-key remap form: `!Tab` sends `Alt+Tab`. |
| `#C;!F4` | **Win+C → send Alt+F4** — closes the active window. |
| `+!z;!Tab 2` | **Shift+Alt+Z → hold Alt, press Tab twice** — the repeat form. Lowercase `z` is fine (canonicalized to `Z`); `!Tab 2` cycles two entries in the Alt+Tab ring. |

Every line is `KEY;ACTION` — the split happens at the *first* semicolon only, so actions may contain more semicolons (literal ones are written `{SEMICOLON}`; see the [grammar](#keybindscfg-grammar)).

### Adding your first binding through the editor

1. Click **+ Add Binding** in the sidebar. The *Binding Editor* opens.
2. Pick the **Type**: *Command* or *Key Remap*. (The action field relabels to *Command:* / *Output key:*.)
3. Fill the **Keybind**. Either type AHK symbols directly (`#^G`), text syntax (`WIN+CTRL+G`, `win g`), or use the **Picker**: tick the Ctrl/Alt/Shift/Win checkboxes and choose a category (*Letters, Digits, Function Keys, Navigation, Editing, Numpad, Mouse, Media, Browser, System*) and key from the dropdowns — the composed key (e.g. `#^G`) is written into the Keybind field.
4. Enter the **action**: e.g. `&sudo apt update` (shell), `>Hello world` (types text), `notepad` (hidden cmd.exe) — or for a remap, an output like `!F4`, `!Tab 2`, or `{Enter}{Enter}abc`.
5. Optionally set a **Window scope** (e.g. `ahk_exe chrome.exe`) so the binding only fires in matching windows. `[`, `]` and `;` are rejected here (they cannot round-trip through the config file).
6. Press **Test** to run the command (hidden `cmd.exe`) or send the remap output once, without repeat-while-held. Note: Test does not apply the `&`/`>`/`@` prefix dispatch — commands run through `cmd.exe` directly.
7. Press **Save**. The hotkey registers **immediately** (the change is live) and the config is marked dirty.
8. Click **Save** (or **Apply**) in the sidebar to write `keybinds.cfg` to disk. Until you do, the change exists only in memory — exiting will prompt about unsaved changes.

---

## Configuration reference

### `keybinds.cfg` grammar

One plain-text file, UTF-8, next to the script. Read as UTF-8; written as UTF-8 **without** BOM with CRLF line endings, atomically via `keybinds.cfg.tmp` + rename.

```ahk
; comment lines start with a semicolon and are skipped entirely

; ---- Default profile (headerless): command bindings ----
KEY;PAYLOAD                     ; a command binding
*KEY;PAYLOAD                     ; "*" prefix = saved DISABLED
KEY[ahk_exe chrome.exe];PAYLOAD  ; "[wintitle]" suffix = per-app scope
*#Z[ahk_exe chrome.exe];start chrome   ; disabled + scoped, composable

; ---- separator: 3+ dashes switches to the key-remap section ----
-------------

; ---- additional profiles get a header; each restarts in its own command section ----
[Profile:Work]
#O; outlook.exe

; ---- the global macro library: name;Send-sequence ----
[Macros]
greet;hello world{Enter}
login;user{Tab}pass{Enter}
-------------
#1;!Tab
```

Rules, exactly as implemented by the parser (`LoadConfig`) and writer (`SaveConfig`):

- A **binding line** is `keypart ; payload`, split at the **first** `;` only — extra semicolons stay in the payload. Both parts must be non-empty after trimming, else the line is rejected.
- `keypart` = optional `*` (disabled) + key + optional `[scope]` suffix. The scope is any AutoHotkey WinTitle criterion.
- A literal `;` inside an action is written `{SEMICOLON}` (unescaped on load, escaped on save).
- Lines beginning with `;` are comments; blank lines are skipped.
- `[Profile:Name]` starts a profile section; the **Default profile has no header** (older tools can still read the file). After a profile header the section resets to *command* — each profile needs its own `---` separator before its remaps.
- Malformed lines, invalid keys, empty profile names and duplicate ids are **skipped, logged, and reported** (the report dialog shows up to 10 rejected lines, then "... and N more"). Duplicate ids: the last one wins.
- Saving writes every profile: commands first, `-------------`, then remaps; disabled bindings get the `*` prefix, scoped ones the `[scope]` suffix.

### Key syntax

Accepted for both the bound key and (when the entire action is text syntax) remap outputs:

- **AHK symbols:** `#` = Win, `^` = Ctrl, `!` = Alt, `+` = Shift. Example: `#^G` = Win+Ctrl+G.
- **Text syntax:** `WIN+CTRL+ALT+G` — with or without plus signs (`win g` also works). Word boundaries are respected, so words like "waltz" are never mangled.
- **Single characters** are written as-is: any letter A–Z or digit 0–9 (case-insensitive; canonicalized to upper case).
- **Multi-character keys** must use their canonical AHK spellings from the built-in key list (`Escape`, `Numpad0`…`Numpad9`, `AppsKey`, `F1`–`F24`, `Media_Play_Pause`, `LButton`…`XButton2`, …). The complete list is shown at the bottom of the in-app **Usage Guide** tab and lives in `class Keys` (`KEY_LIST`) in the source — the single authoritative list shared by the editor picker and the macro recorder.

<details>
<summary>Full multi-character key list (from <code>KEY_LIST</code>)</summary>

Escape, Tab, Enter, Space, Backspace, Delete, Insert, PgUp, PgDn, Home, End, Up, Down, Left, Right, F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12, F13, F14, F15, F16, F17, F18, F19, F20, F21, F22, F23, F24, Numpad0, Numpad1, Numpad2, Numpad3, Numpad4, Numpad5, Numpad6, Numpad7, Numpad8, Numpad9, NumpadEnter, NumpadAdd, NumpadSub, NumpadMult, NumpadDiv, NumpadDot, NumpadIns, NumpadDel, NumpadClear, NumpadUp, NumpadDown, NumpadLeft, NumpadRight, NumpadHome, NumpadEnd, NumpadPgUp, NumpadPgDn, LButton, RButton, MButton, XButton1, XButton2, AppsKey, PrintScreen, Pause, ScrollLock, CapsLock, Media_Play_Pause, Media_Stop, Media_Next, Media_Prev, Volume_Mute, Volume_Up, Volume_Down, Browser_Back, Browser_Forward, Browser_Refresh, Browser_Stop, Browser_Search, Browser_Favorites, Browser_Home

</details>

### Command actions and prefixes

A *Command Mapper* action is dispatched by its first character(s):

| Action | Prefix | Behavior |
|---|---|---|
| `taskmgr` | *(none)* | Runs hidden through the selected shell (`.ks`; fallback `/bin/sh` off-Windows) / `cmd.exe` (`.ahk`): `cmd /c taskmgr` on Windows with the default `cmd` selection. **In `zxcmc.ahk` the no-prefix branch is always `cmd.exe`.** **In `zxcmc.ks` it runs through the selected shell**, since `cmd.exe` does not exist off-Windows — a documented divergence between the two scripts. |
| `&sudo apt update` | `&` | Runs through the shell selected in Settings (hidden or visible per the console setting). With the shell-detection layer: the detected shell's family decides the invocation — `cmd` → `/c`, `powershell`/`pwsh` → `-NoProfile -Command`, POSIX shells (`bash`, `zsh`, `sh`, …) → `-c` with escaped internal quotes. **If the selected shell is bash, the command is first validated with `bash -n`** (see below). |
| `>Hello world` | `>` | Sends text/keys (`Send`) instead of running a program. |
| `@MsgBox "hi"` | `@` | Runs AutoHotkey code by writing it to a temp script (`ZxCMC_expr_<id>.ahk` in `%TEMP%`) and launching `A_AhkPath` on it. **Not available in compiled builds** (status message + log). |
| `&&foo`, `>>foo`, `@@foo` | doubled | Escape hatch: strip one character and run through the default (no-prefix) handler, so the extra `&`/`>`/`@` is passed literally. |

#### Shell detection + bash validation

The Settings tab's *Shell for & commands* control offers the shells actually installed on the device, discovered by a runtime detection layer implemented identically in both scripts, so a compiled binary finds the right shells on whichever platform it runs:

- **Detected shells** (populated at startup, before the setting is read):
  - **Windows**: `cmd` (always present), `powershell` (via its absolute `System32\WindowsPowerShell\v1.0` path), `pwsh` (PATH search, then `PowerShell\7` fallback), `bash` (Git Bash: Git's install paths first, labeled "Git Bash"; a PATH-found `bash.exe` excluding WSL's `System32\bash.exe`). Order: cmd, powershell, pwsh, Git Bash.
  - **Unix** (fully dynamic): parse `/etc/shells` (the canonical list of valid login shells), keeping only entries that exist; fall back to probing `/bin/sh` and `/bin/bash` if the file is missing; dedupe by Id. The user's login shell (`SHELL` env) is listed first.
- **Each shell entry** carries an `Id` (lowercased executable basename — this is what gets persisted), display `Name`, absolute `Path`, `ArgStyle` (`/c`, `-Command`, `-c`) and a `Family` (`cmd`, `ps`, `posix`) that decides invocation semantics.
- **The INI setting `ShellCmd` becomes a shell Id** (`"cmd"`, `"powershell"`, `"pwsh"`, `"bash"`, `"zsh"`, `"sh"`, …). Backward compatible with the previous `"cmd"`/`"powershell"` values; if the saved Id is not among the detected shells, the first detected shell is used (and the setting updated).
- **Bash syntax validation:** when the selected shell's Id is `bash`, `&`-commands are first written to a temp file and checked with `bash -n` via `RunWait`; a non-zero exit means the command is **not executed** — the syntax error is logged and shown in the status strip. Validation is always-on for bash (it costs milliseconds) and only for bash — other shells have incompatible syntax and could false-reject.
- Startup cleanup of leftover temp scripts is extended to the validation files (`ZxCMC_syntax_*.sh`).

#### Per-profile macros and settings

Macros and the three repeat settings (`DoRepeatOutputs`, `RepeatBuffer`, `RepeatDelay`) are per-profile. They persist inside each profile section:

```
[Profile:Work]
set:RepeatBuffer;120
macro:login;user{Tab}pass{Enter}
#L; outlook.exe
-------------
```

A legacy global `[Macros]` section (from older versions) is read into the Default profile on load; new saves always write per-profile. Hotstring (`hs:`) and pixel (`px:`) triggers are just bindings and live on the same keypart grammar.

### Key remap outputs

A *Key Remapper* action is translated to a `Send` string by three grammar forms (`BuildKeyOutput`):

| You write | Sent as | Effect |
|---|---|---|
| `!Tab` | `!{Tab}` | Single key with modifiers: Alt+Tab. |
| `!Tab 2` (or `!{Tab} 2`) | `!{Tab 2}` | **Repeat form:** hold Alt, press Tab twice. |
| `{Enter}{Enter}abc` | as-is | **Macro string:** full AHK `Send` syntax, sent verbatim. |

Text syntax is accepted for outputs too (`WIN+CTRL+ALT+G`, `win g`) — but only when the *entire* action is text syntax, so macro strings containing words like "alt" are never mangled.

### `zxcmcsettings.ini`

Section `[SETTINGS]`. **In the AutoHotkey suite this file is UTF-16 with a BOM** — the only Unicode encoding the Win32 INI APIs support; ZxCMC normalizes it automatically on first load if it finds another encoding; **do not resave it as UTF-8** (values would mojibake or silently drop on some locales). **The Keysharp port normalizes to BOM-less UTF-8 instead** — Keysharp's .NET-based `IniRead`/`IniWrite` read and write plain text, so the `.ks` converts the shipped file once on its first load. Either suite can read the other's output for the ASCII values stored here.

| Key | Default | Range | Meaning |
|---|---|---|---|
| `DoRepeatOutputs` | `0` | 0–1 | Keep repeating a remap's output while the bound key is physically held (remaps only — commands never repeat). |
| `RepeatBuffer` | `0` | 0–1000 ms | Pause after the first output, before the held-repeat loop starts. |
| `RepeatDelay` | `0` | 0–500 ms | Pause between repeats while held. |
| `ActiveProfile` | `Default` | any name | Profile active at startup. |
| `ShellCmd` | `cmd` | shell Id | Shell for `&` commands — now a **detected-shell Id** (see above). Backward compatible with the older `"cmd"`/`"powershell"` values; if the saved Id is not among the detected shells, the first detected shell is used (and the setting updated). |
| `ShellHidden` | `1` | 0–1 | `1` = hide the console when `&` commands run. |
| `GuiVisible` | `1` | 0–1 | `1` = show the window at launch. Set to `0` when you hide the window or launch with `--silent`; the state persists. |

`DoStartup` is *not* persisted — it is seeded from whether the startup shortcut exists. All settings are written by the single exit hook (every exit path), not on every change. The shipped file contains only the three repeat keys; the rest are added on first exit.

### `theme.cfg`

Optional, UTF-8, `Key=Value` lines; `;` comments; unknown keys ignored. Colors are `RRGGBB` hex (no `#`), validated — an invalid value is logged and the built-in preset is used for that key, so a hand-corrupted file can never break GUI construction.

| Key | Example | Meaning |
|---|---|---|
| `Background` | `1E1E1E` | Window and list background. |
| `Control` | `2D2D2D` | Button/checkbox face color (themed for contrast; AutoHotkey ignores it on native buttons — visual no-op there, effective under Keysharp). |
| `Text` | `FFFFFF` | Text color. |
| `Hint` | `9E9E9E` | Dimmed empty-state text color. Preset per theme to pass WCAG AA (dark: `9E9E9E`, light: `595959`). |
| `Transparency` | `255` | Window opacity, 0–255 (255 = opaque). |
| `Auto` | `1` | `1` = follow the Windows dark/light app mode automatically (reads `HKCU\...\Themes\Personalize`, `AppsUseLightTheme`). **Windows-only** — the Keysharp port guards the registry read and falls back to the dark preset elsewhere. |

Built-in presets: **Dark** `1E1E1E / 2D2D2D / FFFFFF / 9E9E9E / 255` (default), **Light** `F3F3F3 / FFFFFF / 1A1A1A / 595959 / 255` (chosen when `Auto=1` and the system uses light mode). Explicit keys override the chosen preset individually. The repo ships a fully commented `theme.cfg` with everything remarked out.

---

## Usage guide

> The in-app **Usage Guide tab** is the complete reference: seven pages (Getting Started, Keys & Remaps, Commands & Shells, Macros & Builder, Hotstrings & Pixel, Profiles, Window & Files) covering every feature below in more depth, including the full key-name inventory and the complete macro token grammar.

### GUI tour

The main window (borderless; title *"ZxCMC - Key remapper utility"*) is organized as a left **sidebar** of action buttons, four **tabs**, and a bottom **status strip**. Hiding the window (F1, Esc, tray, or its Close event) never exits the app — it keeps running in the tray. Exit is only via the *Exit* button or tray *Exit*, both of which respect unsaved changes.

**Sidebar buttons**

| Button | What it does |
|---|---|
| **+ Add Binding** | Opens the binding editor in Add mode. |
| **Delete** | Deletes every **selected** row of the current tab; confirms when more than one row is selected. |
| **Toggle On/Off** | Flips Enabled on every selected row. |
| **Clear Bindings** | Removes **all** bindings in the *active* profile (asks first). |
| **Undo** | Restores the last change (10 levels deep). |
| **Apply** | Writes `keybinds.cfg` (identical to Save — kept for continuity). |
| **Save** | Writes `keybinds.cfg` atomically; status shows "Saved N bindings". |
| **Load** | Re-reads `keybinds.cfg` from disk, re-applies the theme, and reports any rejected lines. |
| **Import** | Loads a `.cfg` from anywhere via the confirmation gate (below). |
| **Export** | Writes every profile to a `.cfg` of your choice (defaults to `save.cfg`). |
| **Exit** | The single exit path (settings always save; bindings prompt if dirty). |

**Tabs**

1. **Command Mapper** and 2. **Key Remapper** — a ListView with columns *Key · Command/Output · Status · Window*, a live **Filter** box above it, and an empty-state hint: "No bindings yet - press + Add Binding" (no rows at all) or "No matches for the current filter" (filter excluded everything). Rows carry a gear (command) or keyboard (remap) icon.
3. **Settings** — *Repeat outputs while held (remaps only)* enable toggle; *Repeat buffer (ms)* (0–1000); *Repeat delay (ms)* (0–500); *Run at startup (requires admin)*; *Shell for & commands*; *& console window* (Hidden/Visible); *Profile* dropdown + **Switch**. Tooltips explain each.
4. **Usage Guide** — the built-in quick reference, including the full key-name list. This README agrees with it.

**Status strip** — transient messages at the bottom (save/load/import feedback, hotkey registration failures, "Recording - press Esc to stop", …) that auto-clear after about 4 seconds.

### Managing bindings

- **Add** — *+ Add Binding* → editor (see [Quick start](#adding-your-first-binding-through-the-editor)). The editor dialog owns its own state, so two editors can be open at once without cross-contamination. Multi-line command actions are collapsed to one line on save.
- **Edit** — double-click a row, press **Enter** (when the list has focus), or right-click → *Edit...*. Saving an edit updates the same binding id; changing key/scope re-registers it.
- **Delete** — select rows (click; Ctrl+click / Shift+click for several), press **Del** or the sidebar *Delete*. Only one row selected: deletes immediately; several: confirms "Delete N bindings?". Right-click → *Delete* removes that one row.
- **Enable/disable** — sidebar *Toggle On/Off* on selected rows, or right-click → *Enable/Disable binding*. The Status column shows the state; disabled bindings are registered as hotkey variants in the Off state (they survive reloads; the config stores them with the `*` prefix).
- **Conflicts** — on save: same key+scope already bound in this profile → *overwrite?* prompt; same key+scope in the **other** type → warning that "Only the later registration will respond" (you can continue anyway).
- Every mutation pushes an **undo snapshot** and marks the config dirty.

### Profiles

A profile bundles **bindings, macros and the three repeat settings** — everything except app-level preferences. All live in `keybinds.cfg`: `Default` is the headerless section at the top, every other profile under `[Profile:Name]`, with its macros (`macro:Name;sequence`) and settings (`set:Key;Value`) stored inside its section.

**The Profiles tab** (between Macros and Settings):

| Control | What it does |
|---|---|
| **Active profile** (dropdown + **Switch**) | Lists every profile; Switch makes the selection active (unregisters/re-registers hotkeys, swaps macros and repeat settings). The tray's Profiles submenu does the same. The choice persists (INI `ActiveProfile`). |
| **New profile...** | A dialog with three modes: *Create from current settings* (full copy of the active profile), *Clone an existing profile* (copy from any other), *Create new empty profile*. Creates and switches to the new profile. |
| **Save** | Saves the active profile to disk. Saving into **Default** shows a one-time warning (never asked again). |
| **Save As...** | Deep-copies the active profile (bindings + macros + settings) under a new name and switches to it. |
| **Rename** | Type the new name into the field, press Rename. Disabled while Default is active (Default cannot be renamed). |
| **Export... / Import...** | Writes the active profile as a single-profile importable `.cfg`; import parses a profile file into matching profiles (merge — existing profiles are kept). |
| **Delete profile / Clear profile** | Non-Default profiles are deleted (with confirmation); Default is cleared of its contents instead. Either way the active profile's hotkeys are unregistered and Default's registered. |

**Sidebar → Save to...**: copies the *selected* rows (bindings, remaps or hotstrings by id; macros by name) into any profile — creating it if needed — **without switching profiles**. Combined with multi-select this is a bulk copy between profiles.

Undo (Ctrl+Z) covers every profile operation.

### Import: the confirmation gate

*Import…* (sidebar or tray) loads any `.cfg` file **without activating anything** — a deliberate safety gate for untrusted configs:

1. The file is parsed fully; malformed lines are rejected and summarized (up to 10 shown with line numbers and reasons, plus the total).
2. A dialog offers three choices:
   - **Yes** — activate the enabled bindings now.
   - **No** — import everything **as disabled** (every binding, in every profile).
   - **Cancel** — **undo this import**; memory returns to the pre-import state.
3. The import replaces all in-memory profiles (the undo stack preserves the previous state). Export does the reverse: writes *all* profiles to the chosen file.

### Macro recorder and the Macros tab

Available from the tray menu: **Record Macro...**

- Your existing bindings are unregistered while recording (they must not fire); the status strip and a tray tip announce "Recording - press Esc to stop". Only one recording can run at a time.
- **Keystrokes pass through to the active window** while being captured, and **only the keyboard is captured** — mouse clicks are never recorded.
- **Esc stops** the recording (Esc itself is not included).
- Recorded text is auto-escaped for `Send` — literal `!`, `#`, `+`, `^`, `{`, `}` are stored in braced form so they replay as characters, not modifiers. A 100,000-character safety cap applies.
- When you stop, you are asked for a **macro name**; the sequence is saved into the **global macro library** (undo-able, persisted in the `[Macros]` section of `keybinds.cfg`).

The **Macros tab** manages the library:

| Button | Action |
|---|---|
| **New...** / **Edit...** (or double-click a row) | Name + Send-syntax sequence editor (names cannot contain `; [ ] *`). |
| **Delete** | Removes the macro (with confirmation). |
| **Run once** | Sends the sequence to the active window as a test. |
| **Assign to key...** | Opens the binding editor in Add mode with the output prefilled as `macro:Name`. |

Because bindings reference macros **by name** (`macro:Name` as a Key Remap output), editing a macro instantly updates every binding that uses it; a broken reference is reported (status + error log) instead of firing.

#### Macro Builder (structured macros)

**Builder...** on the Macros tab opens the builder: build a macro **one action at a time** in a ListView — key press / key down / key up, wait (ms), run shell command (via the selected shell), mouse move (absolute or relative, optionally holding a key or button during the move), and `Loop start`/`Loop end` markers to repeat parts of the sequence (unbalanced loops are rejected at save). Add action.../Edit action.../Delete/Up/Down manage the rows; **Test run** executes the current sequence once; values are validated per type.

Each structured macro carries its own **trigger**:

| Trigger | Behavior |
|---|---|
| On key press | Default: fires when the assigned key goes down. |
| On key release | Fires on key-UP (a dedicated up-variant is registered only for keys that need it). |
| Repeat while held | Repeats the sequence with its own buffer/delay (ms) values, overriding the global repeat settings. |
| Pixel watch | A watcher polls a screen pixel (`X`, `Y`, color `RRGGBB`, "turns to"/"turns from") and fires on the color transition, re-arming when it clears. Pixel capture may be unavailable on some platforms (Wayland); an unsupported watcher disables itself and logs once. |

Structured macros persist in the same `[Macros]` section as a compact token line (e.g. `login` could be `trg:press|kp:{Tab}|w:120|run:echo done|loop:2|kp:a|w:50|endloop`); plain Send-string macros coexist and keep opening in the simple sequence editor.

### Keyboard shortcuts

| Shortcut | Where | Action |
|---|---|---|
| **F1** | Global (any app) | Hide/show the ZxCMC window. And yes — F1 itself is rebindable. |
| **Del** | Main window, a list has focus | Delete the selected rows (confirms if >1). |
| **Ctrl+Z** | Main window, a list has focus | Undo the last change (10 levels). |
| **Enter** | Main window, a list has focus | Edit the first selected row. |
| **Double-click** | A row | Edit that binding. |
| **Right-click** | A row | Menu: *Enable/Disable binding*, *Edit...*, *Delete*. |
| **Esc** | Main window | Hide the window (does not exit). |

Del and Ctrl+Z pass through to the focused control when a list is not focused; all app hotkeys use the `$` prefix so ZxCMC's own `Send` output can never re-trigger them.

### Tray menu

| Item | Notes |
|---|---|
| *(single left-click)* | Show/hide the window — the default action, mapped to one click. |
| **Show / Hide** | Same as the single click. |
| **Save / Load** | Write / re-read `keybinds.cfg`. |
| **Import... / Export...** | The gated import and full export. |
| **Profiles ▸** | One radio item per profile, checked on the active one, plus *New...*. |
| **Record Macro...** | Starts the macro recorder. |
| **Exit** | The single exit path (prompts on unsaved changes). |

---

## Troubleshooting

- **First stop: the error log.** Everything that goes wrong is logged with a timestamp to `%APPDATA%\ZxCMC\error.log` (created on demand; entries capped at 2000 characters so a huge import cannot balloon it; logging itself can never crash the app). Check it after any "… - see error log" status message.
- **Rejected config lines.** Load and Import report malformed lines (bad key, empty profile name, duplicates, non-`KEY;PAYLOAD` shape) in a dialog with line numbers, and log the same. Fix the line or remove it — parsing skips rejects and continues.
- **"Hotkey registration failed for X"** — the key could not be registered (typically another application owns it, or the OS rejects it). The failure is logged; the binding stays in the list so you can rebind it to another key.
- **Settings not saving / mojibake in the INI.** `zxcmcsettings.ini` must stay **UTF-16** — the app re-normalizes it automatically if it finds UTF-8/ANSI, but don't edit-and-resave it as UTF-8 yourself. Settings are written on exit, so kill the app gracefully.
- **`@` actions don't run in a compiled build** — by design; the `@` prefix needs `A_AhkPath` and is disabled when the script is compiled.
- **Startup toggle says it needs admin** — creating/removing the Startup-folder shortcut requires elevation; relaunch as administrator to use it.
- **Known-fixed bugs & their stories** — the engineering audit in [`ANALYSIS.md`](ANALYSIS.md) (especially the §6 addendum) documents every fixed defect and the reasoning, e.g. the mangled `!Tab 2` repeat form, text-syntax mangling of words like "waltz", duplicate GUI rebuilds on show, wrong LVM color constants, and the INI encoding direction.
- **Keysharp/Linux specifics** — capability prompts on first run; hotkey capture Partial off-Windows (see [Status & caveats](#status--caveats)); startup links are freedesktop `.desktop` entries whose generated name may not match the toggle's check.

---

## Project layout

| Path | Purpose |
|---|---|
| `zxcmc.ahk` | The canonical implementation — AutoHotkey v2.0 app for Windows (~2250 lines, class-based state, hotkey engine, GUI, tray, config I/O). |
| `zxcmc.ks` | The Keysharp cross-platform port — a mechanical mirror of the `.ahk` plus platform branches (`#Requires capability`, `#if WINDOWS` guards, restructured UpDown controls) so the two stay diffable. |
| `keybinds.cfg` | Your bindings — the shipped example doubles as the working config, loaded from the script's folder. |
| `zxcmcsettings.ini` | Settings file (UTF-16 with BOM; see [reference](#zxcmcsettingsini)). |
| `theme.cfg` | Commented theme example; every key documented inline. |
| `icons/` | Row icons for the list views — `gear.ico` (command bindings), `keyboard.ico` (key remaps). |
| `dist/` | Keysharp compile artifacts: `zxcmc.cks` (from the `.ahk`) and `zxcmc-ks.cks` (from the `.ks`). *(gitignored)* |
| `.gitignore` | Ignores local notes, test harnesses, configuration/save files and build temp files |

---

## Status & caveats

1. **Hotkeys / InputHook / Send / GetKeyState: Full on Windows, Partial on Linux/macOS.** X11 support is broader; on Wayland, global hotkey capture and PID availability vary by compositor.
2. **Capability prompts** on first run off-Windows (`#Requires capability InputMonitoring, InputControl, WindowMonitoring`); a denied capability exits with an error naming it.
3. **Startup toggle off-Windows**: `FileCreateShortcut` writes a freedesktop `.desktop` launcher/symlink whose generated filename may not match the `FileExist` seeding check — the toggle's initial state may need path adjustment per platform (Windows unchanged).
4. **ListView theming** via Win32 LVM messages is compiled out off-Windows (GTK treeview); only the `+Background` GUI option remains.
5. **Tooltips** (settings controls, filter boxes) are Windows-only — absent elsewhere, never fatal.
6. **UpDown UI** differs: Keysharp UpDowns are standalone NumericUpDown controls (no buddy Edit), so the Settings tab looks slightly different in the `.ks`.
7. **`Sleep()`** uses `Application.DoEvents()` internally in Keysharp — the repeat-while-held loop and recorder should still work but warrant smoke-testing.
8. **MsgBox** modality options are ignored; **TrayTip** never mutes (Keysharp).

The **shell detection + bash validation** layer is implemented in both scripts and covered by the same compile-validation loop as the rest (see *Command actions and prefixes* above).

---

## License

Licensed under the MIT license.
