# ReBindX → Keysharp Port Plan

> Keysharp is the .NET port of AutoHotkey v2 (github.com/keysharp-org/Keysharp; docs: keysharp-org.github.io/KeysharpDocs). It is a cross-platform C# implementation targeting AutoHotkey v2.1-alpha.33 compatibility, requires the .NET 10 runtime, and runs on Windows, Linux and macOS ("under active development and not yet recommended for production"; Windows has the broadest compatibility). This plan covers porting `rebindx.ahk` and the Windows/Linux build path.

---

## 1. Preliminary Assessment

### Porting cost: **Moderate**

| Component | AHK v2 construct | Keysharp construct | Risk |
|-----------|------------------|--------------------|------|
| Hotkey engine | `Hotkey("$" key, fn)` | Provided; `$` prefix supported, but underlying `RegisterHotkey` is Win32 only | **Linux needs xdotool/evdev shim — not built in** |
| GUI | `Gui.Create(...)` / `MainGui.Add("Button", ...)` | AHK-style API over WinForms on Windows; Gtk# on Linux — partial | Windows fine; Linux partial |
| ListView theming | `DllCall("SendMessage", hwnd, 0x30B, ...)` | `SendMessage` exists but string-form signature differs | medium |
| INI read/write | `IniRead` / `IniWrite` / `IniDelete` | Provided 1:1 | low |
| FileCreateShortcut | `FileCreateShortcut(...)` | Not present — needs `ShellLink` COM on Windows / `.desktop` writer on Linux | medium |
| TrayTip | `TrayTip(...)` | Provided; tray icon needs `NotifyIcon` wrapper | medium |
| Send/Run | `Run("start zen.exe")` | `Run()` provided (`System.Diagnostics.Process`) | low |
| OnExit | `OnExit(fn, 1)` | Provided with exit-code veto | low |
| FileSelect / MsgBox | `FileSelect(3, ...)` / `MsgBox(..., 308)` | Provided | low |

**Verdict:** hotkey core and GUI port cleanly; shortcut creation + Linux hotkey shim are the two real blockers.

### Cross-platform path work
Keysharp today is Windows-first. To make the ReBindX binary run on Linux:
1. Replace `FileCreateShortcut` with a platform switch → `ShellLink` on Windows, `.desktop` file writer on Linux.
2. Replace "startup" semantics with an XDG autostart entry (`~/.config/autostart/rebindx.desktop`).
3. `TrayTip` → `NotifyIcon` needs `libappindicator` — optional graceful fallback.
4. `#SingleInstance Force` → map to a lock file (`/tmp/rebindx.lock`) with PID check.

---

## 2. Build Plan (Windows)

### Step 1 — Install prerequisites
```powershell
winget install Microsoft.DotNet.SDK.10
git clone https://github.com/keysharp-org/Keysharp.git
cd Keysharp
dotnet build -c Release
```

### Step 2 — Convert rebindx.ahk
Keysharp is a superset but not byte-compatible with AHK v2:
- ~~`#Requires AutoHotkey v2.0` directive is not supported — remove it.~~ **CORRECTED (2026-10, verified):** the directive IS supported — shipped Keysharp scripts (`Scripts/WindowSpy.ks`, `Scripts/Template.ks`) use it, and a script carrying it validates and compiles cleanly. Keysharp also accepts `#Requires Keysharp <version>` (checked against `A_KsVersion`) and `#Requires capability <names>` (platform permissions: InputMonitoring, InputControl, WindowMonitoring, WindowControl, ScreenCapture, AudioCapture, CameraCapture, ClipboardMonitoring).
- `FileExist`/`IniRead`/`MsgBox` map 1:1 (Keysharp preserves the AHK API surface).
- Raw `DllCall("SendMessage", ...)` string-form: prefer the `SendMessage()` function; Win32-only calls (`tooltips_class32`, LVM_*) need `#if WINDOWS` compile-time guards — Keysharp supports `#if WINDOWS` / `#else` / `#endif` platform conditionals.
- `FileCreateShortcut` — supported by Keysharp itself: `.lnk` on Windows, freedesktop `.desktop` launchers/symlinks on Linux/macOS (Windows-only icon-number/hotkey parameters are ignored off-Windows).
- File path separators — `A_ScriptDir` + `JoinPath` helper (see ANALYSIS.md D-04 fix, applied).
- The port now EXISTS as `rebindx.ks` (mechanical mirror of `rebindx.ahk` + platform adaptations): validated with `keysharp --errorstdout --validate-syntax` / `--validate` and compiled with `keysharp --compile asm --dest dist/rebindx-ks.cks` (see `Resources/keysharp_porting_notes.md` for the adaptation table and runtime caveats).

