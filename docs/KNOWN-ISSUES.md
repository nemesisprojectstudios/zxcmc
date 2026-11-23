# Known issues

This file tracks defects found by reading the ZxCMC source (`zxcmc.ahk` and
its `.ks` twin) and their status. Most issues from the first review were
**fixed on the `Experimental` branch**; line references below point at the
branch, not at `master`.

## Open

### 9. Macro Builder resize is broken under Linux/GTK

**Severity: LOW** — cosmetic, self-documented.

**Where:** `zxcmc.ks` carries the author's own
`total_hours_wasted_here: 16` note; the .ahk twin's `BuilderSize` works under
Windows only.

**What happens:** resizing the Builder window under GTK does not reflow the
action list and button row.

**Workaround:** keep the window at its default size (820x536); the builder
is still fully usable.

**Status:** accepted. This one is deliberately left alone.

### By design (not bugs)

- **Macro `run:`/`rw:` commands always run hidden** — the hard-coded `Hide`
  console for macro-run shell commands is intended behavior, not an
  oversight. Put interactive work in a Command Mapper binding instead (the
  `&` prefix there respects the profile's hidden-shell setting).
- **Settings INI encoding differs between runtimes** — the `.ahk`
  (AutoHotkey) targets UTF-16, the `.ks` (Keysharp) BOM-less UTF-8; either
  suite can read the other's output for the ASCII values stored here.
- **Tooltips, ListView theming and UpDown styling differ off-Windows** —
  platform limitations of Keysharp, documented in the README's
  [Status & caveats](../README.md#status--caveats).

## Fixed on `Experimental`

These were fixed in the `Experimental` branch and are expected to land in
`Main` after manual testing. Keep the descriptions here as a paper trail
until then.

| # | Title (fixed) | Fix, in brief |
|---|---|---|
| [1](#1-editing-a-pixel-binding-destroys-its-trigger-fixed) | Editing a pixel binding destroys its trigger | PX/PY/PC/PM fields are prefilled from the binding when editing |
| [2](#2-undo-does-not-cover-import-fully-fixed) | Undo does not cover import fully | Undo snapshots **all** profiles (bindings incl. Icp/SendMode, macros, settings); Undo restores the full state and re-registers |
| [3](#3-zxcmc-ahk-cannot-run-on-plain-autohotkey-v20-fixed) | `zxcmc.ahk` cannot run on plain AutoHotkey v2.0 | Layout uses `XC()`/`YC()` helpers: Keysharp `xc`/`yc` where supported, computed absolute `x`/`y` (Tab display area via `TCM_ADJUSTRECT`) on plain AHK v2.0 |
| [4](#4-profile-import-bypasses-the-safety-gate-fixed) | Profile import bypasses the safety gate | Import parses to temp state, reports rejected lines, shows the same Yes/No/Cancel gate, and pushes an undo snapshot |
| [5](#5-pixel-triggers-ignore-the-window-scope-fixed) | Pixel triggers ignore the window scope | Watchers carry the binding's `[wintitle]` scope; while the scoped window is inactive they skip firing and re-arm |
| [6](#6-run-at-startup-required-an-admin-token-unnecessarily-fixed) | "Run at startup" required an admin token unnecessarily | The `A_IsAdmin` gate was removed; the label reads "Run at startup" |
| [7](#7--prefix-under-uncompiled-keysharp-used-a-possibly-null-ahkpath-fixed) | `@` prefix under uncompiled Keysharp used a possibly-null `A_AhkPath` | Empty interpreter path is guarded: error is logged and shown instead of launching an empty command |
| [10](#10-undo-did-not-cover-profile-settings-fixed) | Undo did not cover profile settings | Covered by the same snapshot redesign as #2 |
| [11](#11-phantom-empty-profiles-from-a-stale-activeprofile-fixed) | Phantom empty profiles from a stale `ActiveProfile` | Stale active profile is kept for the session but marked phantom; empty phantoms are never written back on save |
| [12](#12-config-problems-are-not-reported-when-started-hidden-fixed) | Config problems were not reported when started hidden | When the report dialog cannot be shown, a tray tip with the rejected-line count is raised; detail stays in `error.log` |

### 1. Editing a pixel binding destroys its trigger (FIXED)

Previously the editor created the PX/PY/PC/PM fields with constant defaults
and never prefilled them when editing an existing pixel binding, so saving an
edit rewrote the trigger to `px:0,0,FFFFFF,to`. The field values are now
restored from the binding before the dialog shows.

### 2. Undo did not cover import fully (FIXED)

Previously undo snapshotted only the active profile's bindings and macros
(and dropped `Icp`/`SendMode`), so a multi-profile import was only partially
restorable. The snapshot now deep-copies every profile's bindings, macros and
settings; undo restores all of it and re-registers the hotkeys.

### 3. `zxcmc.ahk` could not run on plain AutoHotkey v2.0 (FIXED)

The layout used Keysharp's container-relative `xc`/`yc` options, which AHK
v2.0 rejects. Both scripts now build tab options through `XC(offset)` /
`YC(offset)` helpers: on Keysharp they emit the original `xc+N` / `yc+N`
strings (identical behavior); on plain AutoHotkey v2.0 they compute absolute
coordinates from the Tab control's true display-area origin
(`TCM_ADJUSTRECT`, with a conservative fallback), so the same visual layout
is produced. The probe is automatic — no user-visible setting.

### 4. Profile import bypassed the safety gate (FIXED)

The Profiles-tab import now parses everything into temporary maps first,
normalizes `hs:`/`px:` entries inside remap sections to command bindings,
reports rejected lines, and shows the same confirmation gate (Yes = merge and
activate, Cancel = no changes) before touching the live profile.

### 5. Pixel triggers ignored the window scope (FIXED)

Pixel watchers now record the binding's `[wintitle]` scope. When the scoped
window is not active the watcher does not fire and re-arms for the next
poll — the trigger stays armed instead of consuming a state edge.

### 6. "Run at startup" required an admin token unnecessarily (FIXED)

The `A_IsAdmin` check was removed; `A_Startup` already points at the per-user
Startup folder, so no elevation is needed. The Settings label and built-in
guide text were updated to match.

### 7. `@` prefix under uncompiled Keysharp used a possibly-null `A_AhkPath` (FIXED)

Interpreter launch now verifies `A_AhkPath` is non-empty; otherwise it logs
and reports the failure instead of silently launching an empty command.
(Compiled builds still intentionally disable `@` actions — there is no
interpreter to point at.)

### 10. Undo did not cover profile settings (FIXED)

See #2 — settings are part of the snapshot now.

### 11. Phantom empty profiles from a stale `ActiveProfile` (FIXED)

A saved active profile that is missing from the loaded `keybinds.cfg` still
becomes the active session profile (so references to it keep working), but it
is remembered as a phantom: empty phantom profiles are no longer written back
to the file on save.

### 12. Config problems were not reported when started hidden (FIXED)

When the load report cannot be shown because the window is hidden
(`--silent` / start-hidden), ZxCMC now raises a tray notification with the
number of rejected lines; the per-line detail remains in `error.log`.
