# ZxCMC

**Zx's Crossplatform Macro Client** — cross-platform hotkey remapping, hotstrings, pixel triggers and macros, inspired by TGMacro.

ZxCMC is a keyboard remapper and command launcher for power users: bind any key combination to a shell command, to another key press, or to a recorded macro, optionally scoped to a single application window. All bindings live in one plain-text file, `keybinds.cfg`, next to the script, and every feature is also reachable from a tabbed GUI and a tray menu.

The project ships two source files:

| Runnable | Runtime | Platforms | Notes |
|---|---|---|---|
| `zxcmc.ks` | [Keysharp](https://github.com/keysharp-org/Keysharp) ([docs](https://keysharp-org.github.io/KeysharpDocs), [releases](https://github.com/keysharp-org/Keysharp/releases)) | Windows / Linux / macOS | **The supported runtime.** Written in AutoHotkey v2 syntax with platform branches (`#Requires capability`, `#if WINDOWS`). |
| `zxcmc.ahk` | Keysharp *or* plain [AutoHotkey v2.0](https://www.autohotkey.com/) | Windows | The original AutoHotkey-style source. Runs on both Keysharp and plain AutoHotkey v2.0 (GUI offsets are translated automatically — see [Building](#building)). |

Compiled `.cks` assemblies are **not committed** to the repository; they are built by [GitHub Actions](.github/workflows/build.yml) (one runner per target OS, since Keysharp cannot cross-compile) and attached to Releases on tagged commits.

Keysharp is a .NET-based reimplementation of AutoHotkey v2 (currently targeting v2.1-alpha.37 as of Keysharp 0.0.0.18) and requires the **.NET 10 runtime**. Per its own README it is under active development and **not yet recommended for production**; Windows has the broadest compatibility.

Pre-built assemblies are attached to GitHub **Releases** as CI-built `.cks` files named per platform (e.g. `zxcmc-windows-latest.cks`), produced for every tagged version.

---

## Contents

1. [Features](#features)
2. [Requirements & installation](#requirements--installation)
3. [Quick start](#quick-start)
4. [Configuration at a glance](#configuration-at-a-glance)
5. [Using ZxCMC](#using-zxcmc)
6. [Troubleshooting](#troubleshooting)
7. [Project layout](#project-layout)
8. [Status & caveats](#status--caveats)
9. [Known issues](#known-issues)
10. [Security](#security)
11. [Building](#building)
12. [License](#license)

---

## Features

**Binding types**

- **Command mapper** — bind a hotkey to a shell command. Actions support prefixes: none (runs through the default shell), `&` (run through the shell selected in Settings, with `bash -n` syntax validation when the shell is bash — see [Shell detection](docs/CONFIGURATION.md#shell-detection--bash-validation)), `>` (send text/keys instead of running a program), `@` (run AutoHotkey code via a temporary script), and doubled `&&`/`>>`/`@@` (literal prefix passthrough).
- **Key remapper** — bind a hotkey to another key or combination (`!Tab`), with a repeat form (`!Tab 2` = hold Alt, press Tab twice), full macro strings sent as-is (`{Enter}{Enter}abc`), and 1:N remaps (`zx` types `z` then `x`).
- **Trigger kinds** — every command binding can trigger on a **hotkey**, a **hotstring** (typed text + ending character) or a **pixel** (screen pixel turns to/from a color); remaps stay hotkey-only. Hotkey triggers offer interception types (`~` passthrough, `$` force hook, `*` wildcard, combinable). Bindings can be scoped to one program (`[ahk_exe chrome.exe]`) — honored by hotkey, hotstring and pixel triggers.
- **Macro Builder** — build macros one action at a time (key press/down/up with hold duration, waits, shell commands with wait-until-return, mouse moves with a held key, raw Send sequences, AHK-Send actions in Advanced mode), with named loops, per-macro trigger modes (press / release / repeat-while-held / pixel-watch), in-place Clone of selected actions, and a Test-run button.
- **Profiles** — bindings, macros, per-profile repeat settings, and (Advanced) Send modes bundled per profile: switch / clone / create / rename / export / import / delete, plus copy-the-selection-to-any-profile (Save to...).
- **Macro recorder** — record keystrokes from the tray menu (keyboard-only, `Esc` stops, recorded text is auto-escaped for `Send`); recordings are saved into the macro library of the active profile.
- **Macros tab** — manage the macro library (create/edit/delete, run once as a test, "Assign to key..."). A remap output of `macro:Name` replays the named library entry, so editing a macro updates every binding that references it.
- **Per-app window scoping** — append a WinTitle criterion such as `ahk_exe chrome.exe` to any binding to fire it only in matching windows.

**Management**

- **Profiles** — unlimited profiles in one file (`[Profile:Name]` sections; the `Default` profile is headerless), switchable from the tray or the Profiles tab; the active profile persists across restarts.
- **Per-binding enable/disable** — a Status column, a *Toggle On/Off* sidebar button, a right-click *Enable/Disable* menu item, and a `*` prefix in the config for bindings saved disabled.
- **Conflict detection** — saving a binding that already exists (same key + scope) prompts to overwrite; the same key+scope registered in the *other* type (command vs. remap) warns that only the later registration responds.
- **Undo** — 10-level undo stack (Ctrl+Z, sidebar *Undo*, tray) covering bindings and macros.
- **Live filters** — a filter box above each list narrows rows as you type, with distinct empty states for "no bindings" vs. "no matches".

**GUI & feedback**

- **Tray menu** — single-click show/hide, Save/Load, Import…/Export…, a Profiles submenu, *Record Macro…*, Exit.
- **Suspend / Start as suspended** — the sidebar *Suspend* button pauses ALL trigger interception until unsuspended (F1, the window and the tray stay live); the Settings tab can start the app suspended.
- **Autosave** — optional: changes persist silently a moment after every edit.
- **Advanced mode** — reveals the Send-mode layer: a default Send mode (per profile), per-remap Send mode overrides, per-token modes and the AHK Send action in the Macro Builder (Send/Input/Event/Play/InputThenPlay, doc-verified on both engines).
- **Validated import with a confirmation gate** — imported configs are parsed fully first; malformed lines are rejected and reported; nothing activates until you choose *Yes* (activate) / *No* (import disabled) / *Cancel* (undo). The Profiles tab's Import... uses the same gate.
- **Themes + auto dark/light** — `theme.cfg` with validated `RRGGBB` colors and window transparency; `Auto=1` follows the Windows dark/light app mode (Windows-only; elsewhere the dark preset is used).
- **Repeat-while-held** — optional: remap outputs keep repeating while the bound key is physically held, with buffer/delay settings.
- **Status strip** — transient feedback bar at the bottom (auto-clears after ~4 s), alongside tray tips.
- **Keyboard navigation** — F1 show/hide, Del delete, Enter edit, Ctrl+Z undo, right-click row menus; F1 itself is rebindable.
- **Row icons** — shipped `icons/gear.ico` (commands) and `icons/keyboard.ico` (remaps); degrade silently if missing.
- **Error log** — timestamped entries in `%APPDATA%\ZxCMC\error.log`; logging never throws.
- **Atomic config saves** — writes go to a `.tmp` file that atomically replaces the target, so a crash or disk-full can never destroy your config.
- **Dirty-state exit protection** — every exit path funnels through one vetoable exit hook that prompts about unsaved changes.

---

## Requirements & installation

### Windows / Linux / macOS — Keysharp (supported runtime)

1. Install [Keysharp](https://github.com/keysharp-org/Keysharp) ([documentation](https://keysharp-org.github.io/KeysharpDocs), [releases](https://github.com/keysharp-org/Keysharp/releases)). It requires the **.NET 10 runtime**. Windows currently has the broadest compatibility.
2. Run `zxcmc.ks` with the `keysharp` executable (or run a Release's compiled `.cks` assembly with Keysharp). The script declares `#Requires capability InputMonitoring, InputControl, WindowMonitoring` — off-Windows, first runs may show authorization dialogs, and a denied capability makes Keysharp exit with an error naming it.
3. Optional: launch with `--silent` to start with the window hidden (this is the argument the built-in *Run at startup* shortcut uses).

Expected files next to the script (all optional — sensible defaults apply if missing): `keybinds.cfg`, `theme.cfg`, `zxcmcsettings.ini`, `icons/`.

On Linux, Keysharp's GTK backend uses the active user's GTK theme; `theme.cfg` colors are effectively a Windows-only feature (Linux keeps its native look). A misconfigured GTK theme can produce visual artifacts or discoloration in the UI on Linux. On Windows, Keysharp renders GUI operations through native WinUI, so the `theme.cfg` configuration applies as documented.

### Windows — plain AutoHotkey v2.0 (works too)

`zxcmc.ahk` is written in AutoHotkey v2 syntax and works on plain AutoHotkey v2.0 as well as under Keysharp. Its tab layout uses `XC()`/`YC()` helper calls that emit Keysharp's tab-relative `xc`/`yc` options when the runtime supports them and computed absolute `x`/`y` coordinates (derived from the Tab control's display area) on AutoHotkey v2.0, so the same layout is produced on both. Only the pixel-trigger and theming caveats of Keysharp do not apply — plain AHK v2.0 has native Windows behavior.

### Runtime support caveat

Per Keysharp's porting notes, hotkeys, `InputHook`, `Send` and `GetKeyState` are **Full on Windows but Partial on Linux/macOS**. X11 support is broader; on Wayland, global hotkey capture varies by compositor (foreign windows on COSMIC/generic wlroots expose no PID). See [Status & caveats](#status--caveats).

---

## Quick start

### First launch

Run any `zxcmc` runnable. On first launch ZxCMC loads `keybinds.cfg` from the script's folder (creating an empty `Default` profile if the file is missing), shows the main window, and puts a tray icon in the notification area. Nothing else is installed.

Press **F1** at any time — in any application — to hide or show the ZxCMC window. A single left-click on the tray icon does the same.

### An example keybinds.cfg (Windows)

```conf
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
| `#ESCAPE;taskmgr` | **Win+Esc → open Task Manager.** `#` = Win. The key name is case-insensitive (`ESCAPE` canonicalizes to `Escape`). No prefix on the action → runs through the default shell. |
| `#Q;alacritty` | **Win+Q → launch Alacritty** (must be on PATH), hidden console. |
| `#Z;start zen.exe` | **Win+Z → launch Zen.** Uses cmd's `start` so the browser detaches from the hidden console. |
| `#^!U;...` | **Win+Ctrl+Alt+U** (`^` = Ctrl, `!` = Alt) → upgrade all winget packages in an Alacritty window that stays open afterwards (`--hold -e`). |
| `-------------` | **Separator** (any line of 3+ dashes): everything above is in the *command* section of the profile; everything below is the *key remap* section. |
| `#1;!Tab` | **Win+1 → send Alt+Tab** — the classic window switcher. |
| `#C;!F4` | **Win+C → send Alt+F4** — closes the active window. |
| `+!z;!Tab 2` | **Shift+Alt+Z → hold Alt, press Tab twice** — the repeat form. Lowercase `z` is fine (canonicalized to `Z`). |

Every line is `KEY;ACTION` — the split happens at the *first* semicolon only, so actions may contain more semicolons (literal ones are written `{SEMICOLON}`). The complete grammar — including hotstring (`hs:`), pixel (`px:`), per-profile macro (`macro:`) and settings (`set:`) lines — is documented in [docs/CONFIGURATION.md](docs/CONFIGURATION.md).

### Adding your first binding through the editor

1. Click **+ Add Binding** in the sidebar. The *Binding Editor* opens.
2. Pick the **Type**: *Command* or *Key Remap*. (The action field relabels to *Command:* / *Output key:*.)
3. Fill the **Keybind**. Either type AHK symbols directly (`#^G`), text syntax (`WIN+CTRL+G`, `win g`), or use the **Picker**: tick the Ctrl/Alt/Shift/Win checkboxes and choose a category (*Letters, Digits, Function Keys, Navigation, Editing, Numpad, Mouse, Media, Browser, System*) and key from the dropdowns — the composed key (e.g. `#^G`) is written into the Keybind field.
4. Enter the **action**: e.g. `&sudo apt update` (shell), `>Hello world` (types text), `notepad` (default shell) — or for a remap, an output like `!F4`, `!Tab 2`, or `{Enter}{Enter}abc`.
5. Optionally set a **Window scope** (e.g. `ahk_exe chrome.exe`) so the binding only fires in matching windows. `[`, `]` and `;` are rejected here (they cannot round-trip through the config file).
6. Press **Test** to run the command or send the remap output once, without repeat-while-held. Note: Test does not apply the `&`/`>`/`@` prefix dispatch — commands run through the default shell directly.
7. Press **Save**. The binding registers **immediately** (the change is live) and the config is marked dirty.
8. Click **Save** in the sidebar to write `keybinds.cfg` to disk. Until you do, the change exists only in memory — exiting will prompt about unsaved changes.

---

## Configuration at a glance

| File | Purpose | Reference |
|---|---|---|
| `keybinds.cfg` | All bindings, profiles, macros and per-profile settings. One plain-text UTF-8 file; written atomically (`.tmp` + rename), CRLF, no BOM. | [Full grammar](docs/CONFIGURATION.md#keybindscfg-grammar) |
| `zxcmcsettings.ini` | App preferences (repeat output, active profile, shell selection, GUI visibility, suspend-on-start, autosave, advanced mode). | [Settings reference](docs/CONFIGURATION.md#zxcmcsettingsini) |
| `theme.cfg` | Optional color theme + window transparency; `Auto=1` follows the Windows dark/light app mode. | [Theme reference](docs/CONFIGURATION.md#themecfg) |

Fully commented example files for all three live in [`examples/`](examples/).

---

## Using ZxCMC

The main window has a left sidebar of action buttons, **seven tabs** (Command Mapper, Key Remapper, Hotstrings, Macros, Profiles, Settings, Usage Guide), and a bottom status strip. The window is a standard resizable window (minimum size 800×600) and adapts its layout when resized. Closing or hiding the window (F1, Esc, tray, or its Close event) never exits the app — it keeps running in the tray. Exit is only via the sidebar *Exit* button or tray *Exit*, both of which respect unsaved changes.

The complete tour — sidebar buttons, binding editing, profiles, the export/import confirmation gate, the macro recorder and Macro Builder, keyboard shortcuts and the tray menu — is in [docs/USAGE.md](docs/USAGE.md). The app also ships this guide in its built-in **Usage Guide** tab.

**A note on trust:** ZxCMC executes what you configure — shell commands, key sends, and with the `@` prefix even AutoHotkey code. Treat `keybinds.cfg` files from other people like scripts. Read the full trust model, review checklist and release-verification guidance in [docs/SECURITY.md](docs/SECURITY.md).

---

## Troubleshooting

- **First stop: the error log.** Everything that goes wrong is logged with a timestamp to `%APPDATA%\ZxCMC\error.log` (created on demand; entries capped at 2000 characters; logging itself can never crash the app). Check it after any "… - see error log" status message.
- **Rejected config lines.** Load and Import report malformed lines (bad key, empty profile name, duplicates, non-`KEY;PAYLOAD` shape) in a dialog with line numbers. Fix the line or remove it — parsing skips rejects and continues. (Startup reports are suppressed under `--silent`, where a modal dialog would block invisibly — check the log instead.)
- **"Hotkey registration failed for X"** — the key could not be registered (typically another application owns it, or the OS rejects it). The failure is logged; the binding stays in the list so you can rebind it to another key.
- **Settings not saving / mojibake in the INI.** On AutoHotkey the INI must stay UTF-16 (the app re-normalizes it automatically); the Keysharp port normalizes it to BOM-less UTF-8. Either suite can read the other's output for the ASCII values stored here.
- **`@` actions don't run in a compiled build** — by design; the `@` prefix needs `A_AhkPath` and is disabled when the script is compiled.
- **Startup toggle** raises a tray tip when the shortcut cannot be written; the Startup folder is per-user, so no elevation is involved.
- **Keysharp/Linux specifics** — capability prompts on first run; hotkey capture Partial off-Windows (see [Status & caveats](#status--caveats)); startup links are freedesktop `.desktop` entries whose generated name may not match the toggle's check.
- **Bugs and code-level defects currently open** are tracked with status in [docs/KNOWN-ISSUES.md](docs/KNOWN-ISSUES.md).

---

## Project layout

| Path | Purpose |
|---|---|
| `zxcmc.ahk` | The original implementation (~6000 lines; class-based state, hotkey engine, GUI, tray, config I/O). Runs under Keysharp and plain AutoHotkey v2.0. |
| `zxcmc.ks` | The Keysharp cross-platform port — a mechanical mirror of the `.ahk` plus platform branches (`#Requires capability`, `#if WINDOWS` guards, restructured UpDown controls) so the two stay diffable. |
| `.github/workflows/build.yml` | CI: validates both scripts and compiles them with Keysharp on Windows, Linux and macOS runners; tag builds are attached to Releases. |
| `examples/` | Titled examples for the configuration files created at runtime. |
| `icons/` | Row icons for the list views — `gear.ico` (command bindings), `keyboard.ico` (key remaps). |
| `docs/` | The full configuration reference, usage guide, security note and issue tracker. |
| `.gitignore` | Ignores local notes, test harnesses, configuration/save files and build temp files. |

---

## Status & caveats

1. **Hotkeys / InputHook / Send / GetKeyState: Full on Windows, Partial on Linux/macOS** per Keysharp's porting notes. X11 support is broader; on Wayland, global hotkey capture and PID availability vary by compositor.
2. **Capability prompts** on first run off-Windows (`#Requires capability InputMonitoring, InputControl, WindowMonitoring`); a denied capability exits with an error naming it.
3. **Startup toggle off-Windows**: Keysharp's `FileCreateShortcut` writes freedesktop `.desktop` launcher entries whose generated filename may not match the existence check — the toggle's initial state may need path adjustment per platform (Windows works properly).
4. **ListView theming** via Win32 LVM messages is compiled out off-Windows (GTK treeview); only the `+Background` GUI option remains.
5. **Tooltips** (settings controls, filter boxes) are Windows-only — absent elsewhere, never fatal.
6. **UpDown UI** differs: Keysharp UpDowns are standalone NumericUpDown controls (no buddy Edit), so the Settings tab looks slightly different in the `.ks`.
7. **`Sleep()`** uses `Application.DoEvents()` internally in Keysharp — the repeat-while-held loop and recorder should still work but warrant smoke-testing.
8. **MsgBox** modality options are ignored, and **TrayTip** notifications degrade to the status strip off-Windows (Keysharp).
9. **Macro Builder window resizing** is not implemented under Linux/GTK yet; the fixed 820×536 layout is used.
10. The two scripts intentionally diverge in a few documented places (no-prefix command shell, doubled-prefix handling, INI encoding target); each divergence is marked in the source and in the [configuration reference](docs/CONFIGURATION.md).

---

## Known issues

Code-level defects and their status (open / fixed on `Experimental` / by
design) are tracked in [docs/KNOWN-ISSUES.md](docs/KNOWN-ISSUES.md). The only
open item is the Macro Builder window resize under Linux/GTK, which is
deliberately left as-is.

---

## Security

ZxCMC executes what you configure with your full user privileges. Before
importing or enabling a config file written by anyone else, read
[docs/SECURITY.md](docs/SECURITY.md) — it covers what actually runs, what the
import gate does and does not protect against, a review checklist, and how to
verify a release build.

---

## Building

Compiled `.cks` assemblies are produced by [GitHub Actions](.github/workflows/build.yml) rather than committed: Keysharp always compiles for the OS it runs on (no cross-compilation), so the workflow runs the same steps on Windows, Linux and macOS runners — download Keysharp `${{ env.KEYSHARP_VERSION }}` (pinned via the `KEYSHARP_VERSION` env var in the workflow), `--validate` both scripts, then `--compile` each with `--dest` into per-OS artifacts. Tag pushes (`v*`) attach the artifacts to the GitHub Release.

You can do the same manually on any platform with [Keysharp](https://github.com/keysharp-org/Keysharp/releases) and the .NET 10 runtime installed:

```sh
keysharp --validate zxcmc.ahk
keysharp --compile zxcmc.ahk --dest zxcmc.cks
```

To validate syntax without launching the GUI: `keysharp --validate <script>` (exit code 0 means it parses cleanly), or (Windows/AutoHotkey) `AutoHotkey.exe /Validate /ErrorStdOut zxcmc.ahk`.

---

## License

Licensed under the MIT license.
