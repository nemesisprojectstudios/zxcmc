# Using ZxCMC

This guide covers day-to-day operation of ZxCMC through its GUI, tray menu, and
keyboard. For config file syntax and internals, see
[CONFIGURATION.md](CONFIGURATION.md). For known bugs and their workarounds, see
[KNOWN-ISSUES.md](KNOWN-ISSUES.md).

ZxCMC runs entirely in memory until you save: it loads `keybinds.cfg` from the
side of the executable/script at startup, and keeps changes unsaved (with a
10-level undo) until you press **Save** (or enable Autosave in Settings).

## Contents

- [The main window](#the-main-window)
- [Sidebar buttons](#sidebar-buttons)
- [Managing bindings](#managing-bindings)
- [Importing, exporting, loading](#importing-exporting-loading)
- [The Profiles tab](#the-profiles-tab)
- [The Macros tab and Macro Builder](#the-macros-tab-and-macro-builder)
- [Recording macros](#recording-macros)
- [The Hotstrings tab](#the-hotstrings-tab)
- [The Settings tab](#the-settings-tab)
- [Keyboard shortcuts](#keyboard-shortcuts)
- [Tray menu](#tray-menu)
- [Troubleshooting](#troubleshooting)

## The main window

The window is titled **ZxCMC - Crossplatform Macro Client** and is a normal,
resizable window (minimum size 800x600; the lists follow when you resize).

It contains **seven tabs**:

| Tab | Purpose |
|---|---|
| Command Mapper | Hotkey / hotstring / pixel triggers that run commands (`&shell`, `>send`, `@code` prefixes) |
| Key Remapper | Hotkey triggers that send keys/macros as output |
| Hotstrings | Typed-text triggers with their replacements |
| Macros | The macro library (New..., Edit..., Builder...) |
| Profiles | Save, switch, clone, rename, import/export profiles |
| Settings | Per-profile repeat, shell, startup, and behavior settings |
| Usage Guide | Built-in reference split into seven sub-tabs |

Press **F1** at any time to hide/show the window (it binds F1 globally before
anything else, so F1 is still safe to rebind as a trigger inside ZxCMC). Press
**Esc** while the window is focused to hide it. Closing to the taskbar does
not exit the program; use the sidebar **Exit** button, the tray **Exit** item,
or an OS logoff/shutdown (which are never blocked).

Above each list there is a **Filter** box that narrows rows as you type.

## Sidebar buttons

The left sidebar holds the same buttons regardless of which tab is active.
They apply to the currently visible list:

| Button | Effect |
|---|---|
| **+ Add Binding** | Opens the binding editor for the active tab |
| **Delete** | Deletes all selected rows (prompts only when more than one row is selected) |
| **Toggle On/Off** | Enables/disables the selected rows |
| **Clear Bindings** | Empties the current list (one-time confirmation) |
| **Undo** | Reverts the last change; 10 levels deep (same as Ctrl+Z) |
| **Suspend / Unsuspend** | Pauses all trigger interception; F1, the main window, and the tray stay live |
| **Save** | Writes all profiles back to `keybinds.cfg` (atomically, via `.tmp` + rename) |
| **Save to...** | Copies the *selected* bindings/macros/hotstrings into any profile without switching profiles |
| **Load** | Re-reads `keybinds.cfg` from disk (your unsaved changes are lost) |
| **Import** | Merges an external config file over the current one (see below) |
| **Export** | Writes the whole config to a file of your choice |
| **Exit** | Quits the app (asks first if there are unsaved changes) |

A status line at the bottom of the window reports the result of every action
(saves, conflicts, recording progress, errors).

## Managing bindings

- Click a row to select it; Ctrl+click or Shift+click selects several.
- Double-click a row, or press **Enter**, to edit it. Right-click a row for a
  one-binding toggle/edit/delete context menu.
- Every time you add or edit, the app checks for trigger conflicts. If another
  enabled binding already claims that trigger (same key, text, or pixel), you
  are prompted. The **later** (highest-sequence) enabled binding always wins at
  dispatch time, so accepting the conflict keeps both rows but only the last
  one lives.
- Hotkey triggers accept AHK modifier syntax (`#` Win, `^` Ctrl, `!` Alt,
  `+` Shift) and multi-character key names; the Interception dropdown offers
  `~` passthrough, `$` force-hook, and `*` wildcard prefixes (combinable).
- Window scopes: append `[wintitle]` to a trigger (e.g. `#Z[ahk_exe chrome.exe]`)
  and the binding only fires while that window is active. Scope applies to
  hotkey and hotstring triggers.
- Pixel triggers: set trigger type **Pixel**, give X,Y and an RRGGBB color, and
  choose "turns to" or "turns from". The watcher polls continuously while ZxCMC
  runs, fires once per transition, and re-arms when the color clears. Where
  pixel capture is unavailable the watcher disables itself and logs once.
  **Known issue:** editing an existing pixel binding loses its stored
  coordinates in the current build — see
  [KNOWN-ISSUES.md](KNOWN-ISSUES.md#1-editing-a-pixel-binding-destroys-its-trigger).

## Importing, exporting, loading

- **Import** (sidebar) shows a preview gate before anything is applied:
  - **Yes** replaces the configuration with the file's contents.
  - **No** closes the file without changing anything.
  - **Cancel** behaves like "No" from the file's perspective; an **Undo**
    (Ctrl+Z) snapshot is always pushed over the active profile. Note that the
    undo snapshot covers only the *active* profile, while an import with
    multiple `[Profile:]` sections replaces *all* profiles — profiles beyond
    the active one cannot be restored. Details in
    [KNOWN-ISSUES.md](KNOWN-ISSUES.md#2-undo-does-not-cover-import-fully).
- **Profile Import** on the Profiles tab imports a single-profile config with
  merge semantics directly into the current profile set (no preview gate;
  malformed lines are skipped silently).
- Saving is atomic: the file is written to a `.tmp` file first, then renamed,
  so a crash mid-save cannot corrupt `keybinds.cfg`.

## The Profiles tab

A profile bundles all bindings, macros, and the repeat settings.

- **Active profile:** pick from the dropdown, press **Switch** (or use the tray
  **Profiles** submenu).
- **New profile...:** start empty, clone the current settings, or clone an
  existing profile.
- **Save** writes the active profile; saving into **Default** warns once.
- **Save As...** copies the active profile under a new name and switches to it.
- **Rename** renames the active profile (disabled for Default).
- **Export... / Import...** read/write single-profile config files.
- **Delete profile:** removes a non-Default profile; Default is cleared instead.

Profiles live as `[Profile:Name]` sections in `keybinds.cfg`; **Default** is the
headerless section at the top of the file.

## The Macros tab and Macro Builder

A macro is a reusable Send-sequence stored in the per-profile macro library.
Bindings reference it by name (`macro:Name` as a remap output), so editing a
macro instantly updates every binding that uses it.

**Record...** captures what you type (see below). **New... / Edit...** opens a
plain sequence text. **Builder...** opens the structured Macro Builder, where
you assemble a macro action by action:

| Control | Effect |
|---|---|
| **Add action...** | Opens a dialog with these types: **Key press** (with hold ms), **Key down**, **Key up**, **Wait** (ms), **Run command** ("Wait until return" checkbox), **Mouse move** (X/Y, Relative, optional held key), **Sequence** (raw Send string), **Loop start / Loop end** (name + count). **AHK Send** appears only in Advanced mode. |
| **Edit action...** / double-click a row | Edits the selected action |
| **Delete** | Removes selected actions |
| **Up / Down** | Reorders the selected action |
| **Clone** | Duplicates the selected action(s) in place (a multi-selection inserts the copies after the last one) |
| **Test** | Executes the current sequence once |
| **Save** | Stores the macro (loops must be balanced; loop names unique; `endloop` matches the innermost open loop) |

The builder shows a live token preview per row, e.g. `kp:G:50`, `w:500`,
`run:curl https://...`, `loop:Loop1:3`, and stores a literal `|` inside a
parameter as `{PIPE}`.

### Macro trigger modes

Each macro binding (Key Remapper) makes a key press trigger the macro:

| Trigger | Fires |
|---|---|
| `trg:press` | When the key goes down |
| `trg:release` | When the key goes up |
| `trg:repeat` | Repeats while held (per-binding buffer/delay, or the profile defaults) |
| `px:` pixel watch | Fires on a pixel color transition at X,Y |

### Shell actions inside macros

`run:` starts a command asynchronously, `rw:` waits for it to finish before
proceeding (visible in the action dialog as the "Wait until return" checkbox).
In the current build both run **hidden** regardless of the console setting —
see [KNOWN-ISSUES.md](KNOWN-ISSUES.md#8-macro-runrw-commands-always-run-hidden).

## Recording macros

1. **Tray → Record Macro...** (or the Record button): all bindings are
   temporarily unhooked, so your trigger keys cannot fire while recording.
2. Type. Every keystroke is passed through to the active window and buffered.
   Recording is keyboard-only; mouse clicks are not captured.
3. **Esc** stops recording (Esc itself is never recorded). The buffer is
   capped at ~100,000 characters.
4. Give the macro a name (it cannot contain `;`, `[`, `]`, `*`, or `|`).
5. Assign it from the Macros tab / Key Remapper with `macro:Name`.

Recorded text is automatically escaped so literal `!`, `#`, `+`, `^`, `{`, `}`
replay as characters instead of Send modifiers.

## The Hotstrings tab

A hotstring fires when you *type* its trigger text anywhere, followed by an
ending character (space, Enter, etc.).

- **New... / Edit...** set the trigger text and the replacement action, which
  follows the binding grammar: `>text` sends text/keys, no prefix/command runs
  a command, `&cmd` goes through the selected shell, `macro:Name` replays a
  macro.
- Scope works for hotstrings: `[wintitle]` limits where the text triggers.
- **Delete / Toggle** behave like in the other tabs.

## The Settings tab

All settings marked *per profile* are stored inside the profile and switch
with it:

| Setting | Scope | Notes |
|---|---|---|
| Repeat outputs while held (remaps only) | per profile | Repeat a remap's output while the trigger stays down |
| Repeat buffer / delay (ms) | per profile | Tuning for the repeat loop |
| Run at startup | machine | Needs admin on Windows (per-user Startup folder entry; see [KNOWN-ISSUES.md](KNOWN-ISSUES.md#6-run-at-startup-requires-an-admin-token-unnecessarily)) |
| Shell for & commands | per profile | cmd.exe / PowerShell on Windows; on Linux/macOS the list is discovered from the system |
| Console visibility | per profile | Whether `&` commands open a console window |
| Start as suspended | global | Begin suspended |
| Autosave | global | Save automatically on exit/changes |
| Advanced mode | global | Reveals the per-profile default Send mode, the per-remap/per-action Send modes, and the builder **AHK Send** action |

## Keyboard shortcuts

| Key | Scope | Effect |
|---|---|---|
| **F1** | Global | Hide/show the main window |
| **Esc** | Main window (active) | Hide the window |
| **Delete** | A list row selected | Delete the selected rows |
| **Ctrl+Z** | Main window (active) | Undo (10 levels) |
| **Enter** | A list row selected | Edit the binding |

## Tray menu

The tray icon is the fastest way to work with ZxCMC in the background:

| Item | Effect |
|---|---|
| **Show / Hide** | Toggles the main window (default item; single click works) |
| **Save** | Save all profiles to `keybinds.cfg` |
| **Load** | Re-read `keybinds.cfg` |
| **Import...** | Import a config file (same gate as the sidebar) |
| **Export...** | Export the whole config |
| **Profiles →** | Switch profiles (radio check on the active one) + **New...** |
| **Record Macro...** | Start the recorder |
| **Exit** | Quit |

## Troubleshooting

- **Nothing was saved / my changes disappeared after a restart.** Don't forget
  that every edit stays in memory until you press **Save** (or enable Autosave).
- **The window vanished.** Press **F1** or click the tray icon; **Esc** only
  hides.
- **A binding fires but seems "stuck" in the wrong state.** Suspend, then
  unsuspend, from the sidebar — this unregisters and re-registers every
  trigger hook and clears stuck modifier-held-repeat states.
- **A remapped key does not repeat.** Repetition is a remap-only setting and is
  configured per profile in Settings.
- **bash error before a command runs.** On Linux (and wherever bash is
  selected as the shell) commands are syntax-checked with `bash -n` first; a
  syntax failure is reported and nothing is executed.
- **Pixel watchers die on Wayland/compositors.** Pixel capture is unavailable
  on some compositors; the watcher disables itself and logs once
  (`error.log` in the OS application-data directory, `ZxCMC` folder).
- **Linux/GTK: the Macro Builder resizes oddly.** The builder resize handler
  is not reliably applied under GTK (documented in the source); the window
  still functions at its default size.
- **Errors and logs.** Anything unexpected is appended to `error.log` inside
  the OS application-data directory (`ZxCMC` folder).

### Platform notes

- **Windows** is the reference platform. Compiled `zxcmc-windows-x64` releases
  ship `.zip` / `.tar.gz` archives with the same `zxcmc.cks` payload.
- **Linux / macOS** work through Keysharp, but expect GUI quirks (builder
  resize; pixel capture restrictions on Wayland/macOS compositors). Shell
  discovery and `bash -n` validation make `&` commands behave as on Windows.
- **macOS** is the least tested surface; basic key remap and macro functionality
  comes from Keysharp itself.

---

*All screens described above correspond to Keysharp v0.0.0.18 as of ZxCMC
v0.2.0-beta.*