### Step 3 — Compile to native
```powershell
dotnet publish -c Release -r win-x64 --self-contained false
# Native AOT preferred — startup time matters for a background hotkey tool:
dotnet publish -c Release -r win-x64 /p:PublishAot=true
# output: bin/Release/net9.0/win-x64/publish/rebindx.exe
```

### Step 4 — Single-file + icon
```powershell
dotnet publish -c Release -r win-x64 /p:PublishSingleFile=true /p:IncludeNativeLibrariesForSelfExtract=true
```

---

## 3. Build Plan (Linux)

### Prerequisites
```bash
sudo apt install dotnet-sdk-10.0 libappindicator3-1 xdotool
git clone https://github.com/keysharp-org/Keysharp.git
cd Keysharp && dotnet build -c Release
```

### Linux-specific shims needed in rebindx code
1. **Hotkey engine** — Keysharp uses `RegisterHotkey` (Win32). On Linux, route through `xdotool`/`xev` event capture or `evdev` — this shim does **not** ship with Keysharp. Interim: run under X11 with `sxhkd`-style external capture, or fork the hotkey layer.
2. **FileCreateShortcut** — write `~/.config/autostart/rebindx.desktop` instead.
3. **MsgBox / FileSelect** — Keysharp on Linux uses GTK dialogs; if GTK bindings are unavailable at runtime, wrap in try/catch and fall back to console prompts.
4. **Theme** — `LVM_SETBKCOLOR` via `SendMessage` is Win32-only; on Linux use a GTK `Gtk.TreeView` theming branch, or skip theming entirely (cosmetic only).

### Build
```bash
dotnet publish -c Release -r linux-x64 /p:PublishSingleFile=true /p:PublishAot=true
# output: bin/Release/net9.0/linux-x64/publish/rebindx
```

---

## 4. Suggested Project Layout After Port

```
rebindx/
├── rebindx.keysharp          # main script (ported from rebindx.ahk)
├── keysharp.json             # Keysharp project manifest
├── ANALYSIS.md               # pre-port audit (this repo)
├── keysharp.md               # this file
└── dist/
    ├── win-x64/rebindx.exe
    └── linux-x64/rebindx
```

---

## 5. Risks

1. **Keysharp maturity** — verified 2026-10 against the official README: "under active development and not yet recommended for production"; targets AutoHotkey v2.1-alpha.33 (not v2.0); Windows compatibility is broadest, Linux/macOS continue to improve. `SendMessage` string-form, `FileCreateShortcut`, and `TrayTip` must still be verified against the current release notes before porting.
2. **Native AOT + reflection** — Keysharp's scripting layer relies heavily on reflection; AOT may strip required members. Test `PublishAot=true` builds *before* investing in theming; fall back to `PublishSingleFile` self-contained if AOT throws.
3. **Linux hotkey shim** — no built-in solution; may require a fork or sxhkd companion. Budget as a separate feature (§3.1).
4. **GUI divergence** — WinForms wrapper on Windows, GTK on Linux; layout literals will not match between platforms — reinforce the flow-layout refactor (ANALYSIS.md D-06) *before* porting.
5. **Shortcut semantics** — `.lnk` vs `.desktop` are not just format differences; startup behaviour, permissions, and icon resolution all differ.

---

## 6. Verification Notes

- **URL corrected:** the original plan cited `github.com/qrl-tech/keysharp` from memory — that repository does not exist (404). The verified official sources are: repo `github.com/keysharp-org/Keysharp`, docs `keysharp-org.github.io/KeysharpDocs`, releases `github.com/keysharp-org/Keysharp/releases`.
- **Status (2026-10):** all BUG-01..08 fixes, D-01..08 weakness fixes, features 1–12 and UI improvements 1–7 from `ANALYSIS.md` have been applied to `rebindx.ahk` (full rewrite, AHK v2.0-only, doc-verified APIs). **The Keysharp port is no longer deferred: `rebindx.ks` exists and is compile-validated** — plain `rebindx.ahk` also compiles under Keysharp unchanged (`dist/rebindx.cks`). Runtime behavior (hotkeys on Linux/Wayland, capability prompts, .desktop startup links) remains to be smoke-tested on a healthy machine — see `Resources/keysharp_porting_notes.md`.
- **Port-relevant notes for the follow-up:** the rewrite keeps a single source of truth for state (`class App`), one `KEY_LIST` constant for all key names, `JoinPath()` instead of hardcoded `\`, named Win32 constants, and a v2.0-verified API-facts file (`ReBindX-research/ahk_facts.md`) that doubles as the port's API-coverage checklist. Keysharp targets v2.1-alpha.33 — keep the facts file as the v2.0 gate so no v2.1-only syntax creeps in before the port.
- **Unverified claims:** the §1 API-coverage table and §2–3 build flags should be re-checked against the current Keysharp docs/repo immediately before executing the port. If the real API differs, §1's risk column is the first thing to re-audit.
