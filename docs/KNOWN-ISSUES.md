# Known issues

This is the list of defects found by reading the ZxCMC source (`zxcmc.ahk` and
its `.ks` twin). Line numbers refer to `zxcmc.ahk` in this commit; the `.ks`
file mirrors it within a few lines unless stated otherwise. Nothing here is
fixed yet — the list is the working roadmap for the next builds.

| # | Severity | Title |
|---|---|---|
| [1](#1-editing-a-pixel-binding-destroys-its-trigger) | HIGH | Editing a pixel binding destroys its trigger |
| [2](#2-undo-does-not-cover-import-fully) | HIGH | Undo does not cover import fully |
| [3](#3-zxcmc-ahk-cannot-run-on-plain-autohotkey-v20) | HIGH | `zxcmc.ahk` cannot run on plain AutoHotkey v2.0 |
| [4](#4-profile-import-bypasses-the-safety-gate) | MED | Profile import bypasses the safety gate |
| [5](#5-pixel-triggers-ignore-the-window-scope) | MED | Pixel triggers ignore the window scope |
| [6](#6-run-at-startup-requires-an-admin-token-unnecessarily) | MED | Run-at-startup requires an admin token unnecessarily |
| [7](#7-@-prefix-uncompiled-keysharp-uses-apossibly-null-ahkpath) | MED | `@` prefix under uncompiled Keysharp uses a possibly-null `A_AhkPath` |
| [8](#8-macro-runrw-commands-always-run-hidden) | LOW | Macro `run:`/`rw:` commands always run hidden |
| [9](#9-macro-builder-resize-is-broken-under-linuxgtk) | LOW | Macro Builder resize is broken under Linux/GTK |
| [10](#10-undo-does-not-cover-profile-settings) | LOW | Undo does not cover profile settings |
| [11](#11-phantom-empty-profiles-from-a-stale-activeprofile) | LOW | Phantom empty profiles from a stale `ActiveProfile` |
| [12](#12-config-problems-are-not-reported-when-started-hidden) | LOW | Config problems are not reported when started hidden |

---

## 1. Editing a pixel binding destroys its trigger

**Severity: HIGH** — data loss on a routine edit.

**Where:** `OpenEditor` (`zxcmc.ahk:3121`) — pixel fields are created with the
constants `0 / 0 / FFFFFF` at `zxcmc.ahk:3216–3223`; `EditorSave`'s pixel
branch is at `zxcmc.ahk:3591` (the same pattern exists in `TestRemap`,
`zxcmc.ahk:3520`).

**What happens:** the binding editor never prefills the PX/PY/PC/PM fields
when editing an existing pixel binding — only the key field gets a value.
When you change anything else in that binding and press Save, the blank
fields are read back and the binding is saved as `px:0,0,FFFFFF,to`, after
which `RemoveBinding(OrigId)` deletes the original. The pixel trigger
silently turns into a watcher for pixel (0,0) turning white.

**Workaround:** re-type the coordinates and color when editing such a
binding, or edit `keybinds.cfg` by hand.

## 2. Undo does not cover import fully

**Severity: HIGH** — undo promises more than it delivers.

**Where:** `PushUndo()` (`zxcmc.ahk:5837`) snapshots only the active
profile's bindings and macros via `CloneBindings()` (`zxcmc.ahk:5822`, which
also drops the `Icp` and `SendMode` fields); `ImportConfig`
(`zxcmc.ahk:1209`) replaces *all* profiles; `Undo()` restores only
`snap.Profile`.

**What happens:** after importing a multi-profile config, Ctrl+Z restores
exactly one profile (the active one) and leaves the other overwritten
profiles at their imported state. Per-profile settings (shell, repeat,
send mode) are never snapshotted, so even the active profile loses parts of
its pre-import configuration.

**Workaround:** `Export` the current configuration before importing
anything.

## 3. `zxcmc.ahk` cannot run on plain AutoHotkey v2.0

**Severity: HIGH** — the file claims a dependency it does not satisfy.

**Where:** header note at `zxcmc.ahk:5–8` admits it; `#Requires AutoHotkey
v2.0` at the top of the file; Keysharp-only `xc`/`yc` (tab-relative)
positioning used throughout `BuildMainGui` (e.g. `zxcmc.ahk:2140`, `2157`,
`2302`, `2324`).

**What happens:** AutoHotkey v2.0 supports only `xp/xs/xm/x±N` (and the `y`
family), not Keysharp's `xc`/`yc` extensions. GUI construction fails with an
"invalid option" error before any window appears.

**Status:** Keysharp is therefore the only supported runtime for either
file; the README now documents this. Either drop the `#Requires v2.0`
mismatch, or replace `xc/yc` usage if plain-AHK support is ever wanted.

## 4. Profile import bypasses the safety gate

**Severity: MED** — risky but recoverable via Undo (partially).

**Where:** `ProfileImport` (`zxcmc.ahk:5453`) activates the imported hotkeys
immediately via `RegisterAllHotkeys()` (`zxcmc.ahk:5546`); malformed lines
are silently `continue`d, and `hs:`/`px:` entries inside remap sections are
forced to `id := "cmd|" keypart "|"` (Type/id inconsistency).

**What happens:** the sidebar **Import** shows a Yes/No/Cancel preview, but
the Profiles-tab **Import...** applies hotkeys at once with no preview and
no report of skipped lines. Binding ids can disagree with binding type,
which confuses later edits.

**Workaround:** prefer the sidebar Import, or export/profile-backup first.

## 5. Pixel triggers ignore the window scope

**Severity: MED** — inconsistent behavior, cannot be narrowed like other
triggers.

**Where:** watcher registration in `PixelWatchers` (`zxcmc.ahk:4119`,
`4135`) stores no scope; dispatch in `HsDispatch` (`zxcmc.ahk:1456`) never
checks one — unlike hotkey/hotstring triggers, which honor `[wintitle]`.

**What happens:** a pixel binding always fires globally, even if the cfg
line carries a `[wintitle]` scope; the UI reports a scope that does nothing.

**Workaround:** none; treat pixel triggers as global.

## 6. "Run at startup" requires an admin token unnecessarily

**Severity: MED** — a benign Windows-only account check misfiled as admin.

**Where:** `ToggleStartup` (`zxcmc.ahk:2655`) gates on `A_IsAdmin`, and the
Settings row even reads "Run at startup (requires admin)" (`zxcmc.ahk:2221`),
but `A_Startup` points at the *per-user* Startup folder, which a normal user
can always write.

**What happens:** the checkbox silently refuses for non-elevated sessions.
The shortcut also may not survive cleanup logic expecting elevation.

**Workaround:** launch ZxCMC from a per-user Startup shortcut you create
yourself (`.lnk` or Task Scheduler), or run elevated once to toggle.

## 7. `@` prefix under uncompiled Keysharp uses a possibly-null `A_AhkPath`

**Severity: MED** (uncompiled Keysharp only) — null-path behavior class the
project already documented for `A_ComSpec`.

**Where:** command execution branch where `@code` is written via a temporary
`.ahk` file; the interpreter path comes from `A_AhkPath`, guarded only by
`A_IsCompiled`.

**What happens:** under a non-compiled Keysharp script, `A_AhkPath` may be
null/empty, so the temporary file is passed to an empty command and the
action fails without a clear message.

**Workaround:** use compiled builds for `@` actions, or `&` shell commands.

## 8. Macro `run:`/`rw:` commands always run hidden

**Severity: LOW** — surprising but harmless.

**Where:** `case "run":` at `zxcmc.ahk:3992` (and `rw:` right after,
`zxcmc.ahk:3994`/`4001`) hard-codes `"Hide"`; the `ShellHidden` profile
setting is not consulted inside macros (unlike the `&` prefix in the
Command Mapper, which respects it).

**What happens:** a macro that runs a visible console script shows nothing;
the same command via a hotkey-bound `&` command may open a window.

**Workaround:** put interactive work in a Command Mapper binding, or have
the command write its output to a file.

## 9. Macro Builder resize is broken under Linux/GTK

**Severity: LOW** — cosmetic, self-documented.

**Where:** `zxcmc.ks:4554` carries the author's own
`total_hours_wasted_here: 16` note; the .ahk twin's `BuilderSize`
(`zxcmc.ahk:4446`) works under Windows only.

**What happens:** resizing the Builder window under GTK does not reflow the
action list and button row.

**Workaround:** keep the window at its default size (820x536); the builder
is still fully usable.

## 10. Undo does not cover profile settings

**Severity: LOW** — limited blast radius.

**Where:** the same snapshot logic as issue 2 (`CloneBindings`
`zxcmc.ahk:5822`) captures only bindings and macros.

**What happens:** changing a profile's shell/repeat/send-mode values in the
Profiles or Settings tab is not restorable with Ctrl+Z, even though the same
in-memory profile object was mutated.

**Workaround:** note the old values before changing them; profile **Save
As...** before experimenting.

## 11. Phantom empty profiles from a stale `ActiveProfile`

**Severity: LOW** — cosmetic, easy to trigger.

**Where:** settings-load path that honors a saved `ActiveProfile` name
contains no existence check; `(unknown name -> created empty)` is relied on
by `TrayNewProfile` (`zxcmc.ahk:5767`), but the same behavior fires at
startup.

**What happens:** if the saved active profile was deleted elsewhere (hand
edits, an older cfg), ZxCMC creates it as an empty profile anyway, and the
next save persists this phantom section forever.

**Workaround:** delete it from the Profiles tab once.

## 12. Config problems are not reported when started hidden

**Severity: LOW** — right behavior, wrong combination with `--silent`.

**Where:** `ShowCfgReport`, which explains rejected binding lines after
load, is gated on `App.Settings["GuiVisible"]`.

**What happens:** starting ZxCMC via the startup shortcut with
"start-as-hidden" (or `--silent`) suppresses the report, so a bad `keybinds.cfg`
line is skipped without any notice beyond the tray icon.

**Workaround:** launch visibly once after editing the cfg by hand, or check
`error.log`.

---

## Older notes

Previous releases of this README linked an `ANALYSIS.md` file that was never
committed (it is gitignored); its content is now folded into this document.
