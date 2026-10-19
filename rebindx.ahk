; =============================================================
; ReBindX - Key remapper utility
; AutoHotkey v2.0 - full rewrite per rev-2 design spec
;
; Comment convention used throughout this file:
;   ;        regular comment
;   ; *      highlighted / important
;   ; !      alert or warning
;   ; ?      query / open question / runtime-verify item
;   ; todo:  known follow-up work
;   ; //     crossed-out code (kept as a removal trace)
;
; Sections (in order):
;   1. Header / directives / entry point
;   2. class App          - all shared state (no globals anywhere)
;   3. class Keys         - KEY_LIST: single authoritative key-name list
;   4. class Consts       - verified Win32 constants
;   5. InitApp            - startup sequence
;   6. Config I/O          - theme, settings, keybinds.cfg, import/export
;   6b. Shell detection    - dynamic shell list + shell execution helpers
;   7. Hotkey engine       - normalize, register, unregister, dispatch
;   8. GUI build           - Tips helper, icons, main window
;   9. GUI events / editor - list views, dialogs, key picker
;  10. Tray / profiles / undo / macro recorder
;  11. Exit path           - single DoExit + vetoable ExitFunc
; =============================================================

; ---------- 1. Header / directives ----------
; * #SingleInstance Force: a second launch replaces the first (the
;   "Single" exit reason skips the config save - the file may have
;   been edited externally and must not be clobbered).
; * #UseHook: keyboard hook for every hotkey - together with the
;   per-key "$" prefix (HkName) this stops our own Send output
;   from re-triggering our hotkeys.
; ? ProcessSetPriority("AboveNormal") - questionable for a user
;   utility; consider Normal if input latency ever matters.
#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook

ProcessSetPriority("AboveNormal")
SetWinDelay(-1)
SetControlDelay(-1)

; * startup entry point - everything below it is definitions
InitApp()

; =============================================================
; 2. class App - shared state (design D-01: no global statements)
; * every function reads and writes shared state through this class
;   only - neither file contains a `global` keyword
; =============================================================
class App {
    static Name := "ReBindX"
    static Title := "ReBindX - Key remapper utility"
    static Profiles := Map()        ; profileName -> Map(bindingId -> bindingMap)
    static ActiveProfile := "Default"
    static ActiveHotkeys := Map()   ; "key|scope" -> dispatcher fn (ONE per hotkey VARIANT)
    static VariantIcp := Map()      ; "key|scope" -> interception type the variant is registered under
    static Settings := Map()
    static Shells := []            ; detected shells: Maps {Id, Name, Path, ArgStyle, Family}
    static Seq := 0                ; registration sequence: "later binding wins" per variant
    static MacroLib := Map()       ; VIEW of the active profile's macros (see ProfileMacros)
    static ProfileMacros := Map()  ; profileName -> Map(macro name -> sequence)
    static ProfileSettings := Map() ; profileName -> Map(setting key -> value)
    static PixelWatchers := []      ; live pixel triggers: {Name, Kind, X, Y, Color, Mode,
                                    ;  Seq, Fired, Dead} (binding kind adds Id; the Fired/Dead
                                    ;  state survives list rebuilds)
    static UpHotkeys := Map()       ; key|scope -> fn for "key up" variants (release-trigger macros)
    static Hotstrings := Map()      ; binding id -> fn for hotstring-triggered bindings
    static LV_Hotstrings := 0      ; the Hotstrings tab list
    static BuilderRows := []        ; macro builder: current action rows (Maps)
    static BuilderGui := 0         ; the (single-instance) builder window
    static ActionDlgGui := 0       ; the cached action dialog
    static ActionDlgRow := 0       ; 0 = append, else 1-based row being edited
    static EditorLastTrig := ""   ; remembers a Hotstring trigger across editor Type switches
    ; // WatchFn / BuilderW / BuilderH removed - leftovers of the abandoned
    ; // builder resize timer watcher (porting-notes round 14)
    static Theme := Map()
    static UndoStack := []           ; max 10 snapshots: {Profile, Bindings, Macros}
    static IsDirty := false
    static Suspended := false   ; custom suspend: triggers not intercepted (F1/window/tray stay live)
    ; // ExitConfirmed removed - written in ExitFunc but never read
    static CTab := 1
    static MainGui := 0
    static LV_Cmd := 0
    static LV_Key := 0
    static LV_Macros := 0
    static Ui := Map()               ; named GUI controls
    static LogFile := ""
    static ConfigFile := ""
    static ThemeFile := ""
    static IniFile := ""
    static StartupLnk := ""
    static ValidKeys := Map()        ; UPPER(name) -> canonical name
    static PickerCats := Map()       ; picker category -> array of key names (from KEY_LIST)
    static Filter_Cmd := ""
    static Filter_Key := ""
    static Icons := 0                ; imagelist id; 0 = icons unavailable
}

; =============================================================
; 3. class Keys - KEY_LIST: single list of ALL valid multi-char
;    key names (canonical AHK spellings). Split at startup into
;    App.ValidKeys; reused by the editor key picker and by the
;    macro-recorder EndKeys. Single-char keys (A-Z, 0-9) are
;    validated by regex and generated for the picker.
; =============================================================
class Keys {
    static List := "Escape,Tab,Enter,Space,Backspace,Delete,Insert,PgUp,PgDn,Home,End,Up,Down,Left,Right,F1,F2,F3,F4,F5,F6,F7,F8,F9,F10,F11,F12,F13,F14,F15,F16,F17,F18,F19,F20,F21,F22,F23,F24,Numpad0,Numpad1,Numpad2,Numpad3,Numpad4,Numpad5,Numpad6,Numpad7,Numpad8,Numpad9,NumpadEnter,NumpadAdd,NumpadSub,NumpadMult,NumpadDiv,NumpadDot,NumpadIns,NumpadDel,NumpadClear,NumpadUp,NumpadDown,NumpadLeft,NumpadRight,NumpadHome,NumpadEnd,NumpadPgUp,NumpadPgDn,LButton,RButton,MButton,XButton1,XButton2,AppsKey,PrintScreen,Pause,ScrollLock,CapsLock,Media_Play_Pause,Media_Stop,Media_Next,Media_Prev,Volume_Mute,Volume_Up,Volume_Down,Browser_Back,Browser_Forward,Browser_Refresh,Browser_Stop,Browser_Search,Browser_Favorites,Browser_Home"
}

; =============================================================
; 4. class Consts - verified Win32 constants (facts file section 1)
;    LVM_FIRST = 0x1000; SETBKCOLOR = +1, SETTEXTCOLOR = +36,
;    SETTEXTBKCOLOR = +38. The old code's 0x30B/0x30C values were
;    wrong (text colors were never applied).
; =============================================================
class Consts {
    static LVM_SETBKCOLOR := 0x1001
    static LVM_SETTEXTCOLOR := 0x1024
    static LVM_SETTEXTBKCOLOR := 0x1026
    ; Main window CLIENT size (Gui.Show w/h = client area on every
    ; platform). The window is fixed-size borderless, so every Show()
    ; passes this explicitly; toolkit auto-sizing (which differs
    ; between AutoHotkey and Keysharp/WinForms/GTK) is never used.
    ; Derived from the BuildMainGui layout constants (D-06):
    ;   WinW = contentX(160) + contentW(726) + marginX(14)         = 900
    ;   WinH = contentY(10) + tabH(820) + 6 + status h24 + marginY(12) = 872
    ; BuildMainGui verifies these against its own constants at build time.
    static WinW := 900
    static WinH := 872
}

; =============================================================
; 5. InitApp - startup sequence (design section 12)
; =============================================================
InitApp() {
    ; --- paths (JoinPath, design D-04) ---
    App.ConfigFile := JoinPath(A_ScriptDir, "keybinds.cfg")
    App.ThemeFile := JoinPath(A_ScriptDir, "theme.cfg")
    App.IniFile := JoinPath(A_ScriptDir, "rebindxsettings.ini")
    App.StartupLnk := JoinPath(A_Startup, App.Name ".lnk")
    logDir := JoinPath(A_AppData, "ReBindX")
    App.LogFile := JoinPath(logDir, "error.log")

    ; sweep leftover @-prefix temp scripts from previous runs
    ; (security review F4; our own file does not exist yet)
    try FileDelete(JoinPath(A_Temp, "ReBindX_expr_*.ahk"))
    ; ...and leftover bash syntax-check temp files (section 6b)
    try FileDelete(JoinPath(A_Temp, "ReBindX_syntax_*.sh"))

    ; --- ValidKeys + picker categories from the single KEY_LIST (D-03) ---
    for , name in StrSplit(Keys.List, ",") {
        App.ValidKeys[StrUpper(name)] := name
        cat := KeyCategory(name)
        if (cat != "") {
            if !App.PickerCats.Has(cat)
                App.PickerCats[cat] := []
            App.PickerCats[cat].Push(name)
        }
    }

    ; --- shell detection, theme, settings, --silent flag ---
    DetectShells()   ; populates App.Shells before LoadSettings reconciles ShellCmd
    LoadTheme()
    LoadSettings()
    isSilent := false
    for , arg in A_Args {
        if (arg = "--silent") {
            isSilent := true
            break
        }
    }
    if (isSilent)
        App.Settings["GuiVisible"] := 0

    ; --- config, GUI, theme, icons, tooltips ---
    report := []
    LoadConfig(App.ConfigFile, &report)
    ; ! hand-edited cfg damage is reported at launch too - but never
    ;   under --silent, where a modal dialog would block invisibly
    if (App.Settings["GuiVisible"])
        ShowCfgReport(report)
    ; * start-as-suspended: seed the flag BEFORE the GUI build so the
    ;   Suspend button shows the right caption; F1/tray stay live
    ;   (RegisterAppHotkeys runs after this)
    App.Suspended := App.Settings["StartSuspended"] ? true : false
    if (App.Suspended) {
        UnregisterAllHotkeys()
        App.PixelWatchers := []
    }
    BuildMainGui()
    ApplyTheme()
    InitRowIcons()
    RefreshGuiData()

    ; --- show EARLY: tooltips/tray/hotkeys attach afterwards (user
    ;     report: the window did not always appear promptly) ---
    if (App.Settings["GuiVisible"])
        App.MainGui.Show(InitialWinSize())
    InstallTips()

    ; --- tray, app hotkeys, exit hook ---
    BuildTrayMenu()
    RegisterAppHotkeys()
    OnExit(ExitFunc, 1)
}

; =============================================================
; 6. Config I/O
; =============================================================

; --- Small shared helpers ---

; Join path parts with "\" (design D-04).
JoinPath(parts*) {
    result := ""
    for , part in parts {
        if (part = "")
            continue
        if (result = "")
            result := part
        else if (SubStr(result, -1) = "\")
            result := result part
        else
            result := result "\" part
    }
    return result
}

; Timestamped line appended to %APPDATA%\ReBindX\error.log.
; ! Must never throw (design D-08): logging is the last line of
;   defense - a throw here would kill the handler being logged.
; Parent dir is created lazily; entries are capped at 2000 chars so a
; huge imported config cannot balloon the log (security review F8).
LogError(msg) {
    try {
        if (StrLen(msg) > 2000)
            msg := SubStr(msg, 1, 2000) "..."
        logDir := JoinPath(A_AppData, "ReBindX")
        if !DirExist(logDir)
            DirCreate(logDir)
        logFile := (App.LogFile != "") ? App.LogFile : JoinPath(logDir, "error.log")
        FileAppend(A_Now " [" A_ScriptName "] " msg "`r`n", logFile, "UTF-8-RAW")
    } catch as Err {
        return   ; logging must never crash the script - swallow
    }
}

; Transient feedback on the bottom status strip; auto-clears
; after 4 s through ONE managed timer.
; * the -4000 one-shot timer is re-armed per message, never stacked
SetStatus(msg) {
    if !App.Ui.Has("Status")
        return
    try {
        App.Ui["Status"].Text := msg
        if (msg != "")
            SetTimer(ClearStatus, -4000)
    } catch as Err {
        LogError("status: " Err.Message)
    }
}

ClearStatus(*) {
    if !App.Ui.Has("Status")
        return
    try App.Ui["Status"].Text := ""
    catch as Err {
        return   ; never crash for status cleanup
    }
}

; Mark bindings as changed (BUG-08). Set by every mutation,
; cleared by a successful SaveConfig of the main config file.
; * Autosave: a debounced -500 timer fires a SILENT save - changes
;   persist without any status-strip feedback.
SetDirty() {
    App.IsDirty := true
    if (App.Settings["Autosave"])
        SetTimer(AutosaveFire, -500)
}

; Silent debounced autosave (armed by SetDirty when Autosave is on).
AutosaveFire() {
    if (App.Settings["Autosave"] && App.IsDirty)
        SaveConfig(App.ConfigFile, true)
}

; Total number of bindings across all profiles.
CountAllBindings() {
    n := 0
    for , profile in App.Profiles
        n += profile.Count
    return n
}

; ! Never-throw integer parse for values that may come from config
;   files, INI files or UI controls: returns `def` when the value is
;   blank or non-numeric ("abcd"), otherwise the integer (decimal
;   text like "250.0" truncates; "-13" parses - callers clamp).
SafeInt(v, def) {
    try {
        if IsInteger(v)
            return Integer(v)
        v := Trim("" v)
        if RegExMatch(v, "^-?\d+([.,]\d+)?$")
            return Integer(RegExReplace(v, "[.,]\d+$", ""))
    } catch as Err {
        ; a sanitizer must never throw
    }
    return def
}

; --- theme.cfg (feature 8; read with FileRead, D-05) ---

LoadTheme() {
    ; "Hint" is the dimmed empty-state text color, preset per theme to
    ; pass WCAG AA on its Background (a11y review P1-2: the old fixed
    ; 808080 scored 4.22:1 on dark and 3.56:1 on light - both fail).
    dark := Map("Background", "1E1E1E", "Control", "3A3A3A", "Text", "FFFFFF", "Hint", "9E9E9E", "Transparency", "255")
    light := Map("Background", "F3F3F3", "Control", "EDEDED", "Text", "1A1A1A", "Hint", "595959", "Transparency", "255")
    theme := dark
    auto := 0
    fileVals := Map()
    if FileExist(App.ThemeFile) {
        try {
            text := FileRead(App.ThemeFile, "UTF-8")
            for , raw in StrSplit(text, "`n", "`r") {
                line := Trim(raw)
                if (line = "" || SubStr(line, 1, 1) = ";")
                    continue
                pos := InStr(line, "=")
                if (pos = 0)
                    continue
                key := Trim(SubStr(line, 1, pos - 1))
                val := Trim(SubStr(line, pos + 1))
                if (key = "Auto") {
                    auto := (val = "1") ? 1 : 0
                } else if (key = "Background" || key = "Control" || key = "Text" || key = "Hint" || key = "Transparency") {
                    fileVals[key] := val
                }
            }
        } catch as Err {
            LogError("theme read failed: " Err.Message)
        }
    }
    if (auto) {
        useLight := 0
        try useLight := RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "AppsUseLightTheme", 0)
        catch as Err {
            useLight := 0
        }
        theme := useLight ? light : dark
    }
    ; explicit keys in the file override the preset individually -
    ; but only when they are VALID, so a hand-corrupted theme.cfg can
    ; never abort GUI construction downstream (review finding 6).
    for key, val in fileVals {
        if (key = "Transparency") {
            ; ! 0 = a fully transparent (invisible, unrecoverable)
            ;   window - clamp at 16 so a hand-set 0 stays faint but usable
            if val is Integer && (val >= 16 && val <= 255)
                theme[key] := val
            else
                LogError("theme: invalid Transparency '" val "' (16..255) - using preset")
        } else {
            if RegExMatch(val, "^[0-9A-Fa-f]{6}$")
                theme[key] := val
            else
                LogError("theme: invalid " key " '" val "' - using preset")
        }
    }
    App.Theme := theme
}

; Restyle both ListViews with the verified LVM constants (D-02)
; and keep the existing BGR byte-swap math (theme hex is RRGGBB,
; COLORREF is 0x00BBGGRR).
StyleListView(LV) {
    if !IsObject(LV)
        return
    try {
        bg := Integer("0x" App.Theme["Background"])
        txt := Integer("0x" App.Theme["Text"])
        bgBgr := (bg & 0xFF) << 16 | (bg & 0xFF00) | (bg & 0xFF0000) >> 16
        txtBgr := (txt & 0xFF) << 16 | (txt & 0xFF00) | (txt & 0xFF0000) >> 16
        LV.Opt("+Background" App.Theme["Background"])
        SendMessage(Consts.LVM_SETBKCOLOR, 0, bgBgr, LV.Hwnd)
        SendMessage(Consts.LVM_SETTEXTCOLOR, 0, txtBgr, LV.Hwnd)
        SendMessage(Consts.LVM_SETTEXTBKCOLOR, 0, bgBgr, LV.Hwnd)
    } catch as Err {
        LogError("listview style failed: " Err.Message)
    }
}

ApplyTheme() {
    if !IsObject(App.MainGui)
        return
    try {
        App.MainGui.BackColor := App.Theme["Background"]
        WinSetTransparent(Integer(App.Theme["Transparency"]), App.MainGui)
    } catch as Err {
        LogError("theme apply failed: " Err.Message)
    }
    StyleListView(App.LV_Cmd)
    StyleListView(App.LV_Key)
}

; --- rebindxsettings.ini (BUG-06: UTF-16 with BOM is the only
;     Unicode encoding IniRead/IniWrite support; facts section 9) ---

; Returns "UTF-16" (FF FE / FE FF), "UTF-8BOM" (EF BB BF),
; "CP0" (no BOM) or "" on I/O problem (facts section 10c).
DetectFileBOM(file) {
    try {
        f := FileOpen(file, "r")
        if !IsObject(f)
            return ""
        buf := Buffer(2, 0)
        n := f.RawRead(buf, 2)   ; returns the number of bytes read
        f.Close()
        if (n < 2)
            return "CP0"
        b := NumGet(buf, 0, "UShort")
        if (b = 0xFEFF || b = 0xFFFE)   ; FF FE (LE) or FE FF (BE)
            return "UTF-16"
        if (b = 0xBBEF)                   ; EF BB (BF) = UTF-8 BOM
            return "UTF-8BOM"
        return "CP0"
    } catch as Err {
        return ""
    }
}

; One-time settings-INI normalization: rewrite as UTF-16 with
; BOM unless the file already is UTF-16.
; ! Never converts TO UTF-8: Win32 IniRead/IniWrite hide the first
;   [Section] header of a UTF-8 file (BUG-06, facts section 9).
EnsureIniUtf16(file) {
    if !FileExist(file)
        return true
    bom := DetectFileBOM(file)
    if (bom = "UTF-16")
        return true
    text := ""
    try {
        text := (bom = "UTF-8BOM") ? FileRead(file, "UTF-8") : FileRead(file, "CP0")
        FileDelete(file)
        FileAppend(text, file, "UTF-16")   ; new file => BOM written
        return true
    } catch as Err {
        LogError("INI migration failed: " Err.Message)
        try {
            ; best-effort restore so settings are not lost
            if (text != "" && !FileExist(file))
                FileAppend(text, file, "UTF-16")
        } catch as Err2 {
            LogError("INI restore failed: " Err2.Message)
        }
        return false
    }
}

; IniRead with an explicit default (facts section 9: a default-less
; read throws OSError on a missing key), integer-parsed and clamped.
ReadIniInt(key, def, minV, maxV) {
    try {
        v := Integer(Trim(IniRead(App.IniFile, "SETTINGS", key, def)))
        if (v < minV)
            return minV
        if (v > maxV)
            return maxV
        return v
    } catch as Err {
        LogError("ini read '" key "': " Err.Message)
        return def
    }
}

ReadIniStr(key, def) {
    try {
        return IniRead(App.IniFile, "SETTINGS", key, def)
    } catch as Err {
        LogError("ini read '" key "': " Err.Message)
        return def
    }
}

LoadSettings() {
    s := Map()
    s["DoRepeatOutputs"] := 0
    s["RepeatBuffer"] := 0
    s["RepeatDelay"] := 0
    s["ActiveProfile"] := "Default"
    s["ShellCmd"] := "cmd"
    s["ShellHidden"] := 1
    s["WarnedDefaultOverride"] := 0
    s["GuiVisible"] := 1
    s["StartSuspended"] := 0
    s["Autosave"] := 0
    s["DoStartup"] := FileExist(App.StartupLnk) ? 1 : 0   ; seeded, never persisted
    EnsureIniUtf16(App.IniFile)
    if FileExist(App.IniFile) {
        s["DoRepeatOutputs"] := ReadIniInt("DoRepeatOutputs", 0, 0, 1)
        s["RepeatBuffer"] := ReadIniInt("RepeatBuffer", 0, 0, 1000)
        s["RepeatDelay"] := ReadIniInt("RepeatDelay", 0, 0, 500)
        s["ActiveProfile"] := ReadIniStr("ActiveProfile", "Default")
        s["ShellCmd"] := ReadIniStr("ShellCmd", "cmd")
        s["ShellHidden"] := ReadIniInt("ShellHidden", 1, 0, 1)
        s["GuiVisible"] := ReadIniInt("GuiVisible", 1, 0, 1)
        s["StartSuspended"] := ReadIniInt("StartSuspended", 0, 0, 1)
        s["Autosave"] := ReadIniInt("Autosave", 0, 0, 1)
    }
    ; ShellCmd is now a shell Id; "cmd" and "powershell" from older
    ; versions remain valid Ids. Reconcile against the detected list
    ; (DetectShells runs first): an unknown Id falls back to the
    ; first detected shell, so the setting can never point at a
    ; missing shell.
    if (App.Shells.Length > 0) {
        found := false
        for , sh in App.Shells {
            if (sh["Id"] = s["ShellCmd"]) {
                found := true
                break
            }
        }
        if !found
            s["ShellCmd"] := App.Shells[1]["Id"]
    }
    App.Settings := s
}

SaveSettings() {
    try {
        IniWrite(App.Settings["DoRepeatOutputs"], App.IniFile, "SETTINGS", "DoRepeatOutputs")
        IniWrite(App.Settings["RepeatBuffer"], App.IniFile, "SETTINGS", "RepeatBuffer")
        IniWrite(App.Settings["RepeatDelay"], App.IniFile, "SETTINGS", "RepeatDelay")
        IniWrite(App.Settings["ActiveProfile"], App.IniFile, "SETTINGS", "ActiveProfile")
        IniWrite(App.Settings["ShellCmd"], App.IniFile, "SETTINGS", "ShellCmd")
        IniWrite(App.Settings["ShellHidden"], App.IniFile, "SETTINGS", "ShellHidden")
        IniWrite(App.Settings["GuiVisible"], App.IniFile, "SETTINGS", "GuiVisible")
        IniWrite(App.Settings["StartSuspended"], App.IniFile, "SETTINGS", "StartSuspended")
        IniWrite(App.Settings["Autosave"], App.IniFile, "SETTINGS", "Autosave")
    } catch as Err {
        LogError("settings write failed: " Err.Message)
    }
}

; =============================================================
; 6b. Shell detection + shell execution (dynamic shell layer)
; =============================================================

; Build one shell Map from its Id / display name / absolute path.
; The small semantics table here encodes HOW each shell takes a
; command (never WHETHER it exists): cmd -> /c; powershell/pwsh ->
; -Command; everything else (bash zsh sh dash ksh fish ...) accepts
; sh -c style, hence Family "posix" / ArgStyle "-c".
MakeShellMap(id, name, path) {
    if (id = "cmd") {
        family := "cmd"
        argStyle := "/c"
    } else if (id = "powershell" || id = "pwsh") {
        family := "ps"
        argStyle := "-Command"
    } else {
        family := "posix"
        argStyle := "-c"
    }
    return Map("Id", id, "Name", name, "Path", path, "ArgStyle", argStyle, "Family", family)
}

; Append one shell entry to App.Shells, deduplicated by Id (the
; first detected path wins). Undetectable entries (Path "") are
; skipped per the data model.
AddDetectedShell(id, name, path) {
    if (id = "" || path = "")
        return
    for , sh in App.Shells {
        if (sh["Id"] = id)
            return
    }
    App.Shells.Push(MakeShellMap(id, name, path))
}

; // ShellBaseName() removed - dead code here (the Windows probes name
; // their shell Ids directly). The .ks keeps it for its Unix
; // /etc/shells branch; see rebindx.ks.

; PATH search helper: the first PATH directory holding `name`
; wins; returns "" when nothing matched.
SearchPathFor(name) {
    try {
        for , dir in StrSplit(EnvGet("PATH"), ";") {
            if (dir = "")
                continue
            candidate := JoinPath(dir, name)
            if FileExist(candidate)
                return candidate
        }
    } catch as Err {
        LogError("PATH search '" name "': " Err.Message)
    }
    return ""
}

; Populate App.Shells at startup, before LoadSettings reads the
; ShellCmd Id. Every probe is guarded; detection failure degrades
; to the fallback entry, so the list is never empty.
DetectShells() {
    App.Shells := []
    ; --- Windows: cmd is always present via A_ComSpec; PowerShell,
    ;     pwsh and bash are probed at their standard locations or
    ;     via PATH. ---
    AddDetectedShell("cmd", "cmd", A_ComSpec)
    psPath := JoinPath(A_WinDir, "System32\WindowsPowerShell\v1.0\powershell.exe")
    if FileExist(psPath)
        AddDetectedShell("powershell", "PowerShell", psPath)
    pwshPath := SearchPathFor("pwsh.exe")
    if (pwshPath = "") {
        pwshPath := JoinPath(A_ProgramFiles, "PowerShell\7\pwsh.exe")
        if !FileExist(pwshPath)
            pwshPath := ""
    }
    if (pwshPath != "")
        AddDetectedShell("pwsh", "pwsh", pwshPath)
    ; Git-for-Windows bash is probed FIRST (final review F6): a bare
    ; PATH search can surface WSL's System32\bash.exe, which would
    ; silently run & commands inside WSL with foreign path semantics.
    bashPath := ""
    gitBash := JoinPath(A_ProgramFiles, "Git\bin\bash.exe")
    if !FileExist(gitBash)
        gitBash := JoinPath(A_ProgramFiles, "Git\usr\bin\bash.exe")
    if FileExist(gitBash)
        bashPath := gitBash
    if (bashPath = "")
        bashPath := SearchPathFor("bash.exe")
    if (bashPath != "" && InStr(bashPath, A_WinDir "\") = 1)
        bashPath := ""   ; System32\bash.exe is WSL, not a Windows shell
    if (bashPath != "")
        AddDetectedShell("bash", "bash", bashPath)
    ; * paranoia: never leave the list empty - the DDL (and the shell
    ;   selection) would have nothing to show.
    if (App.Shells.Length = 0)
        AddDetectedShell("cmd", "cmd", A_ComSpec)
}

; Look up a detected shell by Id. An unknown Id gets the documented
; fallback (cmd via A_ComSpec) so command dispatch always has a
; shell to run through.
GetShellById(id) {
    for , sh in App.Shells {
        if (sh["Id"] = id)
            return sh
    }
    return MakeShellMap("cmd", "cmd", A_ComSpec)
}

; Escape a command for the posix -c "..." wrapper so the command-
; line parser hands the shell EXACTLY the original text. Backslashes
; are doubled first (a payload \ before a " would otherwise close
; the double-quoted argument early and mangle the command - caught
; by the spec's third hand-check case), then every internal "
; becomes \", which the parser folds back into a literal quote.
EscapePosixQuotes(s) {
    s := StrReplace(s, "\", "\\")
    return StrReplace(s, '"', '\"')
}

; Run `rest` through `shell` (a Map from App.Shells or the
; GetShellById fallback). Bash shells get an always-on bash -n
; syntax validation first (milliseconds; only bash - other shells
; have incompatible syntax and could be false-rejected): a failing
; command is logged and NOT executed. Returns true when the command
; was launched, false when it was rejected or the launch failed.
RunViaShell(shell, rest, hidden) {
    try {
        if (shell["Id"] = "bash" && shell["Path"] != "") {
            ; per-process temp file; the startup sweep clears any
            ; leftovers (same pattern as the @ prefix, review F4)
            file := JoinPath(A_Temp, "ReBindX_syntax_" A_ScriptHwnd ".sh")
            try {
                if FileExist(file)
                    FileDelete(file)
                FileAppend(rest "`n", file, "UTF-8-RAW")
                ; RunWait RETURNS the exit code; its 4th parameter is a
                ; PID output, not the exit code
                exitCode := RunWait('"' shell["Path"] '" -n "' file '"', , "Hide")
            } catch as ErrV {
                try if FileExist(file)
                    FileDelete(file)   ; final review F8: no temp leak on throw
                throw ErrV
            }
            if FileExist(file)
                FileDelete(file)
            if (exitCode != 0) {
                LogError("bash syntax error (exit " exitCode ") in: " rest)
                SetStatus("bash syntax error - see error log")
                return false
            }
        }
        switch shell["Family"] {
            case "cmd":
                Run(A_ComSpec " /c " rest, , hidden)
            case "ps":
                Run('"' shell["Path"] '" -NoProfile -Command ' rest, , hidden)
            default:
                ; posix: -c with the command double-quoted, inner
                ; quotes escaped (zsh/fish/sh/dash all accept sh -c)
                Run('"' shell["Path"] '" -c "' EscapePosixQuotes(rest) '"', , hidden)
        }
        return true
    } catch as Err {
        LogError("shell run failed via " shell["Id"] " (" rest "): " Err.Message)
        SetStatus("Command failed - see error log")
        return false
    }
}

; --- keybinds.cfg (design section 2 grammar) ---

; Parse per the rev-2 grammar and REPLACE all profiles in memory.
; Malformed lines are skipped, logged and collected into `report`
; (BUG-07). Duplicate ids in the file are reported; last one wins.
; Returns false without touching profiles/hotkeys if the file is
; unreadable (a missing file leaves an empty Default profile, as
; the data model requires). register=false (import preview):
; commit + refresh but do NOT activate hotkeys yet - the caller
; decides (security review F3).
LoadConfig(file, &report, register := true) {
    report := []
    if (file = "")
        file := App.ConfigFile
    if !FileExist(file) {
        if !App.Profiles.Has("Default")
            App.Profiles["Default"] := Map()
        return false
    }
    text := ""
    try text := FileRead(file, "UTF-8")
    catch as Err {
        LogError("config read failed (" file "): " Err.Message)
        return false
    }
    newProfiles := Map("Default", Map())
    curProfile := newProfiles["Default"]
    curProfileName := "Default"
    newPMacros := Map("Default", Map())
    newPSettings := Map("Default", Map())
    section := "cmd"
    inMacros := false
    lineNo := 0
    for , raw in StrSplit(text, "`n", "`r") {
        lineNo++
        line := Trim(raw)
        ; comments are skipped BEFORE any splitting
        if (line = "" || SubStr(line, 1, 1) = ";")
            continue
        ; profile header: [Profile:Name]
        if (SubStr(line, 1, 9) = "[Profile:" && SubStr(line, -1) = "]") {
            inMacros := false
            name := Trim(SubStr(line, 10, StrLen(line) - 10))
            if (name = "") {
                report.Push({Line: lineNo, Text: raw, Reason: "empty profile name"})
                LogError("cfg line " lineNo ": empty profile name - skipped")
                continue
            }
            if !newProfiles.Has(name) {
                newProfiles[name] := Map()
                newPMacros[name] := Map()
                newPSettings[name] := Map()
            }
            curProfile := newProfiles[name]
            curProfileName := name
            section := "cmd"
            continue
        }
        ; [Macros]: the global macro library (name;sequence)
        if (line = "[Macros]") {
            inMacros := true
            continue
        }
        if (inMacros) {
            mparts := StrSplit(line, ";", , 2)
            if (mparts.Length < 2 || Trim(mparts[1]) = "" || Trim(mparts[2]) = "") {
                report.Push({Line: lineNo, Text: raw, Reason: "malformed macro (expected NAME;SEQUENCE)"})
                LogError("cfg line " lineNo ": malformed macro - skipped")
                continue
            }
            mname := Trim(mparts[1])
            newPMacros["Default"][mname] := StrReplace(Trim(mparts[2]), "{SEMICOLON}", ";")
            continue
        }
        if (inMacros)
            continue
        ; separator: a full line of 3+ dashes switches cmd -> key
        if RegExMatch(line, "^-{3,}$") {
            section := "key"
            continue
        }
        ; binding: keypart ";" payload - split at the FIRST ";"
        ; only, so extra semicolons stay in the payload (BUG-07)
        parts := StrSplit(line, ";", , 2)
        if (parts.Length < 2 || Trim(parts[1]) = "" || Trim(parts[2]) = "") {
            report.Push({Line: lineNo, Text: raw, Reason: "malformed line (expected KEY;PAYLOAD)"})
            LogError("cfg line " lineNo ": malformed line - skipped")
            continue
        }
        keypart := Trim(parts[1])
        payload := Trim(parts[2])
        ; "*" prefix = disabled binding
        enabled := true
        if (SubStr(keypart, 1, 1) = "*") {
            enabled := false
            keypart := Trim(SubStr(keypart, 2))
        }
        ; "[wintitle]" suffix = per-app scope (feature 11)
        scope := ""
        if RegExMatch(keypart, "^([^\[\]]*)\[(.*)\]$", &m) {
            keypart := Trim(m[1])
            scope := m[2]
        }
        if (SubStr(keypart, 1, 6) = "macro:" || SubStr(keypart, 1, 4) = "set:") {
            ; per-profile macro and settings entries live inside the section
            k := SubStr(keypart, 1, 6) = "macro:" ? SubStr(keypart, 7) : SubStr(keypart, 5)
            if (k = "") {
                report.Push({Line: lineNo, Text: raw, Reason: "empty macro/set name"})
                LogError("cfg line " lineNo ": empty macro/set name - skipped")
                continue
            }
            v := StrReplace(payload, "{SEMICOLON}", ";")
            if (SubStr(keypart, 1, 6) = "macro:")
                newPMacros[curProfileName][k] := v
            else
                newPSettings[curProfileName][k] := v
            continue
        }
        if (SubStr(keypart, 1, 3) = "hs:" || SubStr(keypart, 1, 3) = "px:") {
            key := keypart
            icp := ""
            if (SubStr(key, 1, 3) = "hs:") {
                hsText := SubStr(key, 4)
                if (hsText = "" || InStr(hsText, "|")) {
                    report.Push({Line: lineNo, Text: raw, Reason: "invalid hotstring trigger"})
                    LogError("cfg line " lineNo ": invalid hotstring trigger - skipped")
                    continue
                }
            } else {
                pp := StrSplit(SubStr(key, 4), ",")
                pxOk := (pp.Length >= 4)
                if pxOk {
                    try {
                        Integer(pp[1])
                        Integer(pp[2])
                    } catch as ErrP {
                        pxOk := false
                    }
                    if (pxOk && !RegExMatch(StrUpper(pp[3]), "^[0-9A-F]{6}$"))
                        pxOk := false
                    if (pxOk && pp[4] != "to" && pp[4] != "from")
                        pxOk := false
                }
                if !pxOk {
                    report.Push({Line: lineNo, Text: raw, Reason: "invalid pixel trigger (expected px:X,Y,RRGGBB,to|from)"})
                    LogError("cfg line " lineNo ": invalid pixel trigger - skipped")
                    continue
                }
            }
        } else {
            ; trailing ~/$/* run = the interception type (B~, B$* ...)
            icp := ""
            if RegExMatch(keypart, "[~$*]+$", &im) {
                icp := im[0]
                keypart := SubStr(keypart, 1, StrLen(keypart) - StrLen(icp))
            }
            key := NormalizeKey(keypart)
            if (key = "") {
                report.Push({Line: lineNo, Text: raw, Reason: "invalid key '" keypart "'"})
                LogError("cfg line " lineNo ": invalid key '" keypart "' - skipped")
                continue
            }
        }
        payload := StrReplace(payload, "{SEMICOLON}", ";")
        type := (section = "cmd") ? "cmd" : "key"
        action := (type = "key") ? NormalizeAction(payload) : payload
        id := type "|" key "|" scope
        if curProfile.Has(id) {
            report.Push({Line: lineNo, Text: raw, Reason: "duplicate binding (last wins)"})
            LogError("cfg line " lineNo ": duplicate id " id " - last one wins")
        }
        ; Seq preserves "later line wins" across restarts: the
        ; dispatcher picks the highest-Seq enabled binding per variant
        App.Seq++
        curProfile[id] := Map("Type", type, "Key", key, "Scope", scope, "Action", action, "Enabled", enabled, "Icp", icp, "Seq", App.Seq)
    }
    ; commit: replace all profiles, one register pass, one refresh
    UnregisterAllHotkeys()
    App.Profiles := newProfiles
    App.ProfileMacros := newPMacros
    App.ProfileSettings := newPSettings
    ; * the LAST active profile (INI) is restored at launch: a name
    ;   missing from the cfg is created empty instead of falling back
    ;   to Default - closing without saving must not lose the selection
    want2 := App.Settings["ActiveProfile"]
    if (want2 = "")
        want2 := "Default"
    if !newProfiles.Has(want2) {
        newProfiles[want2] := Map()
        newPMacros[want2] := Map()
        newPSettings[want2] := Map()
    }
    App.ActiveProfile := want2
    SetProfileView(App.ActiveProfile)
    ; // App.MacroLib := App.ProfileMacros[App.ActiveProfile] - removed:
    ; // redundant, SetProfileView already pointed the view at the profile
    if !App.Profiles.Has("Default")
        App.Profiles["Default"] := Map()
    ; // want := App.Settings["ActiveProfile"] - removed: dead local
    App.Settings["ActiveProfile"] := App.ActiveProfile
    if (register)
        RegisterAllHotkeys()
    App.IsDirty := false
    RebuildProfilesMenu()
    RefreshGuiData()
    return true
}

; MsgBox summary of rejected lines (truncated to 10, total shown).
ShowCfgReport(report) {
    if (report.Length = 0)
        return
    msg := "The configuration file contained " report.Length " rejected line(s):`n`n"
    shown := 0
    for , r in report {
        if (shown >= 10) {
            msg .= "... and " (report.Length - shown) " more`n"
            break
        }
        msg .= "Line " r.Line ": " r.Reason "`n"
        shown++
    }
    try MsgBox(msg, App.Name, "Icon!")
    catch as Err {
        LogError("report dialog failed: " Err.Message)
    }
}

; Write every profile per the section-2 grammar. Default profile
; is headerless (old AHK versions can still read the file); every
; other profile gets its [Profile:Name] header. CRLF line endings,
; UTF-8 without BOM ("UTF-8-RAW").
; * The write is ATOMIC: the text goes to a .tmp file which then
;   replaces the target via FileMove, so a crash / disk-full / AV
;   lock can never destroy the old config (security review F2).
SaveConfig(file := "", quiet := false) {
    if (file = "")
        file := App.ConfigFile
    tmp := file ".tmp"
    try {
        text := BuildConfigText()
        if FileExist(tmp)
            FileDelete(tmp)
        FileAppend(text, tmp, "UTF-8-RAW")
        FileMove(tmp, file, 1)
    } catch as Err {
        LogError("save failed (" file ", partial text in " tmp "): " Err.Message)
        SetStatus("Save failed - see error log")
        return false
    }
    if (file = App.ConfigFile) {
        App.IsDirty := false
        if !quiet {   ; * autosave fires silently - no status-strip feedback
            n := CountAllBindings()
            SetStatus("Saved " n " bindings")
            TrayTip("Saved " n " bindings", App.Name, "Iconi")
        }
    } else if !quiet {
        SetStatus("Exported " CountAllBindings() " bindings")
    }
    return true
}

BuildConfigText() {
    ; sync the per-profile settings from the live App.Settings first
    if !App.ProfileSettings.Has(App.ActiveProfile)
        App.ProfileSettings[App.ActiveProfile] := Map()
    ps := App.ProfileSettings[App.ActiveProfile]
    for , k in ["DoRepeatOutputs", "RepeatBuffer", "RepeatDelay"]
        ps[k] := App.Settings[k]
    ; * The Default profile is written FIRST, explicitly by name, so
    ;   the output never depends on Map enumeration order (AHK Maps
    ;   keep insertion order, Keysharp's are sorted before enumeration).
    text := ""
    first := true
    if App.Profiles.Has("Default") {
        text .= ProfileSectionText("Default", App.Profiles["Default"])
        first := false
    }
    for name, profile in App.Profiles {
        if (name = "Default")
            continue
        if !first
            text .= "`r`n"
        text .= ProfileSectionText(name, profile)
        first := false
    }
    return text
}

; One profile's cfg section: [Profile:Name] header for non-Default
; profiles, command bindings, separator, key bindings.
ProfileSectionText(name, profile) {
    eol := "`r`n"
    s := (name != "Default") ? "[Profile:" name "]" eol : ""
    pm := App.ProfileSettings.Has(name) ? App.ProfileSettings[name] : 0
    if IsObject(pm) {
        for k, v in pm
            s .= "set:" k ";" v eol
    }
    if App.ProfileMacros.Has(name) {
        for mn, ms in App.ProfileMacros[name]
            s .= "macro:" mn ";" StrReplace(ms, ";", "{SEMICOLON}") eol
    }
    for , b in profile {
        if (b["Type"] = "cmd")
            s .= FormatBindingLine(b) eol
    }
    s .= "-------------" eol
    for , b in profile {
        if (b["Type"] = "key")
            s .= FormatBindingLine(b) eol
    }
    return s
}

; "*" prefix for disabled, "[scope]" suffix for scoped bindings.
; * {SEMICOLON} escaping makes literal semicolons round-trip - the
;   grammar's one hard separator.
FormatBindingLine(b) {
    keyText := (b["Enabled"] ? "" : "*") . b["Key"] . BindingIcp(b) . (b["Scope"] != "" ? "[" b["Scope"] "]" : "")
    return keyText ";" StrReplace(b["Action"], ";", "{SEMICOLON}")
}

; --- Load / Save / Import / Export button + tray flows ---

; Sidebar/tray Save: write keybinds.cfg atomically.
SaveBindings(*) {
    SaveConfig(App.ConfigFile)
}

; // Apply button + ApplyBindings removed (round 114): binding changes
; // apply live (the engine registers on every mutation) and Autosave
; // covers persistence; the button slot is now Suspend/Unsuspend.

LoadBindings(*) {
    report := []
    if !LoadConfig(App.ConfigFile, &report) {
        SetStatus("Config file not found or unreadable")
        return
    }
    ShowCfgReport(report)
    LoadTheme()
    ApplyTheme()
    SetStatus("Configuration loaded")
    TrayTip("Configuration loaded", App.Name, "Iconi")
}

ImportConfig(*) {
    file := FileSelect(3, , "Select a .cfg file to import", "Config Files (*.cfg)")
    if (file = "")
        return
    report := []
    PushUndo()
    ; Preview: load to memory WITHOUT activating anything (F3 gate).
    if !LoadConfig(file, &report, false) {
        SetStatus("Import failed - see error log")
        return
    }
    ShowCfgReport(report)
    nEnabled := CountEnabledBindings()
    msg := "Imported " CountAllBindings() " bindings (" nEnabled " enabled in this profile).`n`n"
    msg .= "Yes = activate the enabled bindings now`n"
    msg .= "No = import everything as disabled`n"
    msg .= "Cancel = undo this import"
    switch MsgBox(msg, App.Name, "YesNoCancel Icon! Default2") {
        case "Cancel":
            Undo()
            SetStatus("Import cancelled")
            return
        case "No":
            DisableAllBindings()
    }
    RegisterAllHotkeys()
    RefreshGuiData()
    SetDirty()
    SetStatus("Imported " CountAllBindings() " bindings, rejected " report.Length)
    TrayTip("Imported " CountAllBindings() " bindings", App.Name, "Iconi")
}

; Enabled-binding count of the ACTIVE profile (import gate message).
CountEnabledBindings() {
    n := 0
    for , b in ActiveProfileMap() {
        if (b["Enabled"])
            n++
    }
    return n
}

; Mark every binding in EVERY profile disabled (import gate, "No").
DisableAllBindings() {
    for , profile in App.Profiles {
        for , b in profile
            b["Enabled"] := false
    }
}

ExportConfig(*) {
    file := FileSelect("S24", JoinPath(A_ScriptDir, "save.cfg"), "Save settings", "Config Files (*.cfg)")
    if (file = "")
        return
    SaveConfig(file)
}

; =============================================================
; 7. Hotkey engine (design section 3)
; =============================================================

; Text-syntax modifier conversion (extra-defect fix: the old two-pass
; regex mangled "waltz" -> "w!z"). Four plain string replacements -
; RegExReplace's Replacement parameter is Type: String in v2.0 (no
; callback form; that is v2.1-alpha only). Word boundaries protect
; non-modifier words; the optional trailing "+" is consumed so
; "WIN+CTRL+ALT+G" and "win g" both produce "#^!G".
; Order is irrelevant: the four words share no boundaries.
ConvertModifierWords(str) {
    str := RegExReplace(str, "i)\bWIN\b\+?", "#")
    str := RegExReplace(str, "i)\bCTRL\b\+?", "^")
    str := RegExReplace(str, "i)\bALT\b\+?", "!")
    str := RegExReplace(str, "i)\bSHIFT\b\+?", "+")
    return str
}

; Keep the old pipeline (trim, strip "$", text->symbol, whitespace
; strip, duplicate-modifier check, final regex) with two changes:
; word-boundary modifier words and canonical casing of the base key
; (single char uppercased, multi-char via ValidKeys) so ids and
; Hotkey() variant lookups stay consistent.
NormalizeKey(key) {
    if (key = "")
        return ""
    key := Trim(key)
    key := RegExReplace(key, "^\$")
    key := ConvertModifierWords(key)
    key := RegExReplace(key, "\s")
    pos := RegExMatch(key, "[\w]")
    if (pos = 0)
        return ""
    modifiers := SubStr(key, 1, pos - 1)
    baseKey := SubStr(key, pos)
    if (StrLen(baseKey) = 1) {
        baseKey := StrUpper(baseKey)
    } else {
        upper := StrUpper(baseKey)
        if !App.ValidKeys.Has(upper)
            return ""
        baseKey := App.ValidKeys[upper]
    }
    ; duplicate-modifier check (e.g. "#^#G" is invalid)
    if (StrLen(RegExReplace(modifiers, "[^#]", "")) > 1)
        return ""
    if (StrLen(RegExReplace(modifiers, "[^\^]", "")) > 1)
        return ""
    if (StrLen(RegExReplace(modifiers, "[^!]", "")) > 1)
        return ""
    if (StrLen(RegExReplace(modifiers, "[^+]", "")) > 1)
        return ""
    if !RegExMatch(baseKey, "^[\w]+$")
        return ""
    key := modifiers baseKey
    if !RegExMatch(key, "^[\^!+#]*[\w]+$")
        return ""
    return key
}

; Word-boundary modifier conversion for key-binding actions - but
; ONLY when the ENTIRE action is text syntax (modifier words plus an
; optional final key and repeat count). Macro strings pass through
; untouched, so recorded text like "press alt now" is never mangled.
NormalizeAction(action) {
    action := Trim(action)
    if RegExMatch(action, "i)^(?:WIN|CTRL|ALT|SHIFT)(?:[\s+]+(?:WIN|CTRL|ALT|SHIFT))*[\s+]+(?:\{[^}]+\}|\w+)(?:[ ]+\d+)?$") {
        action := RegExReplace(action, "i)\bWIN[\s+]*", "#")
        action := RegExReplace(action, "i)\bCTRL[\s+]*", "^")
        action := RegExReplace(action, "i)\bALT[\s+]*", "!")
        action := RegExReplace(action, "i)\bSHIFT[\s+]*", "+")
    }
    return action
}

; The active profile's binding map (auto-vivified, never throws).
ActiveProfileMap() {
    if !App.Profiles.Has(App.ActiveProfile)
        App.Profiles[App.ActiveProfile] := Map()
    return App.Profiles[App.ActiveProfile]
}

GetBinding(id) {
    profile := ActiveProfileMap()
    return profile.Has(id) ? profile[id] : 0
}

; Hotkey name as registered.
; ! The "$" (keyboard-hook) prefix prevents our own Send output from
;   re-triggering our hotkeys - without it a remap loop echoes
;   forever. The Keysharp port registers bare names off-Windows (no
;   Win32 hook convention there) - see rebindx.ks.
HkName(key) {
    return "$" key
}

; Variant name = engine hook prefix + the binding's interception
; type ("" = none).
; * the engine "$" is skipped when the user's own prefix already
;   contains it (no "$$B" doubles)
HkVariantName(key, icp) {
    p := icp
    if !InStr(p, "$")
        p := "$" p
    return p key
}

; --- Hotkey variant DISPATCHER architecture (runtime round 3) ---
; * One hotkey VARIANT per unique Key+Scope carries ONE dispatcher
; callback that is installed a single time and NEVER swapped. At
; fire time the dispatcher resolves the effective binding: the
; highest-Seq ENABLED binding with that Key+Scope ("later
; registration wins", matching the documented conflict semantics).
; Consequences: adding / deleting / toggling a binding never
; re-registers the variant (one portal interaction per unique key
; - critical under Hyprland, where every Hotkey() call emits GLib
; -CRITICAL warnings), and deleting the later of two same-trigger
; bindings instantly falls back to the earlier one (user report:
; the old off/re-register dance left the survivor dead).

; Store/update a binding in the ACTIVE profile and ensure its
; variant exists. The variant's On/Off state is reconciled from the
; bindings, and the criterion is set explicitly and reset after
; (facts 3f thread gotcha).
RegHotkey(type, keyText, scope, action, enabled, icp := "") {
    ; The trigger may be a hotkey, "hs:..." (hotstring) or "px:..."
    ; (pixel watch) - the last two skip the hotkey grammar.
    key := ""
    trimmed := Trim(keyText)
    if (SubStr(trimmed, 1, 3) = "hs:" || SubStr(trimmed, 1, 3) = "px:")
        key := trimmed
    else {
        key := NormalizeKey(keyText)
        if (key = "")
            return ""
    }
    id := type "|" key "|" scope
    profile := ActiveProfileMap()
    if !profile.Has(id)
        profile[id] := Map()
    b := profile[id]
    b["Type"] := type
    b["Key"] := key
    b["Scope"] := scope
    b["Action"] := action
    b["Enabled"] := enabled ? true : false
    b["Icp"] := icp
    App.Seq++
    b["Seq"] := App.Seq
    if (SubStr(key, 1, 3) = "hs:") {
        if (enabled)
            RegisterHotstringBinding(id, key, scope)
        return id
    }
    if (SubStr(key, 1, 3) = "px:") {
        RebuildPixelWatchers()   ; picks the new watcher up
        return id
    }
    EnsureVariant(key, scope)
    ReconcileVariant(key, scope)
    return id
}

; Register one hotstring binding. The callback is per-binding, so a
; later binding for the same text replaces the earlier one - the
; same "later wins" rule as hotkey variants.
; ? under Linux the trigger only fires when the keysharp input hook
;   is active AND an ending character is typed
; ? the typed trigger is NOT auto-erased (callback hotstrings never
;   backspace) - see the round-113 report, auto-erase is the follow-up
RegisterHotstringBinding(id, key, scope) {
    text := SubStr(key, 4)
    fn := HsDispatch.Bind(id)
    App.Hotstrings[id] := fn
    if (scope != "")
        HotIfWinActive(scope)
    else
        HotIf()
    try Hotstring(text, fn)
    catch as ErrS {
        LogError("register hotstring '" text "': " ErrS.Message)
        SetStatus("Hotstring registration failed - see error log")
        App.Hotstrings.Delete(id)
    }
    HotIf()
}

; Hotstring/pixel-trigger dispatch: run the binding's action by type.
HsDispatch(id, *) {
    b := GetBinding(id)
    if !IsObject(b) || !b["Enabled"]
        return
    if (b["Type"] = "cmd")
        BindCmd(id)
    else
        BindKey(id)
}

; Create the variant + dispatcher exactly once per Key+Scope.
EnsureVariant(key, scope) {
    vkey := key "|" scope
    if App.ActiveHotkeys.Has(vkey)
        return
    fn := BindingDispatch.Bind(key, scope)
    App.ActiveHotkeys[vkey] := fn
    ; * the interception type comes from the effective binding
    icp := EffectiveBindingIcp(key, scope)
    App.VariantIcp[vkey] := icp
    ; ! the HotIf criterion is set explicitly and reset after: a
    ;   leaked criterion would register the NEXT variant under the
    ;   wrong window rule (facts 3f thread gotcha) - same pattern at
    ;   every other Hotkey()/Hotstring() registration site
    if (scope != "")
        HotIfWinActive(scope)
    else
        HotIf()
    try Hotkey(HkVariantName(key, icp), fn, "On")
    catch as Err {
        LogError("register hotkey " key ": " Err.Message)
        SetStatus("Hotkey registration failed for " key " - see error log")
    }
    HotIf()
    EnsureUpVariant(key, scope, icp)
}

; Variant On/Off follows whether ANY enabled binding exists for the
; Key+Scope. The dispatcher itself re-checks at fire time, so a
; missed transition degrades to a no-op instead of a wrong fire.
; Blank action keeps the dispatcher callback untouched (facts 3e).
ReconcileVariant(key, scope) {
    vkey := key "|" scope
    if !App.ActiveHotkeys.Has(vkey)
        return
    anyEnabled := false
    for , b in ActiveProfileMap() {
        if (b["Key"] = key && b["Scope"] = scope && b["Enabled"]) {
            anyEnabled := true
            break
        }
    }
    effIcp := EffectiveBindingIcp(key, scope)
    curIcp := App.VariantIcp.Has(vkey) ? App.VariantIcp[vkey] : ""
    if (scope != "")
        HotIfWinActive(scope)
    else
        HotIf()
    if (curIcp != effIcp) {
        ; * the interception type follows the effective binding - a
        ;   change is the ONE case that re-registers the variant name
        if (curIcp != "") {
            try Hotkey(HkVariantName(key, curIcp), , "Off")
            catch as ErrO {
                LogError("retire variant " key " (" curIcp "): " ErrO.Message)
            }
        }
        try Hotkey(HkVariantName(key, effIcp), App.ActiveHotkeys[vkey], anyEnabled ? "On" : "Off")
        catch as Err {
            LogError("re-register variant " key ": " Err.Message)
        }
        App.VariantIcp[vkey] := effIcp
    } else {
        try Hotkey(HkVariantName(key, curIcp), , anyEnabled ? "On" : "Off")
        catch as Err {
            LogError((anyEnabled ? "enable" : "disable") " hotkey " key ": " Err.Message)
        }
    }
    HotIf()
    EnsureUpVariant(key, scope, effIcp)
}

; The dispatcher: resolve the effective binding and invoke its
; worker. Called by the hotkey variant on every trigger.
BindingDispatch(key, scope, *) {
    id := EffectiveBindingId(key, scope)
    if (id = "")
        return
    b := GetBinding(id)
    if !IsObject(b)
        return
    if (b["Type"] = "cmd")
        BindCmd(id)
    else
        BindKey(id)
}

; * Highest-Seq enabled binding for a Key+Scope ("later wins") -
;   resolved at FIRE time, so add/delete/toggle never needs to
;   re-register the variant.
EffectiveBindingId(key, scope) {
    best := "", bestSeq := -1
    for id, b in ActiveProfileMap() {
        if (b["Key"] = key && b["Scope"] = scope && b["Enabled"] && b["Seq"] > bestSeq) {
            best := id
            bestSeq := b["Seq"]
        }
    }
    return best
}

; Interception type of a binding ("" for legacy maps without the field).
BindingIcp(b) {
    return (IsObject(b) && b.Has("Icp")) ? b["Icp"] : ""
}

; Effective interception type = the effective ("later wins") binding's.
EffectiveBindingIcp(key, scope) {
    id := EffectiveBindingId(key, scope)
    if (id = "")
        return ""
    return BindingIcp(GetBinding(id))
}

; Turn off every registered variant of the active profile.
; ! Keys are snapshotted before iterating: deleting from a Map
;   while enumerating it skips entries (BUG-05). TargetError is
;   expected and logged only (facts 3b). Exception-safe by design.
UnregisterAllHotkeys() {
    vkeys := []
    for vkey, fn in App.ActiveHotkeys
        vkeys.Push(vkey)
    for , vkey in vkeys {
        parts := StrSplit(vkey, "|", , 2)
        key := parts[1]
        scope := parts.Length > 1 ? parts[2] : ""
        if (scope != "")
            HotIfWinActive(scope)
        else
            HotIf()
        try Hotkey(HkVariantName(key, App.VariantIcp.Has(vkey) ? App.VariantIcp[vkey] : ""), , "Off")
        catch TargetError {
            LogError("unregister: no variant for " key)
        }
        catch as Err {
            LogError("unregister " key ": " Err.Message)
        }
        HotIf()
    }
    App.ActiveHotkeys.Clear()
    ; "key up" variants (release-trigger macros)
    ukeys := []
    for vkey, fn in App.UpHotkeys
        ukeys.Push(vkey)
    for , vkey in ukeys {
        parts := StrSplit(vkey, "|", , 2)
        key := parts[1]
        scope := parts.Length > 1 ? parts[2] : ""
        if (scope != "")
            HotIfWinActive(scope)
        else
            HotIf()
        try Hotkey(HkVariantName(key, App.VariantIcp.Has(vkey) ? App.VariantIcp[vkey] : "") " up", , "Off")
        catch TargetError {
        }
        catch as Err {
            LogError("unregister up " key ": " Err.Message)
        }
        HotIf()
    }
    App.UpHotkeys.Clear()
    App.VariantIcp.Clear()
    ; hotstring triggers
    hids := []
    for id, fn in App.Hotstrings
        hids.Push(id)
    for , id in hids {
        b := GetBinding(id)
        if !IsObject(b)
            continue
        if (b["Scope"] != "")
            HotIfWinActive(b["Scope"])
        else
            HotIf()
        try Hotstring(SubStr(b["Key"], 4), , "Off")
        catch as ErrH {
            LogError("unregister hotstring: " ErrH.Message)
        }
        HotIf()
    }
    App.Hotstrings.Clear()
}

; Register one variant per unique Key+Scope present in the active
; profile; On/Off reconciled from the bindings afterwards.
RegisterAllHotkeys() {
    if (App.Suspended)
        return   ; * suspended: triggers stay down; UnsuspendTriggers() re-registers
    App.ActiveHotkeys.Clear()
    App.Hotstrings.Clear()
    for id, b in ActiveProfileMap() {
        if (SubStr(b["Key"], 1, 3) = "hs:") {
            if (b["Enabled"])
                RegisterHotstringBinding(id, b["Key"], b["Scope"])
        } else if (SubStr(b["Key"], 1, 3) != "px:") {
            EnsureVariant(b["Key"], b["Scope"])
        }
    }
    for , b in ActiveProfileMap() {
        if (SubStr(b["Key"], 1, 3) != "hs:" && SubStr(b["Key"], 1, 3) != "px:")
            ReconcileVariant(b["Key"], b["Scope"])
    }
}

; Flip a binding's Enabled flag and reconcile the variant.
SetBindingEnabled(id, on) {
    b := GetBinding(id)
    if !IsObject(b)
        return
    b["Enabled"] := on ? true : false
    if (SubStr(b["Key"], 1, 3) = "hs:") {
        if (on && !App.Hotstrings.Has(id))
            RegisterHotstringBinding(id, b["Key"], b["Scope"])
        else if (App.Hotstrings.Has(id)) {
            if (b["Scope"] != "")
                HotIfWinActive(b["Scope"])
            else
                HotIf()
            try Hotstring(SubStr(b["Key"], 4), , on ? "On" : "Off")
            catch as ErrH {
                LogError("toggle hotstring: " ErrH.Message)
            }
            HotIf()
        }
    } else if (SubStr(b["Key"], 1, 3) = "px:") {
        RebuildPixelWatchers()   ; watcher list respects Enabled
    } else {
        ReconcileVariant(b["Key"], b["Scope"])
    }
    SetDirty()
}

; Delete a binding; the variant is reconciled - if an enabled
; survivor with the same Key+Scope remains, the dispatcher falls
; back to it IMMEDIATELY (no callback swap, no portal round-trip).
RemoveBinding(id) {
    profile := ActiveProfileMap()
    if !profile.Has(id)
        return
    b := profile[id]
    profile.Delete(id)
    if (SubStr(b["Key"], 1, 3) = "hs:") {
        if (b["Scope"] != "")
            HotIfWinActive(b["Scope"])
        else
            HotIf()
        try Hotstring(SubStr(b["Key"], 4), , "Off")
        catch as ErrH {
            LogError("unregister hotstring: " ErrH.Message)
        }
        HotIf()
        if App.Hotstrings.Has(id)
            App.Hotstrings.Delete(id)
    } else if (SubStr(b["Key"], 1, 3) = "px:") {
        RebuildPixelWatchers()
    }
    ReconcileVariant(b["Key"], b["Scope"])
}

; Translate a key-binding action into its Send string (design
; section 3 output grammar; fixes the "!Tab 2" defect):
; 1. repeat form  "mods KEY count"  ->  "mods{KEY count}"
; 2. single-key   "modsKEY"         ->  "mods{KEY}"
; 3. anything else is a macro string, sent as-is.
; Braces around a repeat-form base key are stripped first so both
; "Tab 2" and "{Tab} 2" produce "{Tab 2}". Modifiers always stay
; inside the SAME Send string (facts R3).
BuildKeyOutput(action) {
    if RegExMatch(action, "^([\^!+#]*)(\{[^}]+\}|[A-Za-z0-9_]+)[ ]+(\d+)$", &m) {
        base := RegExReplace(m[2], "^\{|\}$", "")
        return m[1] "{" base " " m[3] "}"
    }
    if RegExMatch(action, "^([\^!+#]*)(\w+)$", &m)
        return m[1] "{" m[2] "}"
    return action
}

; Command dispatch (feature 7). "&" runs via the shell selected in
; Settings from the detected list (bash commands are syntax-checked
; first - see RunViaShell); ">" sends; "@" runs a temporary AHK
; script (guarded by A_IsCompiled per facts 19a); doubled prefixes
; escape; anything else runs hidden via cmd.exe (previous behavior).
BindCmd(id, *) {
    b := GetBinding(id)
    if !IsObject(b)
        return
    payload := b["Action"]
    if (payload = "")
        return
    try {
        if (SubStr(payload, 1, 2) = "&&" || SubStr(payload, 1, 2) = ">>" || SubStr(payload, 1, 2) = "@@") {
            ; doubled prefix: strip one char, fall through to the default handler
            Run(A_ComSpec " /c " SubStr(payload, 2), , "Hide")
            return
        }
        p := SubStr(payload, 1, 1)
        rest := SubStr(payload, 2)
        if (p = "&") {
            hidden := App.Settings["ShellHidden"] ? "Hide" : ""
            RunViaShell(GetShellById(App.Settings["ShellCmd"]), rest, hidden)
            return
        }
        if (p = ">") {
            Send(rest)
            return
        }
        if (p = "@") {
            if (A_IsCompiled) {
                LogError("@ prefix unavailable in a compiled build")
                SetStatus("@ expressions are not available in compiled builds")
                return
            }
            ; per-process filename: no cross-process swap race, and the
            ; startup sweep below clears leftovers (security review F4).
            ; A_ScriptHwnd is unique per process and valid on every
            ; platform (unlike a PID variable, which v2.0 lacks).
            file := JoinPath(A_Temp, "ReBindX_expr_" A_ScriptHwnd ".ahk")
            if FileExist(file)
                FileDelete(file)
            FileAppend(rest "`n", file, "UTF-8-RAW")
            Run('"' A_AhkPath '" "' file '"', , "Hide")
            return
        }
        Run(A_ComSpec " /c " payload, , "Hide")
    } catch as Err {
        LogError("command failed (" payload "): " Err.Message)
        SetStatus("Command failed - see error log")
    }
}

; Key-output dispatch with repeat-while-held support applied to
; all three grammar forms. The "$" prefix on every registered
; hotkey prevents our own Send from re-triggering (facts 3d).
; Resolve a key-binding action to its effective Send input.
; "macro:Name" references the global macro library (Macros tab):
; editing a macro updates every binding that references it.
; Returns "" when the reference is broken (reported, not fired).
ResolveKeyAction(action) {
    if (SubStr(action, 1, 6) = "macro:") {
        mname := SubStr(action, 7)
        if !App.MacroLib.Has(mname) {
            LogError("macro not found: '" mname "'")
            SetStatus("Macro '" mname "' not found - see error log")
            return ""
        }
        return App.MacroLib[mname]
    }
    return action
}

BindKey(id, *) {
    b := GetBinding(id)
    if !IsObject(b)
        return
    action := ResolveKeyAction(b["Action"])
    if (action = "")
        return
    if IsStructuredMacro(action) {
        ; structured (builder) macro: executor handles waits, loops,
        ; shell runs and mouse moves; trg:release fires via BindKeyUp
        hdr := ParseMacroHeader(action)
        if (hdr.Mode = "release" || hdr.Mode = "pixel")
            return   ; release fires via BindKeyUp; pixel via the watcher
        RunMacroSequence(action)
        if (hdr.Mode = "repeat") {
            if (hdr.Buf != 0)
                Sleep(hdr.Buf)
            baseBoundKey := RegExReplace(b["Key"], "[\^!+#*~\$]")
            while (baseBoundKey != "" && GetKeyState(baseBoundKey, "P")) {
                RunMacroSequence(action)
                if (hdr.Del != 0)
                    Sleep(hdr.Del)
            }
        }
        return
    }
    sendStr := BuildKeyOutput(action)
    try Send(sendStr)
    catch as Err {
        LogError("send failed (" action "): " Err.Message)
        return
    }
    if (App.Settings["DoRepeatOutputs"]) {
        try {
            if (App.Settings["RepeatBuffer"] != 0)
                Sleep(App.Settings["RepeatBuffer"])
            baseBoundKey := RegExReplace(b["Key"], "[\^!+#*~\$]")
            if (baseBoundKey != "") {
                while GetKeyState(baseBoundKey, "P") {
                    Send(sendStr)
                    if (App.Settings["RepeatDelay"] != 0)
                        Sleep(App.Settings["RepeatDelay"])
                }
            }
        } catch as Err {
            LogError("repeat failed (" action "): " Err.Message)
        }
    }
}

; F1 global toggle + Del / Ctrl+Z scoped to the main window.
; Registered ONCE at startup, never inside UnregisterAllHotkeys
; (that function only manages App.ActiveHotkeys binding callbacks).
RegisterAppHotkeys() {
    HotIf()
    try Hotkey(HkName("F1"), ToggleGui)
    catch as Err {
        LogError("F1 hotkey: " Err.Message)
    }
    HotIfWinActive(App.Title)
    try Hotkey(HkName("Del"), LvDelete)
    catch as Err {
        LogError("Del hotkey: " Err.Message)
    }
    try Hotkey(HkName("^z"), LvUndo)
    catch as Err {
        LogError("^z hotkey: " Err.Message)
    }
    HotIf()
}

; =============================================================
; 8. GUI build
; =============================================================

; === Tooltip helper (v2.0-safe; adapted from GuiCtrlTips.ahk
;     2025-03-24, facts section 2). One tooltip control per Gui.
;     Call Tips.Init(GuiObj) once, then AddTip(ctrl, text). ===
class Tips {
    static Hwnd := 0, GuiHwnd := 0, Known := Map()
    static Init(GuiObj) {
        try {
            Tips.GuiHwnd := GuiObj.Hwnd
            Tips.Hwnd := DllCall("CreateWindowEx", "UInt", 0, "Str", "tooltips_class32", "Ptr", 0
                , "UInt", 0x80000003, "Int", 0x80000000, "Int", 0x80000000, "Int", 0x80000000
                , "Int", 0x80000000, "Ptr", Tips.GuiHwnd, "Ptr", 0, "Ptr", 0, "Ptr", 0, "UPtr")
            if Tips.Hwnd
                SendMessage(0x0418, 0, A_ScreenWidth, Tips.Hwnd)   ; TTM_SETMAXTIPWIDTH
        } catch as Err {
            Tips.Hwnd := 0
            LogError("tooltip init: " Err.Message)
        }
    }
    static AddTip(Ctrl, Text) {
        if !Tips.Hwnd || !(Ctrl is Gui.Control)
            return
        try {
            TI := Buffer(24 + A_PtrSize * 6, 0)
            NumPut("UInt", 24 + A_PtrSize * 6, TI)                                        ; cbSize
            NumPut("UInt", 0x11, "UPtr", Tips.GuiHwnd, "UPtr", Ctrl.Hwnd, TI, 4)         ; uFlags|hwnd|uId
            if !Tips.Known.Has(Ctrl.Hwnd) {
                SendMessage(0x0432, 0, TI.Ptr, Tips.Hwnd)                                 ; TTM_ADDTOOLW
                Tips.Known[Ctrl.Hwnd] := true
            }
            NumPut("UPtr", StrPtr(Text), TI, 24 + A_PtrSize * 3)                          ; lpszText
            SendMessage(0x0439, 0, TI.Ptr, Tips.Hwnd)                                      ; TTM_UPDATETIPTEXTW
        } catch as Err {
            LogError("tooltip add: " Err.Message)
        }
    }
}

; Button/CheckBox face color for theme contrast (a11y P1-1): the GUI
; font color (Text) is white in the dark theme, so Keysharp's toolkit
; buttons would paint white captions on their light native faces
; (~1.14:1). Appending this option sets the control background to
; Theme["Control"]; AutoHotkey ignores background colors on native
; buttons, so the .ahk is visually unchanged there.
BtnBg() {
    return " +Background" App.Theme["Control"]
}

; Shared themed SetFont wrappers so GUI-building code is identical
; across both files. The .ks routes both names through its cached
; UiFont logic; on AutoHotkey both are SetFont + Segoe UI (two names
; are kept so call sites mirror the .ks one-to-one).
ThemedFont(g, opts) {
    SetUIThemeFont(g, opts)
}

SetUIThemeFont(g, opts) {
    g.SetFont(opts, "Segoe UI")
}

; Row icons (UI 3, facts section 17): ship our own .ico files,
; check every return value, degrade silently when unavailable.
InitRowIcons() {
    il := 0
    try {
        il := IL_Create(2)
        if !il
            return 0
        if !IL_Add(il, JoinPath(A_ScriptDir, "icons", "gear.ico"))
            return 0
        if !IL_Add(il, JoinPath(A_ScriptDir, "icons", "keyboard.ico"))
            return 0
        App.LV_Cmd.SetImageList(il, 1)   ; 1 = small icons (report view)
        App.LV_Key.SetImageList(il, 1)
    } catch as Err {
        LogError("icons: " Err.Message)
        il := 0
    }
    App.Icons := il
    return il
}

BuildMainGui() {
    ; ---- layout constants (D-06: everything flows from these) ----
    ; Sizing rules for cross-toolkit robustness (AutoHotkey/Win32 vs
    ; Keysharp/WinForms vs Eto/GTK): every control gets an explicit
    ; w/h, row pitch must clear the tallest plausible control of the
    ; row's type (GTK combos/entries render ~30-32px even when h22
    ; is requested), and the tab content area must clear the tallest
    ; tab-header band (GTK notebook ~36-40px vs WinForms ~28px).
    marginX := 14
    marginY := 12
    sideW := 132
    btnW := 130
    btnH := 30
    contentX := marginX + sideW + 14      ; main area left edge (160)
    contentY := 10
    contentW := 726
    tabH := 820                           ; sized by the Usage Guide (see below)
    pad := 12                             ; in-tab padding
    tabX := contentX + pad                ; in-tab content x (172)
    tabY0 := contentY + 46                ; first in-tab row y (56; tab-strip clearance)
    lvW := contentW - pad * 2             ; 702
    lvY := tabY0 + 36                     ; filter row + gap (92; GTK entry min-height)
    lvH := tabH - (lvY - contentY) - pad  ; bottom-aligned in-tab (726)
    lblW := 330
    ctlX := tabX + lblW + 10              ; settings control column (512)
    rowH := 44                            ; settings row pitch (GTK combos ~32px tall)
    ; tabH derivation: the Usage Guide is the tallest tab - an inner
    ; Tab3 with seven word-wrapped Text pages that fit the fixed page
    ; box (no scrolling; +ScrollBars proved invalid on Keysharp,
    ; round 109). 820 keeps every page readable at Win32/Segoe
    ; metrics with headroom for Eto/GTK wide-font rendering; it also
    ; sets the window's lower size bound.
    ; Drift guard: Show() call sites outside this function use
    ; Consts.WinW/WinH; fail loudly (log) if the two ever diverge.
    if (contentX + contentW + marginX != Consts.WinW)
        LogError("layout drift: WinW " (contentX + contentW + marginX) " != Consts.WinW " Consts.WinW)
    if (contentY + tabH + 6 + 24 + marginY != Consts.WinH)
        LogError("layout drift: WinH " (contentY + tabH + 6 + 24 + marginY) " != Consts.WinH " Consts.WinH)

    g := Gui("Resize MinSize800x600 +OwnDialogs", App.Title)
    App.MainGui := g
    g.MarginX := marginX
    g.MarginY := marginY
    App.Ui := Map()
    SetUIThemeFont(g, "s10 c" App.Theme["Text"])

    ; ---- sidebar (flow-stacked with y+m) ----
    SetUIThemeFont(g, "s12 bold c" App.Theme["Text"])
    g.Add("Text", "x" marginX " y" marginY " w" sideW " h26 +BackgroundTrans Section", App.Name)
    SetUIThemeFont(g, "s10 norm c" App.Theme["Text"])

    App.Ui["AddBtn"] := g.Add("Button", "xs y+m w" btnW " h" btnH BtnBg(), "+ Add Binding")
    App.Ui["AddBtn"].OnEvent("Click", AddBindingClicked)
    App.Ui["DelBtn"] := g.Add("Button", "xs y+m w" btnW " h" btnH BtnBg(), "Delete")
    App.Ui["DelBtn"].OnEvent("Click", DeleteSelectedBindings)
    App.Ui["TglBtn"] := g.Add("Button", "xs y+m w" btnW " h" btnH BtnBg(), "Toggle On/Off")
    App.Ui["TglBtn"].OnEvent("Click", ToggleSelectedBindings)
    App.Ui["ClrBtn"] := g.Add("Button", "xs y+m w" btnW " h" btnH BtnBg(), "Clear Bindings")
    App.Ui["ClrBtn"].OnEvent("Click", ClearBindings)
    App.Ui["UndoBtn"] := g.Add("Button", "xs y+m w" btnW " h" btnH BtnBg(), "Undo")
    App.Ui["UndoBtn"].OnEvent("Click", Undo)
    App.Ui["SuspendBtn"] := g.Add("Button", "xs y+m w" btnW " h" btnH BtnBg()
        , App.Suspended ? "Unsuspend" : "Suspend")
    App.Ui["SuspendBtn"].OnEvent("Click", ToggleSuspendBtn)
    App.Ui["SaveBtn"] := g.Add("Button", "xs y+m w" btnW " h" btnH BtnBg(), "Save")
    App.Ui["SaveBtn"].OnEvent("Click", SaveBindings)
    App.Ui["SaveToBtn"] := g.Add("Button", "xs y+m w" btnW " h" btnH BtnBg(), "Save to...")
    App.Ui["SaveToBtn"].OnEvent("Click", SaveSelectedTo)
    App.Ui["LoadBtn"] := g.Add("Button", "xs y+m w" btnW " h" btnH BtnBg(), "Load")
    App.Ui["LoadBtn"].OnEvent("Click", LoadBindings)
    App.Ui["ImportBtn"] := g.Add("Button", "xs y+m w" btnW " h" btnH BtnBg(), "Import")
    App.Ui["ImportBtn"].OnEvent("Click", ImportConfig)
    App.Ui["ExportBtn"] := g.Add("Button", "xs y+m w" btnW " h" btnH BtnBg(), "Export")
    App.Ui["ExportBtn"].OnEvent("Click", ExportConfig)

    ; Exit pinned at the bottom via layout constants
    exitY := contentY + tabH + 6 - btnH - 10   ; 10px above the status strip
    App.Ui["ExitBtn"] := g.Add("Button", "x" marginX " y" exitY " w" btnW " h" btnH BtnBg(), "Exit")
    App.Ui["ExitBtn"].OnEvent("Click", DoExit)

    ; ---- tabs ----
    tabs := g.Add("Tab3", "x" contentX " y" contentY " w" contentW " h" tabH " AltSubmit c" App.Theme["Text"]
        , ["Command Mapper", "Key Remapper", "Hotstrings", "Macros", "Profiles", "Settings", "Usage Guide"])
    App.Ui["Tab"] := tabs
    tabs.OnEvent("Change", TabCh)

    ; -- Tab 1: Command Mapper --
    ; Keysharp: in-tab content uses xc/yc (container-RELATIVE
    ; positioning) with 10px margins, so GTK's own tab-content inset
    ; is not ADDED to our offsets - the cause of the oversized left
    ; gap (user report). rebindx.ahk keeps window-absolute x/y.
    tabs.UseTab(1)
    inW := contentW - 20                   ; in-tab content width
    g.Add("Text", "x(contentX+10) y(contentY+36+46) w44 h22 +BackgroundTrans", "Filter:")
    App.Ui["FilterCmd"] := g.Add("Edit", "x(contentX+60) yp w240 h22 c" App.Theme["Text"] " +Background" App.Theme["Control"], "")
    App.Ui["FilterCmd"].OnEvent("Change", OnFilterCmdChange)
    App.LV_Cmd := g.Add("ListView", "x(contentX+10) y(contentY+36+82) w" inW " h" lvH " NoSortHdr +Background" App.Theme["Background"]
        , ["Key", "Command", "Status", "Window"])
    App.LV_Cmd.ModifyCol(1, 150)
    App.LV_Cmd.ModifyCol(2, lvW - 150 - 64 - 150 - 26)
    App.LV_Cmd.ModifyCol(3, 64)
    App.LV_Cmd.ModifyCol(4, 150)
    App.LV_Cmd.OnEvent("DoubleClick", LvDoubleClick)
    App.LV_Cmd.OnEvent("ContextMenu", LvContextMenu)
    App.Ui["EmptyCmd"] := g.Add("Text", "x" (contentX + 10 + (inW - 220) // 2) " y" (contentY + 36 + 82 + (lvH // 2) - 11) " w220 h22 c" App.Theme["Hint"] " +BackgroundTrans Center"
        , "No bindings yet")
    App.Ui["EmptyCmd"].Visible := false

    ; -- Tab 2: Key Remapper --
    tabs.UseTab(2)
    g.Add("Text", "x(contentX+10) y(contentY+36+46) w44 h22 +BackgroundTrans", "Filter:")
    App.Ui["FilterKey"] := g.Add("Edit", "x(contentX+60) yp w240 h22 c" App.Theme["Text"] " +Background" App.Theme["Control"], "")
    App.Ui["FilterKey"].OnEvent("Change", OnFilterKeyChange)
    App.LV_Key := g.Add("ListView", "x(contentX+10) y(contentY+36+82) w" inW " h" lvH " NoSortHdr +Background" App.Theme["Background"]
        , ["Key", "Output", "Status", "Window"])
    App.LV_Key.ModifyCol(1, 150)
    App.LV_Key.ModifyCol(2, lvW - 150 - 64 - 150 - 26)
    App.LV_Key.ModifyCol(3, 64)
    App.LV_Key.ModifyCol(4, 150)
    App.LV_Key.OnEvent("DoubleClick", LvDoubleClick)
    App.LV_Key.OnEvent("ContextMenu", LvContextMenu)
    App.Ui["EmptyKey"] := g.Add("Text", "x" (contentX + 10 + (inW - 220) // 2) " y" (contentY + 36 + 82 + (lvH // 2) - 11) " w220 h22 c" App.Theme["Hint"] " +BackgroundTrans Center"
        , "No bindings yet")
    App.Ui["EmptyKey"].Visible := false

    ; -- Tab 5: Profiles --
    tabs.UseTab(5)
    ; row 1: active profile identity
    g.Add("Text", "x(contentX+14) y(contentY+36+16) w110 h24 +BackgroundTrans", "Active profile:")
    App.Ui["ProfileDDL"] := g.Add("DDL", "x(contentX+110) y(contentY+36+8) w170 vProfDDL", [])
    App.Ui["ProfileSwitchBtn"] := g.Add("Button", "x(contentX+315) y(contentY+36+8) w100 h28" BtnBg(), "Switch")
    App.Ui["ProfileSwitchBtn"].OnEvent("Click", OnProfileSwitchBtn)
    ; row 2: creation and deletion
    App.Ui["PNewBtn"] := g.Add("Button", "x(contentX+10) y(contentY+36+64) w120 h28" BtnBg(), "New profile...")
    App.Ui["PNewBtn"].OnEvent("Click", ProfileNewDialog)
    App.Ui["PDeleteBtn"] := g.Add("Button", "x(contentX+140) y(contentY+36+64) w120 h28" BtnBg(), "Delete profile")
    App.Ui["PDeleteBtn"].OnEvent("Click", ProfileDeleteOrClear)
    ; row 3: save / identity ops
    App.Ui["PSaveBtn"] := g.Add("Button", "x(contentX+10) y(contentY+36+120) w120 h28" BtnBg(), "Save")
    App.Ui["PSaveBtn"].OnEvent("Click", ProfileSave)
    App.Ui["PSaveAsBtn"] := g.Add("Button", "x(contentX+140) y(contentY+36+120) w120 h28" BtnBg(), "Save As...")
    App.Ui["PSaveAsBtn"].OnEvent("Click", ProfileSaveAs)
    ; row 4: file / profile ops
    App.Ui["PExportBtn"] := g.Add("Button", "x(contentX+10) y(contentY+36+168) w120 h28" BtnBg(), "Export...")
    App.Ui["PExportBtn"].OnEvent("Click", ProfileExport)
    App.Ui["PImportBtn"] := g.Add("Button", "x(contentX+140) y(contentY+36+168) w120 h28" BtnBg(), "Import...")
    App.Ui["PImportBtn"].OnEvent("Click", ProfileImport)
    ; row 5: rename target field (Rename uses this name)
    g.Add("Text", "x(contentX+10) y(contentY+36+220) w460 h20 +BackgroundTrans", "Rename target: type the new name for the ACTIVE profile:")
    App.Ui["ProfNameEdit"] := g.Add("Edit", "x(contentX+10) y(contentY+36+260) w200 h22 vProfName c" App.Theme["Text"] " +Background" App.Theme["Control"], App.ActiveProfile)
    App.Ui["PRenameBtn"] := g.Add("Button", "x(contentX+220) y(contentY+36+260) w100 h28" BtnBg(), "Rename")
    App.Ui["PRenameBtn"].OnEvent("Click", ProfileRename)

    ; -- Tab 6: Settings --
    tabs.UseTab(6)
    row1 := 10
    g.Add("Text", "x(contentX+10) y" (contentY+36+row1) " w" lblW " h24 +BackgroundTrans", "Repeat outputs while held (remaps only)")
    App.Ui["RepeatBtn"] := g.Add("Button", "x(contentX+350) y" (contentY+36+row1-2) " w100 h28" BtnBg()
        , App.Settings["DoRepeatOutputs"] ? "Disable" : "Enable")   ; caption via Add text, later via .Text only (BUG-02)
    App.Ui["RepeatBtn"].OnEvent("Click", ToggleRepeat)

    row2 := row1 + rowH
    g.Add("Text", "x(contentX+10) y" (contentY+36+row2) " w" lblW " h24 +BackgroundTrans", "Repeat buffer (ms)")
    ; Keysharp: UpDowns are standalone NumericUpDown controls with no
    ; buddy Edit, so one control replaces the old Edit+UpDown pair.
    App.Ui["RepeatBufUD"] := g.Add("UpDown", "x(contentX+350) y" (contentY+36+row2) " w100 h24 Range0-1000", App.Settings["RepeatBuffer"])
    App.Ui["RepeatBufUD"].OnEvent("Change", OnRepeatBufChange)

    row3 := row2 + rowH
    g.Add("Text", "x(contentX+10) y" (contentY+36+row3) " w" lblW " h24 +BackgroundTrans", "Repeat delay (ms)")
    App.Ui["RepeatDelayUD"] := g.Add("UpDown", "x(contentX+350) y" (contentY+36+row3) " w100 h24 Range0-500", App.Settings["RepeatDelay"])
    App.Ui["RepeatDelayUD"].OnEvent("Change", OnRepeatDelayChange)

    row4 := row3 + rowH
    g.Add("Text", "x(contentX+10) y" (contentY+36+row4) " w" lblW " h24 +BackgroundTrans", "Run at startup (requires admin)")
    App.Ui["StartupBtn"] := g.Add("Button", "x(contentX+350) y" (contentY+36+row4-2) " w100 h28" BtnBg()
        , App.Settings["DoStartup"] ? "Disable" : "Enable")
    App.Ui["StartupBtn"].OnEvent("Click", ToggleStartup)

    row5 := row4 + rowH
    g.Add("Text", "x(contentX+10) y" (contentY+36+row5) " w" lblW " h24 +BackgroundTrans", "Shell for & commands")
    shellNames := []
    shellIdx := 1
    for i, sh in App.Shells {
        shellNames.Push(sh["Name"])
        if (sh["Id"] = App.Settings["ShellCmd"])
            shellIdx := i
    }
    if (shellNames.Length = 0)
        shellNames.Push("cmd")   ; defensive: DetectShells guarantees one
    App.Ui["ShellDDL"] := g.Add("DDL", "x(contentX+350) y" (contentY+36+row5-2) " w150 Choose" shellIdx, shellNames)
    App.Ui["ShellDDL"].OnEvent("Change", OnShellDDLChange)

    row6 := row5 + rowH
    g.Add("Text", "x(contentX+10) y" (contentY+36+row6) " w" lblW " h24 +BackgroundTrans", "Console window")
    App.Ui["ShellVisBtn"] := g.Add("Button", "x(contentX+350) y" (contentY+36+row6-2) " w100 h28" BtnBg()
        , App.Settings["ShellHidden"] ? "Hidden" : "Visible")
    App.Ui["ShellVisBtn"].OnEvent("Click", ToggleShellVis)

    row7 := row6 + rowH
    g.Add("Text", "x(contentX+10) y" (contentY+36+row7) " w" lblW " h24 +BackgroundTrans", "Start as suspended (unsuspend manually to arm triggers)")
    App.Ui["StartSuspBtn"] := g.Add("Button", "x(contentX+350) y" (contentY+36+row7-2) " w100 h28" BtnBg()
        , App.Settings["StartSuspended"] ? "Disable" : "Enable")
    App.Ui["StartSuspBtn"].OnEvent("Click", ToggleStartSuspended)

    row8 := row7 + rowH
    g.Add("Text", "x(contentX+10) y" (contentY+36+row8) " w" lblW " h24 +BackgroundTrans", "Autosave (save after changes, silently)")
    App.Ui["AutosaveBtn"] := g.Add("Button", "x(contentX+350) y" (contentY+36+row8-2) " w100 h28" BtnBg()
        , App.Settings["Autosave"] ? "Disable" : "Enable")
    App.Ui["AutosaveBtn"].OnEvent("Click", ToggleAutosave)


    ; -- Tab 7: Usage Guide - split into INNER sub-tabs (user request:
    ;    the single scrolling stack overflowed the window) --
    tabs.UseTab(7)
    SetUIThemeFont(g, "s8 c" App.Theme["Text"])
    guide := g.Add("Tab3", "x(contentX+4) y(contentY+36+18) w" (contentW - 8) " h" (tabH - 36) " c" App.Theme["Text"]
        , ["Getting Started", "Keys & Remaps", "Commands & Shells", "Macros & Builder", "Hotstrings & Pixel", "Profiles", "Window & Files"])
    App.Ui["GuideTabs"] := guide
    App.Ui["GuideTxts"] := []
    gw := contentW - 28
    ; one word-wrapped Text per sub-tab; the per-page content fits
    ; the fixed page box
    guide.UseTab(1)
    App.Ui["GuideTxts"].Push(g.Add("Text", "x(contentX+10) y(contentY+36+10) w" gw " h" (tabH - 76) " +BackgroundTrans -Wrap", "GETTING STARTED`n- ReBindX maps keys to commands and other keys, manages macros, hotstrings, pixel triggers and profiles.`n- Everything lives in keybinds.cfg next to this script`n- Use Save to write it, Load to re-read it, and profile Save/Import for variants.`n`nQUICK START`n- Press + Add Binding, pick a trigger type, enter the action, Save`n- F1 shows/hides this window at any time (you can even rebind F1 itself)`n- Everything is reachable from the tray menu too`n`nTHE FOUR CONCEPTS`n- BINDINGS: a trigger (hotkey, hotstring or pixel) fires an action`n- MACROS: reusable Send sequences, built action-by-action in the Builder`n- PROFILES: independent sets of bindings, macros and settings`n- TRIGGERS: what makes something fire - key press, typed text, or a pixel turning a color`n`nWHERE THINGS LIVE`n- Command Mapper tab: hotkey/hotstring/pixel -> command bindings`n- Key Remapper tab: hotkey -> key/macro output bindings`n- Hotstrings tab: typed-text triggers and their replacements`n- Macros tab: the macro library (New..., Edit..., Builder...)`n- Profiles tab: save/switch/clone/import/export profiles"))
    guide.UseTab(2)
    App.Ui["GuideTxts"].Push(g.Add("Text", "x(contentX+10) y(contentY+36+10) w" gw " h" (tabH - 76) " +BackgroundTrans -Wrap", "KEY SYNTAX`n- AHK symbols: # = Win, ^ = Ctrl, ! = Alt, + = Shift (example: #^G = Win+Ctrl+G)`n- Text syntax also accepted: WIN+CTRL+ALT+G, with or without plus signs`n- Single characters written as-is: A-Z, 0-9`n`nKEY NAMES`n- Multi-character keys use their full names: Escape, Tab, Enter, Space, Backspace, Delete, Insert, Home, End, PgUp, PgDn, arrows, F1-F24`n- Numpad: Numpad0-9, NumpadEnter, NumpadAdd/Sub/Mult/Div/Dot, NumpadIns/Del/Up/Down/Left/Right/Home/End/PgUp/PgDn`n- System: AppsKey, PrintScreen, Pause, ScrollLock, CapsLock`n- Mouse: LButton, RButton, MButton, XButton1, XButton2`n- Media/Internet: Media_Play_Pause, Media_Next/Prev/Stop, Volume_Mute/Up/Down, Browser_Back/Forward/Refresh/Stop/Search/Favorites/Home`n`nREMAP OUTPUTS`n- Single key: G, !F4, ^c`n- Repeat form: !Tab 2 holds Alt and presses Tab twice`n- Macro string: sent as-is, e.g. {Enter}{Enter}abc`n`nWINDOW SCOPES`n- Append [wintitle] to scope a binding to one program: #Z[ahk_exe chrome.exe];start chrome`n- Works for hotkey AND hotstring triggers`n- The binding only fires while that window is active`n`nCONFIG GRAMMAR`n- key;action  - one binding per line`n- *key;action  - the * prefix saves the binding DISABLED`n- A line of 3+ dashes separates command from key-remap sections`n- [Profile:Name] starts a new profile; [Macros] is the legacy global-macro section (read into Default)`n- macro:Name;sequence and set:Key;Value lines store per-profile macros/settings`n- {SEMICOLON} escapes a literal semicolon inside an action"))
    guide.UseTab(3)
    App.Ui["GuideTxts"].Push(g.Add("Text", "x(contentX+10) y(contentY+36+10) w" gw " h" (tabH - 76) " +BackgroundTrans -Wrap", "COMMAND PREFIXES (Command Mapper actions)`n- &command  runs through the shell selected in Settings, hidden or visible per the console setting`n- Bash commands are syntax-checked (bash -n) before running`n- >text  sends text/keys instead of running a program`n- @code  runs AutoHotkey code via a temporary .ahk file (not available in compiled builds)`n- Doubled prefix (&&, >>, @@) passes the character through to the default handler`n- No prefix: hidden cmd.exe (Windows) / selected shell (Keysharp)`n`nSHELLS`n- The Settings tab selects the shell for & commands (cmd.exe or PowerShell on Windows; on Linux/macOS the list is discovered from the system)`n- bash is validated with bash -n before every run - syntax errors are reported and the command is NOT executed`n- rw: runs a command and WAITS for it to finish before the next macro action; run: proceeds immediately`n`nKEY REMAP REPEAT`n- !Tab 2 = press Tab twice with Alt held`n- Repeat-while-held: the Settings tab toggles whether holding the trigger key keeps repeating the output, with buffer/delay values (per-profile)"))
    guide.UseTab(4)
    App.Ui["GuideTxts"].Push(g.Add("Text", "x(contentX+10) y(contentY+36+10) w" gw " h" (tabH - 76) " +BackgroundTrans -Wrap", "MACROS`n- A macro is a reusable Send sequence stored in the macro library (Macros tab)`n- Bindings reference macros by name: a Key Remap output of macro:Name replays it`n- Editing a macro instantly updates every binding that uses it`n`nTHE BUILDER (Builder... button)`n- Build macros one action at a time: Key press (with hold duration), Key down, Key up, Wait (ms), Run command (with wait-until-return), Mouse move (X/Y, relative, hold a key while moving), Sequence (raw Send string)`n- Loop start / Loop end wrap a part of the sequence; loops need unique names`n- Endloop must match the innermost open loop, every loop must be closed before saving`n- Test run executes the current sequence once`n`nTRIGGER MODES (per macro)`n- On key press: fires when the assigned key goes down`n- On key release: fires when the assigned key goes up`n- Repeat while held: repeats with per-macro buffer/delay`n- Pixel watch: fires while the pixel at X,Y turns to / turns from a color; the watcher polls while ReBindX runs`n- Pixel capture may be unavailable on some compositors (watcher disables itself and logs once)`n`nMACRO GRAMMAR (stored per profile)`n- trg:press|release|repeat  trigger mode`n- rbuf:ms / rdel:ms  repeat buffer/delay`n- px:x,y,RRGGBB,to|from  pixel trigger`n- kd:Key / ku:Key / kp:Key[:holdMs]  key actions`n- w:ms  wait`n- run:cmd / rw:cmd  shell (async / wait)`n- mm:x,y,rel|abs[,hold:Key]  mouse move`n- loop:Name:Count ... endloop:Name  repetition`n- sq:string  raw Send sequence`n- A literal | inside a parameter is stored as {PIPE}"))
    guide.UseTab(5)
    App.Ui["GuideTxts"].Push(g.Add("Text", "x(contentX+10) y(contentY+36+10) w" gw " h" (tabH - 76) " +BackgroundTrans -Wrap", "HOTSTRINGS`n- A hotstring fires when you TYPE its trigger text anywhere, then an ending character (space, Enter, etc.)`n- Set the Trigger type to Hotstring in the binding editor and type the trigger text`n- Replacement actions follow the binding grammar: >text sends text/keys, no prefix runs a command, & runs via the selected shell, macro:Name replays a library macro`n- The Hotstrings tab lists every hotstring binding with New/Edit/Delete/Toggle`n- Scope works for hotstrings too: [wintitle] limits where the text triggers`n`nPIXEL TRIGGERS`n- Trigger type Pixel: the binding fires when the screen pixel at X,Y turns to (or turns from) a color RRGGBB`n- Polls continuously while ReBindX runs; fires once per transition and re-arms when the color clears`n- A pixel watcher disables itself (with one log entry) on platforms where pixel capture is unavailable`n`nHOTKEY TRIGGERS`n- The classic form: a hotkey (e.g. #^G) fires the action on key press`n- Multiple bindings may share a hotkey: the LATEST enabled binding wins`n- Per-app scoping via [wintitle]`n- Interception (editor dropdown): ~ passthrough, $ force hook, * wildcard; combinable, stored as a key suffix (B~$)"))
    guide.UseTab(6)
    App.Ui["GuideTxts"].Push(g.Add("Text", "x(contentX+10) y(contentY+36+10) w" gw " h" (tabH - 76) " +BackgroundTrans -Wrap", "PROFILES`n- A profile bundles bindings, macros AND the three repeat settings`n- Active profile: pick from the dropdown and press Switch (or use the tray menu)`n- New profile...: create from current settings, clone an existing profile, or start empty`n- Save: writes the active profile (one-time warning before saving into Default)`n- Save As...: copy the active profile under a new name and switch to it`n- Rename: type a new name for the ACTIVE profile (disabled for Default)`n- Export... / Import...: single-profile config files, merge-on-import`n- Delete / Clear: removes a non-Default profile (Default is cleared instead)`n- Save to... (sidebar): copies the SELECTED bindings/macros/hotstrings into any profile without switching`n`nSTORAGE`n- Profiles live as [Profile:Name] sections in keybinds.cfg`n- The Default profile is the headerless section at the top`n- macro:Name and set:Key lines inside a section carry its macros and settings`n- Undo (Ctrl+Z) covers profile operations"))
    guide.UseTab(7)
    App.Ui["GuideTxts"].Push(g.Add("Text", "x(contentX+10) y(contentY+36+10) w" gw " h" (tabH - 76) " +BackgroundTrans -Wrap", "USING THE WINDOW`n- F1 hides/shows this window (rebindable)`n- Click a row to select; Ctrl+click or Shift+click selects several`n- Double-click a row, or press Enter, to edit; Del deletes the selected rows`n- Right-click a row to toggle/edit/delete that one binding`n- Ctrl+Z undoes the last change (10 levels)`n- The Filter box above each list narrows rows as you type`n- Resize the window freely; the lists follow (the Usage Guide content sets the lower limit)`n`nSETTINGS TAB`n- Repeat outputs/buffer/delay: per-profile remap repeat behavior`n- Run at startup: creates the Startup shortcut (Windows, admin)`n- Shell for & commands + console visibility`n- Start as suspended and Autosave: trigger/persistence defaults`n`nFILES`n- keybinds.cfg: bindings, remaps, macros, profiles (UTF-8)`n- rebindxsettings.ini: settings (UTF-16 on Windows/Win32; do not resave as UTF-8)`n- theme.cfg: optional colors; Auto=1 follows Windows dark/light mode`n- errors: error.log inside the ReBindX folder of the OS application-data directory`n- icons\gear.ico / keyboard.ico: list icons (missing icons degrade silently)"))
    guide.UseTab()
    SetUIThemeFont(g, "s10 c" App.Theme["Text"])

    ; -- Tab 3: Hotstrings (triggers typed as text) --
    tabs.UseTab(3)
    App.Ui["HsNewBtn"] := g.Add("Button", "x(contentX+10) y(contentY+36+46) w110 h28" BtnBg(), "New...")
    App.Ui["HsNewBtn"].OnEvent("Click", HsNew)
    App.Ui["HsEditBtn"] := g.Add("Button", "x(contentX+134) y(contentY+36+46) w110 h28" BtnBg(), "Edit...")
    App.Ui["HsEditBtn"].OnEvent("Click", HsEditSelected)
    App.Ui["HsDelBtn"] := g.Add("Button", "x(contentX+258) y(contentY+36+46) w110 h28" BtnBg(), "Delete")
    App.Ui["HsDelBtn"].OnEvent("Click", HsDeleteSelected)
    App.Ui["HsTglBtn"] := g.Add("Button", "x(contentX+382) y(contentY+36+46) w110 h28" BtnBg(), "Toggle")
    App.Ui["HsTglBtn"].OnEvent("Click", HsToggleSelected)
    App.LV_Hotstrings := g.Add("ListView", "x(contentX+10) y(contentY+36+82) w" inW " h" lvH " NoSortHdr +Background" App.Theme["Background"]
        , ["Trigger", "Output", "Status"])
    App.LV_Hotstrings.ModifyCol(1, 200)
    App.LV_Hotstrings.ModifyCol(2, lvW - 200 - 90 - 26)
    App.LV_Hotstrings.ModifyCol(3, 90)
    App.LV_Hotstrings.OnEvent("DoubleClick", HsDoubleClick)
    App.Ui["EmptyHs"] := g.Add("Text", "x" (contentX + 10 + (inW - 220) // 2) " y" (contentY + 36 + 82 + (lvH // 2) - 11) " w220 h22 c" App.Theme["Hint"] " +BackgroundTrans Center"
        , "No hotstrings yet - press New...")
    App.Ui["EmptyHs"].Visible := false

    ; -- Tab 4: Macros (user request) - the global macro library --
    tabs.UseTab(4)
    ; ONE row, compact (user request), Builder first; the row ends at
    ; ~510px so the tab can still shrink below the default window size
    App.Ui["MacroBuilderBtn"] := g.Add("Button", "x(contentX+10) y(contentY+36+46) w110 h28" BtnBg(), "Builder...")
    App.Ui["MacroBuilderBtn"].OnEvent("Click", MacroNewStructured)
    App.Ui["MacroEditBtn"] := g.Add("Button", "x(contentX+134) y(contentY+36+46) w110 h28" BtnBg(), "Edit...")
    App.Ui["MacroEditBtn"].OnEvent("Click", MacroEditSelected)
    App.Ui["MacroDelBtn"] := g.Add("Button", "x(contentX+258) y(contentY+36+46) w110 h28" BtnBg(), "Delete")
    App.Ui["MacroDelBtn"].OnEvent("Click", MacroDeleteSelected)
    App.Ui["MacroRunBtn"] := g.Add("Button", "x(contentX+382) y(contentY+36+46) w110 h28" BtnBg(), "Run once")
    App.Ui["MacroRunBtn"].OnEvent("Click", MacroRunSelected)
    App.Ui["MacroAssignBtn"] := g.Add("Button", "x(contentX+506) y(contentY+36+46) w110 h28" BtnBg(), "Assign...")
    App.Ui["MacroAssignBtn"].OnEvent("Click", MacroAssignSelected)
    App.LV_Macros := g.Add("ListView", "x(contentX+10) y(contentY+36+82) w" inW " h" lvH " NoSortHdr +Background" App.Theme["Background"]
        , ["Name", "Chars", "Preview"])
    App.LV_Macros.ModifyCol(1, 170)
    App.LV_Macros.ModifyCol(2, 60)
    App.LV_Macros.ModifyCol(3, lvW - 170 - 60 - 26)
    App.LV_Macros.OnEvent("DoubleClick", MacroDoubleClick)
    App.Ui["EmptyMac"] := g.Add("Text", "x" (contentX + 10 + (inW - 220) // 2) " y" (contentY + 36 + 82 + (lvH // 2) - 11) " w220 h22 c" App.Theme["Hint"] " +BackgroundTrans Center"
        , "No macros yet - press Builder...")
    App.Ui["EmptyMac"].Visible := false
    tabs.UseTab()

    ; ---- bottom status strip (UI 2) ----
    statusY := contentY + tabH + 6
    statusW := contentX + contentW - marginX
    App.Ui["Status"] := g.Add("Text", "x" marginX " y" statusY " w" statusW " h24 +BackgroundTrans c" App.Theme["Text"], "")

    ; ---- window events + hidden Default button for Enter (UI 4) ----
    g.OnEvent("Close", HideGui)
    g.OnEvent("Escape", HideGui)
    g.OnEvent("Size", GuiSize)
    g.Add("Button", "Hidden Default", "OK").OnEvent("Click", LvEnter)
}

; Initial window size, capped to the screen (user request: automatic
; sizing for smaller screens). The floor matches the MinSize option.
InitialWinSize() {
    w := Max(800, Min(Consts.WinW, A_ScreenWidth - 80))
    h := Max(600, Min(Consts.WinH, A_ScreenHeight - 120))
    return "w" w " h" h
}

; Dynamic layout on window resize (user request): the tab control,
; both ListViews with their filter edits and empty-state hints, the
; guide sub-tabs, the pinned Exit button and the status strip follow
; the actual client size. The sidebar and the Settings rows keep
; their fixed geometry. The numeric constants MUST mirror the
; BuildMainGui layout constants (D-06) - they are repeated here
; because build-time locals do not survive into the event callback.
GuiSize(g, minMax, w, h) {
    ; minMax is deliberately NOT used as a guard: the Win32 mapping
    ; (1 = minimized) does not necessarily hold on other toolkits, and
    ; an early return on minMax=1 left the layout fully static while
    ; resizing (user report: shrinking cut the bottom off). Guard on
    ; the actual client size instead.
    ; * lvY is the PAGE-frame y of the lists (the "yc+82" frame); the
    ;   hint Moves add contentY + 36 to reach the window frame.
    if (!IsObject(App.MainGui) || g != App.MainGui)
        return
    if (w < 420 || h < 480)
        return
    try {
        pad := 12
        contentX := 160
        contentY := 10
        marginX := 14
        bandH := 42                       ; status strip band
        tabW := w - contentX - marginX
        tabsH := h - contentY - bandH
        lvW := tabW - 24                   ; 10-12px in-tab margins
        lvY := 82                          ; in-tab y of the ListViews
        lvH := tabsH - lvY - pad
        ; FIXED-POSITION children move FIRST: GTK clamps a container's
        ; shrink to its children's CURRENT extents, so anything pinned
        ; low must be out of the way before the tall content shrinks.
        if App.Ui.Has("ExitBtn")
            App.Ui["ExitBtn"].Move(marginX, h - 74)   ; 10px above the status strip
        if App.Ui.Has("Status")
            App.Ui["Status"].Move(marginX, h - 34, w - marginX * 2, 24)
        ; CONTENT FIRST, tab control LAST: on GTK the tab control's
        ; shrink gets clamped by its current content, so resizing
        ; the lists before the tab lets both shrink (user report:
        ; past a certain height the lists resized but the tab did not).
        try {
            if App.Ui.Has("FilterCmd") {
                App.Ui["FilterCmd"].Move(, , lvW - 60)
                App.LV_Cmd.Move(, , lvW, lvH)
                if App.Ui.Has("EmptyCmd")
                    App.Ui["EmptyCmd"].Move(contentX + 10 + (lvW - 220) // 2, contentY + 36 + lvY + (lvH // 2) - 11, 220, 22)
            }
        } catch as ErrC {
            LogError("resize cmd list: " ErrC.Message)
        }
        try {
            if App.Ui.Has("FilterKey") {
                App.Ui["FilterKey"].Move(, , lvW - 60)
                App.LV_Key.Move(, , lvW, lvH)
                if App.Ui.Has("EmptyKey")
                    App.Ui["EmptyKey"].Move(contentX + 10 + (lvW - 220) // 2, contentY + 36 + lvY + (lvH // 2) - 11, 220, 22)
            }
        } catch as ErrK {
            LogError("resize key list: " ErrK.Message)
        }
        try {
            if App.Ui.Has("GuideTabs")
                App.Ui["GuideTabs"].Move(, , tabW - 8, tabsH - 36)
            if App.Ui.Has("GuideTxts") {
                gw := lvW - 14
                for , gt in App.Ui["GuideTxts"]
                    gt.Move(, , gw)
            }
        } catch as ErrG {
            LogError("resize guide: " ErrG.Message)
        }
        try {
            if IsObject(App.LV_Hotstrings) {
                App.LV_Hotstrings.Move(, , lvW, lvH)
                App.LV_Hotstrings.ModifyCol(2, lvW - 200 - 90 - 26)
                if App.Ui.Has("EmptyHs")
                    App.Ui["EmptyHs"].Move(contentX + 10 + (lvW - 220) // 2, contentY + 36 + lvY + (lvH // 2) - 11, 220, 22)
            }
        } catch as ErrHs {
            LogError("resize hotstrings list: " ErrHs.Message)
        }
        try {
            if IsObject(App.LV_Macros) {
                App.LV_Macros.Move(, , lvW, lvH)
                App.LV_Macros.ModifyCol(3, lvW - 170 - 60 - 26)
                if App.Ui.Has("EmptyMac")
                    App.Ui["EmptyMac"].Move(contentX + 10 + (lvW - 220) // 2, contentY + 36 + lvY + (lvH // 2) - 11, 220, 22)
            }
        } catch as ErrM {
            LogError("resize macros list: " ErrM.Message)
        }
        try App.LV_Cmd.ModifyCol(2, lvW - 150 - 64 - 150 - 26)
        try App.LV_Key.ModifyCol(2, lvW - 150 - 64 - 150 - 26)
        ; Tab control: Move first, Opt fallback second - if both fail,
        ; say so visibly (user report: vertical shrink never applied)
        try App.Ui["Tab"].Move(contentX, contentY, tabW, tabsH)
        catch as ErrT {
            try App.Ui["Tab"].Opt("w" tabW " h" tabsH)
            catch as ErrT2 {
                LogError("tab resize: " ErrT.Message " / " ErrT2.Message)
                SetStatus("Tab resize unsupported on this build")
            }
        }
    } catch as Err {
        LogError("resize: " Err.Message)
    }
}

; Tooltips (UI 5): Tips class from the facts file, applied to the
; Repeat/Startup buttons, the shell controls and the filter boxes.
InstallTips() {
    Tips.Init(App.MainGui)
    Tips.AddTip(App.Ui["RepeatBtn"], "While held, a remapped key keeps repeating its output (uses the buffer/delay settings).")
    Tips.AddTip(App.Ui["StartupBtn"], "Create or remove the Startup-folder shortcut. Requires administrator privileges.")
    Tips.AddTip(App.Ui["ShellDDL"], "Shell used for & command actions; the list shows the shells detected on this device.")
    Tips.AddTip(App.Ui["ShellVisBtn"], "Show or hide the console window when & commands run.")
    Tips.AddTip(App.Ui["FilterCmd"], "Type to filter the command list by key, command or window scope.")
    Tips.AddTip(App.Ui["FilterKey"], "Type to filter the remap list by key, output or window scope.")
}

; * Single bulk refresh for every list surface (BUG-01: callers
;   never refresh mid-batch; this is the only fill path).
RefreshGuiData() {
    if !IsObject(App.MainGui)
        return
    profile := ActiveProfileMap()
    FillBindingList(App.LV_Cmd, profile, "cmd", App.Filter_Cmd, App.Ui.Has("EmptyCmd") ? App.Ui["EmptyCmd"] : 0)
    FillBindingList(App.LV_Key, profile, "key", App.Filter_Key, App.Ui.Has("EmptyKey") ? App.Ui["EmptyKey"] : 0)
    FillMacroList()
    FillHotstringList()
    FillProfilesTab()
    RebuildPixelWatchers()
    PopulateProfileDDL()
}

FillBindingList(LV, profile, type, filter, emptyCtrl) {
    if !IsObject(LV)
        return
    LV.Opt("-Redraw")
    LV.Delete()
    needle := StrUpper(filter)
    shown := 0
    total := 0
    for , b in profile {
        if (b["Type"] != type)
            continue
        if (SubStr(b["Key"], 1, 3) = "hs:" || SubStr(b["Key"], 1, 3) = "px:")
            continue   ; hotstring/pixel triggers have their own surfaces
        total++
        if (needle != "") {
            hay := StrUpper(b["Key"] . b["Action"] . b["Scope"])
            if !InStr(hay, needle)
                continue
        }
        opt := App.Icons ? "Icon" (type = "cmd" ? 1 : 2) : ""
        LV.Add(opt, b["Key"], b["Action"], b["Enabled"] ? "Enabled" : "Disabled", b["Scope"])
        shown++
    }
    LV.Opt("+Redraw")
    ; empty state (UI 7): centered overlay hint (user-confirmed form)
    if IsObject(emptyCtrl) {
        if (shown = 0) {
            emptyCtrl.Text := (total > 0) ? "No matches for the current filter" : "No bindings yet - press + Add Binding"
            emptyCtrl.Visible := true
        } else {
            emptyCtrl.Visible := false
        }
    }
}

; Row -> binding resolution: Key (col 1) + Window (col 4) text
; plus the tab's type. Bindings always have unique ids.
BindingIdFromRow(LV, row) {
    try {
        key := LV.GetText(row, 1)
        scope := LV.GetText(row, 4)
        type := (LV = App.LV_Cmd) ? "cmd" : "key"
        return type "|" key "|" scope
    } catch as Err {
        LogError("row lookup failed: " Err.Message)
        return ""
    }
}

; ListView of the current tab (0 on Settings / Usage Guide).
CurrentTabLV() {
    if (App.CTab = 1)
        return App.LV_Cmd
    if (App.CTab = 2)
        return App.LV_Key
    return 0
}

; FocusedCtrl guard (facts R6): wrap in try/catch + IsObject.
FocusedCtrlIs(ctrl) {
    try {
        f := App.MainGui.FocusedCtrl
        return IsObject(f) && (f = ctrl)
    } catch as Err {
        return false
    }
}

; Settings-tab profile DDL (re-populated on every profile change).
PopulateProfileDDL() {
    if !App.Ui.Has("ProfileDDL")
        return
    try {
        ddl := App.Ui["ProfileDDL"]
        names := []
        for name, profile in App.Profiles
            names.Push(name)
        ddl.Delete()
        if (names.Length > 0)
            ddl.Add(names)
        idx := 1
        for i, name in names {
            if (name = App.ActiveProfile)
                idx := i
        }
        if (names.Length > 0)
            ddl.Choose(idx)
    } catch as Err {
        LogError("profile DDL: " Err.Message)
    }
}

; =============================================================
; 9. GUI events
; =============================================================

; Tab change: remember the active tab (Add-Binding prefill and the
; Del/Enter scoping). A non-integer value can only mean a broken
; toolkit - fall back to tab 1 instead of crashing.
TabCh(ctrl, *) {
    v := ctrl.Value
    App.CTab := IsInteger(v) ? Integer(v) : 1
}

; Filter text change: remember the needle, then one bulk refresh.
OnFilterCmdChange(ctrl, *) {
    App.Filter_Cmd := ctrl.Value
    RefreshGuiData()
}

; Filter text change: remember the needle, then one bulk refresh.
OnFilterKeyChange(ctrl, *) {
    App.Filter_Key := ctrl.Value
    RefreshGuiData()
}

; Caption updates only through .Text - never .Value (BUG-02).
ToggleRepeat(*) {
    App.Settings["DoRepeatOutputs"] := App.Settings["DoRepeatOutputs"] ? 0 : 1
    SyncProfileSetting("DoRepeatOutputs")
    if App.Ui.Has("RepeatBtn")
        App.Ui["RepeatBtn"].Text := App.Settings["DoRepeatOutputs"] ? "Disable" : "Enable"
    SetStatus(App.Settings["DoRepeatOutputs"] ? "Repeat while held: on" : "Repeat while held: off")
}

; Idempotent integer sync from the UpDown controls' Change event
; (extra-defect fix retained: the old Submit(false) result was
; discarded, values never synced).
SyncEditSetting(settingKey, editName, minV, maxV) {
    if !App.Ui.Has(editName)
        return
    ; the UpDown/NumericUpDown Value may arrive as an Integer, a
    ; plain string or (Keysharp) decimal text like "250.0" - parse
    ; defensively (garbage reads as below-range, then clamps to min)
    v := SafeInt(App.Ui[editName].Value, minV - 1)
    if (v < minV)
        v := minV
    if (v > maxV)
        v := maxV
    App.Settings[settingKey] := v
    SyncProfileSetting(settingKey)   ; write-through to the active profile
}

OnRepeatBufChange(*) {
    SyncEditSetting("RepeatBuffer", "RepeatBufUD", 0, 1000)
}

OnRepeatDelayChange(*) {
    SyncEditSetting("RepeatDelay", "RepeatDelayUD", 0, 500)
}

; Startup toggle (BUG-03): the flag flips ONLY after the file op
; succeeds inside try/catch; failures surface via status + log.
ToggleStartup(*) {
    if !A_IsAdmin {
        MsgBox("This setting requires the program to have administrator privileges.`nPlease launch the program again as administrator.", "Insufficient permissions", "Iconx")
        return
    }
    want := App.Settings["DoStartup"] ? 0 : 1
    try {
        if (want && !FileExist(App.StartupLnk))
            FileCreateShortcut(A_ScriptFullPath, App.StartupLnk, A_ScriptDir, "--silent", App.Name " startup entry")
        else if (!want && FileExist(App.StartupLnk))
            FileDelete(App.StartupLnk)
        App.Settings["DoStartup"] := want
        if App.Ui.Has("StartupBtn")
            App.Ui["StartupBtn"].Text := want ? "Disable" : "Enable"
        SetStatus(want ? "Run at startup: enabled" : "Run at startup: disabled")
    } catch as Err {
        LogError("startup toggle failed: " Err.Message)
        SetStatus("Startup toggle failed - see error log")
    }
}

; Shell DDL change: persist the selected shell Id. The index is
; bounds-checked - never trust a toolkit-provided index.
OnShellDDLChange(ctrl, *) {
    idx := ctrl.Value
    if (idx >= 1 && idx <= App.Shells.Length)
        App.Settings["ShellCmd"] := App.Shells[idx]["Id"]
    SetStatus("Shell for & commands: " ctrl.Text)
}

; Console visibility flip for & commands (Hidden/Visible face).
ToggleShellVis(*) {
    App.Settings["ShellHidden"] := App.Settings["ShellHidden"] ? 0 : 1
    if App.Ui.Has("ShellVisBtn")
        App.Ui["ShellVisBtn"].Text := App.Settings["ShellHidden"] ? "Hidden" : "Visible"
    SetStatus("& commands will run " (App.Settings["ShellHidden"] ? "hidden" : "visible"))
}

; * Custom suspend - NOT AHK's Suspend(): F1, the window, the tray and
;   the recorder keep working; only the user's triggers stop
;   intercepting and responding.
SuspendTriggers() {
    if (App.Suspended)
        return
    App.Suspended := true
    UnregisterAllHotkeys()   ; hotkey variants, up-variants, hotstrings
    App.PixelWatchers := []  ; watchers stop re-arming
    if App.Ui.Has("SuspendBtn")
        App.Ui["SuspendBtn"].Text := "Unsuspend"
    SetStatus("Triggers suspended")
}

; Lift the custom suspend: re-register the active profile's triggers.
UnsuspendTriggers() {
    if (!App.Suspended)
        return
    App.Suspended := false
    RegisterAllHotkeys()
    RebuildPixelWatchers()
    if App.Ui.Has("SuspendBtn")
        App.Ui["SuspendBtn"].Text := "Suspend"
    SetStatus("Triggers active")
}

; Suspend button (the old Apply slot): toggle the custom suspend.
ToggleSuspendBtn(*) {
    App.Suspended ? UnsuspendTriggers() : SuspendTriggers()
}

; Settings row 7: launch suspended until manually unsuspended.
ToggleStartSuspended(*) {
    App.Settings["StartSuspended"] := App.Settings["StartSuspended"] ? 0 : 1
    if App.Ui.Has("StartSuspBtn")
        App.Ui["StartSuspBtn"].Text := App.Settings["StartSuspended"] ? "Disable" : "Enable"
    SaveSettings()
    SetStatus(App.Settings["StartSuspended"] ? "Start as suspended: on" : "Start as suspended: off")
}

; Settings row 8: save after changes, silently (no status feedback).
ToggleAutosave(*) {
    App.Settings["Autosave"] := App.Settings["Autosave"] ? 0 : 1
    if App.Ui.Has("AutosaveBtn")
        App.Ui["AutosaveBtn"].Text := App.Settings["Autosave"] ? "Disable" : "Enable"
    SaveSettings()
    if (App.Settings["Autosave"] && App.IsDirty)
        SetTimer(AutosaveFire, -500)
    SetStatus(App.Settings["Autosave"] ? "Autosave: on" : "Autosave: off")
}

; Profiles tab Switch button: apply the DDL selection ("" = no-op).
OnProfileSwitchBtn(*) {
    if !App.Ui.Has("ProfileDDL")
        return
    SwitchProfile(App.Ui["ProfileDDL"].Text)
}

; F1 hide/show. Never rebuild when the Gui object exists
; (WinExist cannot see hidden windows - extra-defect fix).
ToggleGui(*) {
    if !IsObject(App.MainGui) {
        BuildMainGui()
        ApplyTheme()
        InitRowIcons()
        InstallTips()
        RefreshGuiData()
        App.MainGui.Show(InitialWinSize())
        App.Settings["GuiVisible"] := 1
    } else if (App.Settings["GuiVisible"]) {
        HideGui()
    } else {
        App.MainGui.Show(InitialWinSize())
        App.Settings["GuiVisible"] := 1
    }
}

HideGui(*) {
    if !IsObject(App.MainGui)
        return
    try App.MainGui.Hide()
    catch as Err {
        return   ; hiding failed; leave the visibility flag alone
    }
    App.Settings["GuiVisible"] := 0
    TrayTip("Running in the background...", App.Name, "Iconi")
}

; --- Keyboard navigation (UI 4) ---

; Enter = hidden Default button; only acts when the current tab's
; ListView has focus, otherwise native behavior applies.
LvEnter(*) {
    lv := CurrentTabLV()
    if !IsObject(lv)
        return
    if !FocusedCtrlIs(lv)
        return
    row := lv.GetNext(0)
    if (row = 0)
        return
    id := BindingIdFromRow(lv, row)
    if (id != "")
        OpenEditor("Edit", id)
}

; Del = delete the selected rows of the focused ListView, else
; pass the keystroke through ($ prefix prevents self-triggering).
LvDelete(*) {
    lv := CurrentTabLV()
    if (IsObject(lv) && FocusedCtrlIs(lv))
        DeleteSelectedBindings()
    else
        Send("{Del}")
}

; Ctrl+Z = undo when a ListView has focus, else passthrough.
LvUndo(*) {
    lv := CurrentTabLV()
    if (IsObject(lv) && FocusedCtrlIs(lv))
        Undo()
    else
        Send("^z")
}

; Double-click a row = open the editor in Edit mode (facts 7a:
; DoubleClick Info carries the row number).
LvDoubleClick(ctrl, info, *) {
    if (info = 0)
        return
    id := BindingIdFromRow(ctrl, info)
    if (id != "")
        OpenEditor("Edit", id)
}

; Right-click a row = popup menu: Toggle / Edit / Delete
; (v2.0 has no ItemClick; ContextMenu gives Item = row, facts 7a).
LvContextMenu(ctrl, item, isRight, x, y, *) {
    if (item = 0)
        return
    id := BindingIdFromRow(ctrl, item)
    if (id = "")
        return
    b := GetBinding(id)
    if !IsObject(b)
        return
    try {
        m := Menu()
        m.Add((b["Enabled"] ? "Disable binding" : "Enable binding"), RowMenuToggle.Bind(id))
        m.Add("Edit...", RowMenuEdit.Bind(id))
        m.Add("Delete", RowMenuDelete.Bind(id))
        m.Show(x, y)
    } catch as Err {
        LogError("row menu: " Err.Message)
    }
}

RowMenuToggle(id, *) {
    b := GetBinding(id)
    if !IsObject(b)
        return
    PushUndo()
    SetBindingEnabled(id, !b["Enabled"])
    RefreshGuiData()
    SetStatus((b["Enabled"] ? "Enabled" : "Disabled") " binding: " b["Key"])
}

RowMenuEdit(id, *) {
    OpenEditor("Edit", id)
}

RowMenuDelete(id, *) {
    PushUndo()
    RemoveBinding(id)
    SetDirty()
    RefreshGuiData()
    SetStatus("Binding deleted")
}

; Sidebar Delete: deletes all SELECTED rows of the current tab
; (multi-select is native in v2.0, facts 7e); confirms only when
; more than one row is selected; one refresh at the end (BUG-01).
DeleteSelectedBindings(*) {
    lv := CurrentTabLV()
    if !IsObject(lv)
        return
    rows := []
    row := lv.GetNext(0)
    while (row != 0) {
        rows.Push(row)
        row := lv.GetNext(row)
    }
    if (rows.Length = 0) {
        SetStatus("No rows selected")
        return
    }
    if (rows.Length > 1) {
        if (MsgBox("Delete " rows.Length " bindings?", App.Name, "YesNo Icon! Default2") != "Yes")
            return
    }
    PushUndo()
    for , r in rows {
        id := BindingIdFromRow(lv, r)
        if (id != "")
            RemoveBinding(id)
    }
    SetDirty()
    RefreshGuiData()
    SetStatus("Deleted " rows.Length " binding(s)")
}

; Sidebar Toggle On/Off: flips every selected row's binding.
ToggleSelectedBindings(*) {
    lv := CurrentTabLV()
    if !IsObject(lv)
        return
    rows := []
    row := lv.GetNext(0)
    while (row != 0) {
        rows.Push(row)
        row := lv.GetNext(row)
    }
    if (rows.Length = 0) {
        SetStatus("No rows selected")
        return
    }
    PushUndo()
    for , r in rows {
        id := BindingIdFromRow(lv, r)
        b := GetBinding(id)
        if IsObject(b)
            SetBindingEnabled(id, !b["Enabled"])
    }
    RefreshGuiData()
    SetStatus("Toggled " rows.Length " binding(s)")
}

; Clear Bindings: clears the ACTIVE profile (confirm kept).
ClearBindings(*) {
    if (MsgBox("Remove all bindings in profile '" App.ActiveProfile "'?", App.Name, "YesNo Icon! Default2") != "Yes")
        return
    PushUndo()
    UnregisterAllHotkeys()
    ActiveProfileMap().Clear()
    SetDirty()
    RefreshGuiData()
    SetStatus("All bindings cleared")
}

; =============================================================
; 9b. Binding editor (features 2 + 5)
; =============================================================

; "+ Add Binding" opens the editor with the CURRENT tab's binding
; type preselected (user request: it always defaulted to Command).
AddBindingClicked(*) {
    pre := Map("Type", (App.CTab = 2) ? "key" : "cmd")
    OpenEditor("Add", "", pre)
}

; Interception-type dropdown entries (Hotkey triggers only). The
; leading ~$* symbol run of each label IS the stored value.
IcpLabels() {
    return ["Unspecified", "~ Passthrough", "$ Force hook", "* Wildcard"
        , "~$ Hook + passthrough", "~* Passthrough + wildcard", "$* Hook + wildcard", "~$* All three"]
}

; Label -> the ~$* symbol run it starts with ("" for Unspecified).
IcpFromLabel(lbl) {
    RegExMatch(lbl, "^[~$]*", &im)
    return im[0]
}

; Stored ~$* run -> dropdown index (1 = Unspecified for unknowns).
IcpLabelIndex(icp) {
    for i, lbl in IcpLabels() {
        if (IcpFromLabel(lbl) = icp)
            return i
    }
    return 1
}

OpenEditor(mode := "Add", id := "", prefill := 0) {
    st := Map("Mode", mode, "OrigId", "", "Type", "cmd", "Key", "", "Action", "", "Scope", "", "Trig", "hk", "Icp", "")
    if (mode = "Edit") {
        b := GetBinding(id)
        if IsObject(b) {
            st["OrigId"] := id
            st["Type"] := b["Type"]
            st["Key"] := b["Key"]
            st["Action"] := b["Action"]
            st["Scope"] := b["Scope"]
            st["Icp"] := BindingIcp(b)
        } else {
            ; diagnostic (user report: edit mode opened empty) - if
            ; this appears in error.log, the row->id lookup failed
            st["Mode"] := "Add"
            LogError("editor: edit-mode binding id not found: '" id "'")
        }
    } else if IsObject(prefill) {
        if prefill.Has("Type")
            st["Type"] := prefill["Type"]
        if prefill.Has("Action")
            st["Action"] := prefill["Action"]
        if prefill.Has("Trig")
            st["Trig"] := prefill["Trig"]
    }
    ; * st stays LOCAL to this dialog. The save handler receives it
    ;   via Bind() so two simultaneously open editors cannot
    ;   cross-contaminate their Mode/OrigId (review finding 4).

    ed := Gui("-MaximizeBox +Owner" App.MainGui.Hwnd " +OwnDialogs", App.Name " - Binding Editor")
    ed.BackColor := App.Theme["Background"]
    ed.SetFont("s10 c" App.Theme["Text"], "Segoe UI")

    ed.Add("Text", "x16 y16 w66 h22", "Type:")
    typeDDL := ed.Add("DDL", "x86 y14 w140 vType", ["Command", "Key Remap"])
    typeDDL.OnEvent("Change", EditorTypeChange)
    ; interception type (Hotkey triggers only): ~ / $ / * prefixes
    ed.Add("Text", "x230 y16 w66 h22 vIcpLbl", "Intercept:")
    icpDDL := ed.Add("DDL", "x300 y14 w150 vIcp Choose1", IcpLabels())

    ed.Add("Text", "x16 y62 w66 h22 vKeyLbl", "Keybind:")
    trigDDL := ed.Add("DDL", "x330 y60 w120 vTrig Choose1", ["Hotkey", "Hotstring", "Pixel"])
    trigDDL.OnEvent("Change", EditorTrigChange)
    ed.Add("Edit", "x86 y60 w220 h22 vKeyEdit c" App.Theme["Text"] " +Background" App.Theme["Control"], st["Key"])

    ; key picker (feature 2): modifier checkboxes, then the category
    ; and key DDLs stacked VERTICALLY with labels. Spacious layout
    ; (user report: elements stacked over each other): every row gets
    ; a 46-48px pitch so even GTK's taller-than-declared combos
    ; (~30-32px) keep clear separation.
    ed.Add("Text", "x16 y110 w66 h22 vPickerLbl", "Picker:")
    ed.Add("CheckBox", "x86 y108 w56 h22 vModCtrl" BtnBg(), "Ctrl")
    ed.Add("CheckBox", "x150 y108 w56 h22 vModAlt" BtnBg(), "Alt")
    ed.Add("CheckBox", "x214 y108 w64 h22 vModShift" BtnBg(), "Shift")
    ed.Add("CheckBox", "x288 y108 w56 h22 vModWin" BtnBg(), "Win")
    for , cbName in ["ModCtrl", "ModAlt", "ModShift", "ModWin"]
        ed[cbName].OnEvent("Click", PickerChange)

    ed.Add("Text", "x16 y158 w66 h22 vCatLbl", "Category:")
    catDDL := ed.Add("DDL", "x86 y156 w200 vKeyCat", PickerCategoryNames())
    catDDL.OnEvent("Change", EditorCatChange)
    catDDL.Choose(1)
    ed.Add("Text", "x16 y206 w66 h22 vKeyPickLbl", "Key:")
    keyDDL := ed.Add("DDL", "x86 y204 w200 vKeyPick", PickerKeysForCategory("Letters"))
    keyDDL.OnEvent("Change", PickerChange)

    isCmd := (st["Type"] = "cmd")
    ed.Add("Text", "x16 y254 w66 h22 vActionLabel", isCmd ? "Command:" : "Output key:")
    actionOpts := isCmd ? "x86 y252 w320 h80 Multi vAction" : "x86 y252 w320 h22 vAction"
    ed.Add("Edit", actionOpts " c" App.Theme["Text"] " +Background" App.Theme["Control"], st["Action"])

    ed.Add("Text", "x16 y366 w400 h22 vScopeLbl", "Window scope (optional) - e.g. ahk_exe chrome.exe")
    ed.Add("Edit", "x86 y392 w320 h22 vScopeEdit c" App.Theme["Text"] " +Background" App.Theme["Control"], st["Scope"])

    ; Pixel trigger fields (visible when Trigger = Pixel)
    ed.Add("Text", "x16 y366 w60 h22 vPXT", "Pixel X:")
    ed.Add("Edit", "x80 y364 w60 h22 vPX c" App.Theme["Text"] " +Background" App.Theme["Control"], 0)
    ed.Add("Text", "x150 y366 w20 h22 vPYT", "Y:")
    ed.Add("Edit", "x176 y364 w60 h22 vPY c" App.Theme["Text"] " +Background" App.Theme["Control"], 0)
    ed.Add("Text", "x244 y366 w44 h22 vPCT", "Color:")
    ed.Add("Edit", "x292 y364 w70 h22 vPC c" App.Theme["Text"] " +Background" App.Theme["Control"], "FFFFFF")
    ed.Add("DDL", "x370 y364 w80 vPM Choose1", ["to", "from"])
    testBtn := ed.Add("Button", "x235 y440 w90 h28" BtnBg(), "Test")
    testBtn.OnEvent("Click", TestRemap)
    saveBtn := ed.Add("Button", "x335 y440 w90 h28" BtnBg(), "Save")
    saveBtn.OnEvent("Click", EditorSave.Bind(st))
    cancelBtn := ed.Add("Button", "x435 y440 w90 h28" BtnBg(), "Cancel")
    cancelBtn.OnEvent("Click", (*) => ed.Destroy())

    typeDDL.Choose(isCmd ? 1 : 2)
    ; Explicit .Value prefill AFTER creation: the Add()-third-parameter
    ; initial text proved unreliable under GTK (user report: Edit mode
    ; opened empty and Save demanded the key be retyped).
    ed["Action"].Value := st["Action"]
    ed["ScopeEdit"].Value := st["Scope"]
    trigIdx := 1
    dispKey := st["Key"]
    if (SubStr(st["Key"], 1, 3) = "hs:") {
        trigIdx := 2
        dispKey := SubStr(st["Key"], 4)
    } else if (SubStr(st["Key"], 1, 3) = "px:") {
        trigIdx := 3
        dispKey := SubStr(st["Key"], 4)
    }
    if (st["Trig"] = "hs")
        trigIdx := 2
    ed["Trig"].Choose(trigIdx)
    ed["Icp"].Choose(IcpLabelIndex(st["Icp"]))
    ed["KeyEdit"].Value := dispKey
    EditorTrigChange(ed["Trig"])
    if (trigIdx = 1 && st["Key"] != "")
        SyncPickerFromKey(ed, st["Key"])
    ed.Show("w535 h490")
}

; Trigger-type switch: the Keybind label text and the key picker
; follow (picker is meaningful only for Hotkey triggers; remaps are
; hotkey-only, so Type=Key Remap forces the Hotkey trigger).
EditorTrigChange(ctrl, *) {
    g := ctrl.Gui
    trig := ctrl.Text
    hk := (trig = "Hotkey")
    try g["KeyLbl"].Text := hk ? "Keybind:" : (trig = "Hotstring") ? "Hotstring:" : "Pixel:"
    for , n in ["PickerLbl", "ModCtrl", "ModAlt", "ModShift", "ModWin", "CatLbl", "KeyCat", "KeyPickLbl", "KeyPick", "IcpLbl", "Icp"]
        try g[n].Visible := hk
    px := (trig = "Pixel")
    ; the pixel fields and the scope row trade places
    for , n in ["PXT", "PX", "PYT", "PY", "PCT", "PC", "PM"]
        try g[n].Visible := px
    try g["ScopeLbl"].Visible := !px
    try g["ScopeEdit"].Visible := !px
    ; remember the user's trigger across Command <-> Key Remap switches
    if (!hk && trig != "Pixel")
        App.EditorLastTrig := "hs"
    else if (hk)
        App.EditorLastTrig := ""
}

; Type switch: relabel the action field and resize it (.Text only).
; Type itself is derived from the DDL when saving, so no shared
; state is written here.
EditorTypeChange(ctrl, *) {
    g := ctrl.Gui
    if (ctrl.Text = "Key Remap") {
        g["ActionLabel"].Text := "Output key:"
        g["Action"].Opt("h22")
        g["Trig"].Choose(1)
        EditorTrigChange(g["Trig"])
    } else {
        if (App.EditorLastTrig = "hs") {
            g["Trig"].Choose(2)
            EditorTrigChange(g["Trig"])
        }
        g["ActionLabel"].Text := "Command:"
        g["Action"].Opt("h80")
    }
}

; Category DDL change: refill the key DDL and re-compose the keybind.
EditorCatChange(ctrl, *) {
    PopulateKeyPick(ctrl.Gui, ctrl.Text)
    PickerChange(ctrl)
}

; Any picker interaction writes the composed key (e.g. #^G) into
; the Keybind Edit. Modifier symbols in canonical order #^!+.
PickerChange(ctrl, *) {
    ComposePickerKey(ctrl.Gui)
}

ComposePickerKey(ed) {
    try {
        mods := ""
        if (ed["ModWin"].Value = 1)
            mods .= "#"
        if (ed["ModCtrl"].Value = 1)
            mods .= "^"
        if (ed["ModAlt"].Value = 1)
            mods .= "!"
        if (ed["ModShift"].Value = 1)
            mods .= "+"
        keyName := ed["KeyPick"].Text
        if (keyName = "")
            return
        ed["KeyEdit"].Value := mods keyName
    } catch as Err {
        LogError("picker compose: " Err.Message)
    }
}

; Reflect an existing keybind text (e.g. #^F) in the picker row:
; modifier checkboxes + category/key DDLs (user report: edit mode
; showed the key text but the picker stayed unselected).
SyncPickerFromKey(ed, keyText) {
    try {
        ed["ModCtrl"].Value := InStr(keyText, "^") ? 1 : 0
        ed["ModAlt"].Value := InStr(keyText, "!") ? 1 : 0
        ed["ModShift"].Value := InStr(keyText, "+") ? 1 : 0
        ed["ModWin"].Value := InStr(keyText, "#") ? 1 : 0
        base := RegExReplace(keyText, "[\^!+#]")
        if (base = "")
            return
        cat := (StrLen(base) = 1) ? (RegExMatch(base, "\d") ? "Digits" : "Letters") : KeyCategory(base)
        if (cat = "")
            return
        for i, cname in PickerCategoryNames() {
            if (cname = cat) {
                ed["KeyCat"].Choose(i)
                break
            }
        }
        PopulateKeyPick(ed, cat)
        for i, kname in PickerKeysForCategory(cat) {
            if (StrUpper(kname) = StrUpper(base)) {
                ed["KeyPick"].Choose(i)
                break
            }
        }
    } catch as Err {
        LogError("picker sync: " Err.Message)
    }
}

PopulateKeyPick(ed, cat) {
    try {
        keys := PickerKeysForCategory(cat)
        kp := ed["KeyPick"]
        kp.Delete()
        if (keys.Length > 0) {
            kp.Add(keys)
            kp.Choose(1)
        }
    } catch as Err {
        LogError("key picker: " Err.Message)
    }
}

PickerKeysForCategory(cat) {
    keys := []
    if (cat = "Letters") {
        loop 26
            keys.Push(Chr(64 + A_Index))   ; A..Z
    } else if (cat = "Digits") {
        loop 10
            keys.Push("" (A_Index - 1))    ; "0".."9"
    } else if App.PickerCats.Has(cat) {
        for , name in App.PickerCats[cat]
            keys.Push(name)
    }
    return keys
}

PickerCategoryNames() {
    return ["Letters", "Digits", "Function Keys", "Navigation", "Editing", "Numpad", "Mouse", "Media", "Browser", "System"]
}

; Organizational classifier: assigns a picker category to a
; KEY_LIST name. KEY_LIST stays the single source of validity;
; an uncategorized name simply is not offered in the picker.
KeyCategory(name) {
    if RegExMatch(name, "^F\d\d?$")
        return "Function Keys"
    if RegExMatch(name, "^Numpad\w*$")
        return "Numpad"
    if RegExMatch(name, "Button\d?$")
        return "Mouse"
    if RegExMatch(name, "^(Media_|Volume_)")
        return "Media"
    if RegExMatch(name, "^Browser_")
        return "Browser"
    switch name {
        case "Escape", "AppsKey", "PrintScreen", "Pause", "ScrollLock", "CapsLock":
            return "System"
        case "Tab", "Enter", "Space", "Backspace", "Delete", "Insert":
            return "Editing"
        case "PgUp", "PgDn", "Home", "End", "Up", "Down", "Left", "Right":
            return "Navigation"
    }
    return ""
}

; Test keeps the previous behavior: run the command / send the
; output once (no repeat-while-held), guarded.
TestRemap(ctrl, *) {
    g := ctrl.Gui
    ; trigger composition: Hotkey | Hotstring | Pixel
    trig := g["Trig"].Text
    key := ""
    if (trig = "Hotkey") {
        key := NormalizeKey(g["KeyEdit"].Value)
        if (key = "") {
            MsgBox("Invalid key format.", "Error", "Icon!")
            return
        }
    } else if (trig = "Hotstring") {
        hsTxt := RegExReplace(Trim(g["KeyEdit"].Value), "i)^hs:")
        ; ; and | cannot survive the cfg grammar, [ and ] would be
        ; parsed back as a window scope on reload - reject all five
        if (hsTxt = "" || InStr(hsTxt, ";") || InStr(hsTxt, "|") || InStr(hsTxt, "[") || InStr(hsTxt, "]")) {
            MsgBox("Hotstring text cannot be empty or contain special characters", "Error", "Icon!")
            return
        }
        key := "hs:" hsTxt
    } else {
        pxX := Trim(g["PX"].Value)
        pxY := Trim(g["PY"].Value)
        pxC := StrUpper(Trim(g["PC"].Value))
        pxM := (g["PM"].Value = 2) ? "from" : "to"
        pxOk := true
        try {
            if (Integer(pxX) < 0 || Integer(pxY) < 0)
                pxOk := false   ; negative coordinates are off-screen
        } catch as ErrP {
            pxOk := false
        }
        if (pxOk && !RegExMatch(pxC, "^[0-9A-F]{6}$"))
            pxOk := false
        if !pxOk {
            MsgBox("Pixel trigger needs non-negative integer X/Y and a 6-digit hex color.", "Error", "Icon!")
            return
        }
        key := "px:" Integer(pxX) "," Integer(pxY) "," pxC "," pxM
    }
    action := Trim(g["Action"].Value)
    if (action = "")
        return
    isCmd := (g["Type"].Text != "Key Remap")
    if (isCmd)
        ; match EditorSave: one binding per line (security review F10)
        action := StrReplace(StrReplace(action, "`r`n", " "), "`n", " ")
    try {
        if (isCmd)
            Run(A_ComSpec " /c " action, , "Hide")
        else {
            out := BuildKeyOutput(ResolveKeyAction(NormalizeAction(action)))
            if (out != "")
                Send(out)
        }
    } catch as Err {
        LogError("test failed: " Err.Message)
        SetStatus("Test failed - see error log")
    }
}

; Editor Save with conflict detection (feature 5):
; - same id in the active profile (and not the edited one) -> overwrite prompt
; - same Key+Scope in the OTHER type -> "later registration wins" warning
; Edit mode updates the same bindingId (re-register); Add mode
; registers enabled. st is this dialog's own state (Bound in
; OpenEditor - review finding 4).
EditorSave(st, ctrl, *) {
    g := ctrl.Gui
    type := (g["Type"].Text = "Key Remap") ? "key" : "cmd"
    ; trigger composition: Hotkey | Hotstring | Pixel
    trig := g["Trig"].Text
    key := ""
    icp := ""
    if (trig = "Hotkey") {
        key := NormalizeKey(g["KeyEdit"].Value)
        if (key = "") {
            MsgBox("Invalid key format.", "Error", "Icon!")
            return
        }
        icp := IcpFromLabel(g["Icp"].Text)
    } else if (trig = "Hotstring") {
        hsTxt := RegExReplace(Trim(g["KeyEdit"].Value), "i)^hs:")
        ; ; and | cannot survive the cfg grammar, [ and ] would be
        ; parsed back as a window scope on reload - reject all five
        if (hsTxt = "" || InStr(hsTxt, ";") || InStr(hsTxt, "|") || InStr(hsTxt, "[") || InStr(hsTxt, "]")) {
            MsgBox("Hotstring text cannot be empty or contain special characters", "Error", "Icon!")
            return
        }
        key := "hs:" hsTxt
    } else {
        pxX := Trim(g["PX"].Value)
        pxY := Trim(g["PY"].Value)
        pxC := StrUpper(Trim(g["PC"].Value))
        pxM := (g["PM"].Value = 2) ? "from" : "to"
        pxOk := true
        try {
            if (Integer(pxX) < 0 || Integer(pxY) < 0)
                pxOk := false   ; negative coordinates are off-screen
        } catch as ErrP {
            pxOk := false
        }
        if (pxOk && !RegExMatch(pxC, "^[0-9A-F]{6}$"))
            pxOk := false
        if !pxOk {
            MsgBox("Pixel trigger needs non-negative integer X/Y and a 6-digit hex color.", "Error", "Icon!")
            return
        }
        key := "px:" Integer(pxX) "," Integer(pxY) "," pxC "," pxM
    }
    action := Trim(g["Action"].Value)
    if (action = "") {
        MsgBox("Action cannot be empty.", "Error", "Icon!")
        return
    }
    if (type = "cmd") {
        ; one binding per line: collapse newlines from the Multi edit
        action := StrReplace(StrReplace(action, "`r`n", " "), "`n", " ")
    } else {
        action := NormalizeAction(action)
    }
    scope := Trim(g["ScopeEdit"].Value)
    ; ! Scope chars that cannot round-trip through keybinds.cfg would
    ;   silently drop the binding on the next load - rejected at edit
    ;   time instead (security review F6).
    if RegExMatch(scope, "[\[\];]") {
        MsgBox("Window scope cannot contain '[', ']' or ';'.`n`nThose characters cannot be stored in keybinds.cfg.", "Error", "Icon!")
        return
    }
    newId := type "|" key "|" scope
    profile := ActiveProfileMap()
    if (profile.Has(newId) && newId != st["OrigId"]) {
        if (MsgBox("This key is already bound in this profile with the same window scope.`nOverwrite the existing binding?"
                , App.Name, "YesNo Icon! Default2") != "Yes")
            return
    }
    otherId := ((type = "cmd") ? "key" : "cmd") "|" key "|" scope
    if (profile.Has(otherId) && otherId != st["OrigId"]) {
        otherLbl := (type = "cmd") ? "key remap" : "command"
        if (MsgBox("Note: this key is also registered as a " otherLbl " binding with the same window scope.`n"
                . "Only the later registration will respond.`n`nContinue anyway?"
                , App.Name, "YesNo Icon! Default2") != "Yes")
            return
    }
    PushUndo()
    if (st["Mode"] = "Edit" && st["OrigId"] != "" && st["OrigId"] != newId)
        RemoveBinding(st["OrigId"])
    enabled := true
    if (st["Mode"] = "Edit" && st["OrigId"] = newId) {
        ob := GetBinding(newId)
        if IsObject(ob)
            enabled := ob["Enabled"]
    }
    RegHotkey(type, key, scope, action, enabled, icp)
    SetDirty()
    RefreshGuiData()
    g.Destroy()
    SetStatus((st["Mode"] = "Edit" ? "Updated" : "Added") " binding: " key)
}

; =============================================================
; 9c. Macros tab (user request): the macro library.
; Macros are Send-syntax sequences stored PER PROFILE (macro: lines
; inside the profile sections of keybinds.cfg) and referenced by key
; bindings as macro:Name. A legacy [Macros] section is still READ
; into Default on load, but never written back.
; =============================================================

; Name of the selected macro row ("" when none).
MacroSelectedName() {
    row := App.LV_Macros.GetNext(0)
    if (row = 0)
        return ""
    name := ""
    try name := App.LV_Macros.GetText(row, 1)
    return name
}

; Fill the macro library list: name, character count, 60-char preview.
FillMacroList() {
    if !IsObject(App.LV_Macros)
        return
    App.LV_Macros.Opt("-Redraw")
    App.LV_Macros.Delete()
    shownMac := 0
    for name, seq in App.MacroLib {
        App.LV_Macros.Add("", name, StrLen(seq), SubStr(seq, 1, 60))
        shownMac++
    }
    App.LV_Macros.Opt("+Redraw")
    ; empty state: centered overlay hint (mirrors the binding lists)
    if App.Ui.Has("EmptyMac")
        App.Ui["EmptyMac"].Visible := (shownMac = 0)
}

MacroEditSelected(*) {
    name := MacroSelectedName()
    if (name = "") {
        SetStatus("Select a macro first")
        return
    }
    seq := App.MacroLib.Has(name) ? App.MacroLib[name] : ""
    if IsStructuredMacro(seq)
        OpenMacroBuilder(name, seq)
    else
        OpenMacroEditor("Edit", name)
}

MacroDoubleClick(ctrl, info, *) {
    if (info = 0)
        return
    try {
        name := ctrl.GetText(info, 1)
        seq := App.MacroLib.Has(name) ? App.MacroLib[name] : ""
        ; structured (builder) macros open in the builder, plain
        ; Send-string macros in the simple sequence dialog
        if IsStructuredMacro(seq)
            OpenMacroBuilder(name, seq)
        else
            OpenMacroEditor("Edit", name)
    }
}

MacroDeleteSelected(*) {
    name := MacroSelectedName()
    if (name = "") {
        SetStatus("Select a macro first")
        return
    }
    if (MsgBox("Delete macro '" name "'?", App.Name, "YesNo Icon! Default2") != "Yes")
        return
    PushUndo()
    App.MacroLib.Delete(name)
    SetDirty()
    RefreshGuiData()
    SetStatus("Macro '" name "' deleted")
}

; Run once: sends the sequence to the ACTIVE window (like the
; binding editor's Test button).
MacroRunSelected(*) {
    name := MacroSelectedName()
    if (name = "") {
        SetStatus("Select a macro first")
        return
    }
    if !App.MacroLib.Has(name) {
        SetStatus("Macro not found: " name)
        return
    }
    seq := App.MacroLib[name]
    try {
        if IsStructuredMacro(seq)
            RunMacroSequence(seq)
        else
            Send(BuildKeyOutput(seq))
    } catch as Err {
        LogError("macro run '" name "': " Err.Message)
        SetStatus("Macro run failed - see error log")
    }
}

MacroAssignSelected(*) {
    name := MacroSelectedName()
    if (name = "") {
        SetStatus("Select a macro first")
        return
    }
    OpenEditor("Add", "", Map("Type", "key", "Action", "macro:" name))
}

; Macro edit dialog (New/Edit). The save handler receives the mode
; and original name via Bind (same pattern as the binding editor).
OpenMacroEditor(mode, name) {
    seq := ""
    if (mode = "Edit" && App.MacroLib.Has(name)) {
        seq := App.MacroLib[name]
    } else {
        mode := "New"
        name := ""
    }
    med := Gui("-MaximizeBox +Owner" App.MainGui.Hwnd " +OwnDialogs", App.Name " - Macro")
    med.BackColor := App.Theme["Background"]
    med.SetFont("s10 c" App.Theme["Text"], "Segoe UI")
    med.Add("Text", "x16 y18 w66 h22", "Name:")
    med.Add("Edit", "x86 y16 w220 h22 vMName c" App.Theme["Text"] " +Background" App.Theme["Control"], name)
    med.Add("Text", "x16 y54 w340 h22", "Sequence (Send syntax, e.g. {Enter}hello{Enter}):")
    med.Add("Edit", "x16 y78 w330 h150 Multi vMSeq c" App.Theme["Text"] " +Background" App.Theme["Control"], seq)
    saveBtn := med.Add("Button", "x86 y248 w90 h28" BtnBg(), "Save")
    saveBtn.OnEvent("Click", MacroSave.Bind(mode, name))
    cancelBtn := med.Add("Button", "x196 y248 w90 h28" BtnBg(), "Cancel")
    cancelBtn.OnEvent("Click", (*) => med.Destroy())
    med.Show("w362 h300")
}

MacroSave(mode, origName, ctrl, *) {
    g := ctrl.Gui
    mname := Trim(g["MName"].Value)
    seq := Trim(g["MSeq"].Value)
    if (mname = "" || InStr(mname, ";") || InStr(mname, "[") || InStr(mname, "]") || InStr(mname, "*") || InStr(mname, "|")) {
        MsgBox("Macro name cannot be empty or contain special characters", "Error", "Icon!")
        return
    }
    if (seq = "") {
        MsgBox("Sequence cannot be empty.", "Error", "Icon!")
        return
    }
    ; ! line breaks cannot round-trip through keybinds.cfg (one line
    ;   = one entry) - point at {Enter} instead of corrupting the file
    if (InStr(seq, "`n") || InStr(seq, "`r")) {
        MsgBox("The sequence cannot contain line breaks.`nUse {Enter} where a newline should be sent.", "Error", "Icon!")
        return
    }
    ; overwrite / rename-target prompt (mode and origName arrive bound)
    if (App.MacroLib.Has(mname) && (mode = "New" || mname != origName)) {
        if (MsgBox("Macro '" mname "' already exists. Overwrite?", App.Name, "YesNo Icon! Default2") != "Yes")
            return
    }
    PushUndo()
    if (mname != origName && App.MacroLib.Has(origName))
        App.MacroLib.Delete(origName)
    App.MacroLib[mname] := seq
    SetDirty()
    RefreshGuiData()
    g.Destroy()
    SetStatus("Macro '" mname "' saved")
}

; =============================================================
; 9d. Structured macro engine + Macro Builder (user request)
;
; A STRUCTURED macro is a "|"-separated token sequence stored in the
; active profile's macro library like any other macro:
;   trg:press|release|repeat  - trigger mode (default press)
;   rbuf:ms / rdel:ms         - repeat-mode buffer/delay
;   px:x,y,RRGGBB,to|from     - PIXEL trigger (watcher fires it)
;   kd:Key / ku:Key / kp:Key  - key down / up / press
;   w:ms                      - wait
;   run:command               - shell command (selected shell, hidden)
;   mm:x,y,rel|abs[,hold:Key] - mouse move, optionally holding a
;                               key or button during the move
;   loop:N ... endloop        - repeat part of the sequence
; A literal "|" inside a parameter is stored as {PIPE}.
; =============================================================

; Structured = contains the token separator AND starts with a token.
IsStructuredMacro(s) {
    return InStr(s, "|") && RegExMatch(s, "i)^[a-z]+:")
}

; Header tokens (trg:/rbuf:/rdel:) -> {Mode, Buf, Del}.
; ! NEVER throws: a hand-edited cfg can carry "rbuf:abcd" / "rdel:-13"
;   / an unknown mode - bad numbers read as 0, negatives clamp to 0,
;   unknown modes fall back to "press" (this also runs inside hotkey
;   registration: WantsKeyUpVariant -> EnsureUpVariant).
ParseMacroHeader(seq) {
    mode := "press", rbuf := 0, rdel := 0
    for , tok in StrSplit(seq, "|") {
        if (SubStr(tok, 1, 4) = "trg:") {
            m := StrLower(SubStr(tok, 5))
            if (m = "release" || m = "repeat" || m = "pixel")
                mode := m
        } else if (SubStr(tok, 1, 5) = "rbuf:")
            rbuf := SafeInt(SubStr(tok, 6), 0)
        else if (SubStr(tok, 1, 5) = "rdel:")
            rdel := SafeInt(SubStr(tok, 6), 0)
    }
    if (rbuf < 0)
        rbuf := 0
    if (rdel < 0)
        rdel := 0
    return {Mode: mode, Buf: rbuf, Del: rdel}
}

; Execute a structured macro sequence: loop-stack interpreter with a
; runaway-loop safety valve. Header tokens are skipped.
RunMacroSequence(seq) {
    toks := StrSplit(seq, "|")
    pos := 1
    stack := []
    actions := 0
    Loop {
        if (pos > toks.Length)
            break
        tok := toks[pos]
        pos++
        if (SubStr(tok, 1, 4) = "trg:" || SubStr(tok, 1, 5) = "rbuf:" || SubStr(tok, 1, 5) = "rdel:" || SubStr(tok, 1, 3) = "px:")
            continue
        if (SubStr(tok, 1, 7) = "endloop") {
            ; endloop or endloop:Name (named loops; save validates
            ; that the name matches the innermost open loop)
            if (stack.Length > 0) {
                top := stack[stack.Length]
                top.Count--
                if (top.Count > 0)
                    pos := top.Start
                else
                    stack.Pop()
            }
            continue
        }
        if (SubStr(tok, 1, 5) = "loop:") {
            ; loop:Name:Count (builder) or loop:Count (legacy)
            lp := StrSplit(tok, ":")
            cnt := 1
            if (lp.Length >= 3) {
                try cnt := Integer(lp[3])
            } else {
                try cnt := Integer(lp[2])
            }
            if (cnt < 1)
                cnt := 1
            stack.Push({Count: cnt, Start: pos})
            continue
        }
        try ExecuteMacroToken(tok)
        catch as Err {
            LogError("macro token '" tok "': " Err.Message)
            SetStatus("Macro action failed - see error log")
        }
        actions++
        ; * runaway-loop safety valve: a hand-edited loop count can
        ;   never hang the script
        if (actions > 100000) {
            LogError("macro aborted after 100000 actions (runaway loop?)")
            SetStatus("Macro aborted - see error log")
            break
        }
    }
}

; One action token -> its side effect.
ExecuteMacroToken(tok) {
    c := InStr(tok, ":")
    if (c = 0)
        return
    op := StrLower(SubStr(tok, 1, c - 1))
    arg := StrReplace(SubStr(tok, c + 1), "{PIPE}", "|")
    switch op {
        case "kp":
            ; kp:Key[:holdMs] - a hold duration inserts the wait
            ; between the key-down and the key-up (user request)
            kp := StrSplit(tok, ":")
            if (kp.Length >= 3) {
                holdMs := 0
                try holdMs := Integer(kp[3])
                if (holdMs > 0) {
                    Send("{" arg " down}")
                    Sleep(holdMs)
                    Send("{" arg " up}")
                    return
                }
            }
            if (InStr(arg, "{") || RegExMatch(arg, "[\^!+#]"))
                Send(arg)
            else
                Send("{" arg "}")
        case "kd":
            Send("{" arg " down}")
        case "ku":
            Send("{" arg " up}")
        case "w":
            ms := SafeInt(arg, 0)   ; hand-edited token: "abcd" waits 0
            if (ms < 0)
                ms := 0
            Sleep(ms)
        case "run":
            RunViaShell(GetShellById(App.Settings["ShellCmd"]), arg, "Hide")
        case "rw":
            ; run and WAIT for the command to finish before the next
            ; action (action-dialog "Wait until return" toggle)
            sh := GetShellById(App.Settings["ShellCmd"])
            if (sh["Family"] = "ps")
                RunWait('"' sh["Path"] '" -NoProfile -Command ' arg, , "Hide")
            else if (sh["Family"] = "posix")
                RunWait('"' sh["Path"] '" -c "' EscapePosixQuotes(arg) '"', , "Hide")
            else
                RunWait(A_ComSpec " /c " arg, , "Hide")
        case "sq":
            ; inline Send-syntax sequence (the old plain-macro editor,
            ; now a builder action - user request)
            Send(arg)
        case "mm":
            p := StrSplit(arg, ",")
            if (p.Length < 2)
                return
            hold := ""
            if (p.Length >= 4 && SubStr(p[4], 1, 5) = "hold:")
                hold := SubStr(p[4], 6)
            rel := (p.Length >= 3 && StrLower(p[3]) = "rel") ? "R" : ""
            if (hold != "")
                Send("{" hold " down}")
            MouseMove(Integer(p[1]), Integer(p[2]), , rel)
            if (hold != "")
                Send("{" hold " up}")
    }
}

; ---- key-up variants (release-trigger macros) ----

; Worker for the "key up" hotkey variant: fires release-mode
; structured macros only.
BindKeyUp(id, *) {
    b := GetBinding(id)
    if !IsObject(b)
        return
    action := ResolveKeyAction(b["Action"])
    if (action = "" || !IsStructuredMacro(action))
        return
    if (ParseMacroHeader(action).Mode != "release")
        return
    RunMacroSequence(action)
}

; Dispatcher for the up-variant (parallel to BindingDispatch).
UpDispatch(key, scope, *) {
    id := EffectiveBindingId(key, scope)
    if (id != "")
        BindKeyUp(id)
}

; Does any enabled binding for this Key+Scope resolve to a
; release-mode structured macro?
WantsKeyUpVariant(key, scope) {
    for , b in ActiveProfileMap() {
        if (b["Key"] != key || b["Scope"] != scope || !b["Enabled"])
            continue
        resolved := ResolveKeyAction(b["Action"])
        if (resolved = "" || !IsStructuredMacro(resolved))
            continue
        if (ParseMacroHeader(resolved).Mode = "release")
            return true
    }
    return false
}

; Register/reconcile the "key up" variant: created only when a
; release-trigger macro is (effectively) bound to this key+scope.
EnsureUpVariant(key, scope, icp) {
    vkey := key "|" scope
    want := WantsKeyUpVariant(key, scope)
    if (want && !App.UpHotkeys.Has(vkey)) {
        fn := UpDispatch.Bind(key, scope)
        App.UpHotkeys[vkey] := fn
        if (scope != "")
            HotIfWinActive(scope)
        else
            HotIf()
        try Hotkey(HkVariantName(key, icp) " up", fn, "On")
        catch as Err {
            LogError("register key-up " key ": " Err.Message)
            App.UpHotkeys.Delete(vkey)
        }
        HotIf()
    } else if (App.UpHotkeys.Has(vkey)) {
        if (scope != "")
            HotIfWinActive(scope)
        else
            HotIf()
        try Hotkey(HkVariantName(key, icp) " up", , want ? "On" : "Off")
        catch as Err {
            LogError("toggle key-up " key ": " Err.Message)
        }
        HotIf()
    }
}

; ---- pixel triggers ----

; Rebuild the watcher list from px: headers in the macro library.
; Called from RefreshGuiData; a single shared timer polls the set.
RebuildPixelWatchers() {
    static coordDone := false
    if !coordDone {
        coordDone := true
        try CoordMode("Pixel", "Screen")
    }
    if (App.Suspended) {
        App.PixelWatchers := []   ; suspended: no polling until unsuspended
        return
    }
    prev := App.PixelWatchers   ; fire/dead state carried across the rebuild
    App.PixelWatchers := []
    for name, seq in App.MacroLib {
        for , tok in StrSplit(seq, "|") {
            if (SubStr(tok, 1, 3) != "px:")
                continue
            p := StrSplit(SubStr(tok, 4), ",")
            if (p.Length < 4)
                continue
            try {
                App.PixelWatchers.Push({Name: name, Kind: "macro", X: Integer(p[1]), Y: Integer(p[2])
                    , Color: StrUpper(p[3]), Mode: StrLower(p[4]), Seq: seq
                    , Fired: false, Dead: false})
            } catch as Err {
                LogError("pixel trigger '" name "': " Err.Message)
            }
        }
    }
    ; px: command bindings are watchers too
    for id, b in ActiveProfileMap() {
        if (SubStr(b["Key"], 1, 3) != "px:" || !b["Enabled"])
            continue
        p := StrSplit(SubStr(b["Key"], 4), ",")
        if (p.Length < 4)
            continue
        try {
            App.PixelWatchers.Push({Name: id, Kind: "binding", Id: id, X: Integer(p[1]), Y: Integer(p[2])
                , Color: StrUpper(p[3]), Mode: StrLower(p[4])
                , Fired: false, Dead: false})
        } catch as Err {
            LogError("pixel binding trigger: " Err.Message)
        }
    }
    ; * carry the fire/dead state of identical watchers: a plain UI
    ;   refresh (filter typing, toggles) must not re-trigger a watcher
    ;   that already fired - "fires once per transition" must hold
    for , nw in App.PixelWatchers {
        for , ow in prev {
            if (nw.Kind = ow.Kind && nw.Name = ow.Name && nw.X = ow.X && nw.Y = ow.Y
                    && nw.Color = ow.Color && nw.Mode = ow.Mode) {
                nw.Fired := ow.Fired
                nw.Dead := ow.Dead
                break
            }
        }
    }
    if (App.PixelWatchers.Length > 0)
        SetTimer(PixelWatchTick, -200)
}

; Poll every live watcher; fire its macro on the color transition.
; A watcher whose PixelGetColor fails (e.g. unsupported platform)
; disables itself after logging once.
; ? pixel capture is unavailable on some Wayland compositors - the
;   self-disable is the documented degradation, not an error
PixelWatchTick() {
    live := 0
    for , w in App.PixelWatchers {
        if w.Dead
            continue
        live++
        try {
            got := StrUpper(StrReplace(PixelGetColor(w.X, w.Y), "0x", ""))
            hit := (w.Mode = "to") ? (got = w.Color) : (got != w.Color)
            if (hit && !w.Fired) {
                w.Fired := true
                if (w.Kind = "binding")
                    HsDispatch(w.Id)
                else
                    RunMacroSequence(w.Seq)
            } else if (!hit) {
                w.Fired := false
            }
        } catch as Err {
            w.Dead := true
            LogError("pixel trigger '" w.Name "' disabled: " Err.Message)
        }
    }
    if (live > 0)
        SetTimer(PixelWatchTick, -200)
}

; ---- Macro Builder GUI (single-instance, destroy-on-close, ----
;      rebuilt on demand) ----

; Close the builder: destroy it AND its action dialog so no orphaned
; child window survives (user report); App.BuilderGui is cleared so
; the next open rebuilds fresh.
BuilderWinClose(bd, *) {
    CloseActionDialog()
    try bd.Destroy()
    App.BuilderGui := 0
}

CloseActionDialog() {
    if IsObject(App.ActionDlgGui) {
        try App.ActionDlgGui.Destroy()
    }
    App.ActionDlgGui := 0
}

; Show/hide a set of controls in the action dialog (per-type groups).
AShowVis(g, on, names) {
    for , n in names {
        try g[n].Visible := on
    }
}

; Fill the builder ListView from App.BuilderRows.
FillBuilderList() {
    if !IsObject(App.BuilderGui)
        return
    lv := App.BuilderGui["BLV"]
    lv.Opt("-Redraw")
    lv.Delete()
    for i, r in App.BuilderRows {
        d := TokenDisplay(r.Tok)
        lv.Add("", i, d[1], d[2], d[3])
    }
    lv.Opt("+Redraw")
    ; empty state: centered overlay hint (mirrors the main lists)
    try App.BuilderGui["EmptyBld"].Visible := (App.BuilderRows.Length = 0)
    catch as Err {
        LogError("builder empty hint: " Err.Message)
    }
}

; Token -> [Action, Value, Detail] display columns.
TokenDisplay(tok) {
    parts := StrSplit(tok, ":")
    op := StrLower(parts[1])
    arg := ""
    if (parts.Length >= 2)
        arg := StrReplace(parts[2], "{PIPE}", "|")
    switch op {
        case "kp":
            hold := (parts.Length >= 3) ? ("hold " parts[3] " ms") : ""
            return ["Key press", arg, hold]
        case "kd": return ["Key down", arg, ""]
        case "ku": return ["Key up", arg, ""]
        case "w": return ["Wait", arg " ms", ""]
        case "run": return ["Run command", SubStr(arg, 1, 50), ""]
        case "sq": return ["Sequence", SubStr(arg, 1, 50), ""]
        case "rw": return ["Run command", SubStr(arg, 1, 50), "waits for return"]
        case "mm":
            p := StrSplit(StrReplace(SubStr(tok, 4), "{PIPE}", "|"), ",")
            if (p.Length < 2)   ; hand-edited "mm:5" must not crash the list
                return ["Mouse move", "(malformed)", ""]
            d := (p.Length >= 3 && StrLower(p[3]) = "rel") ? "relative" : "absolute"
            if (p.Length >= 4 && SubStr(p[4], 1, 5) = "hold:")
                d .= ", holding " SubStr(p[4], 6)
            return ["Mouse move", p[1] "," p[2], d]
        case "loop":
            nm := (parts.Length >= 3) ? parts[2] : ""
            cnt := (parts.Length >= 3) ? parts[3] : (parts.Length >= 2 ? parts[2] : "?")
            return ["Loop start", nm, cnt " times"]
        case "endloop":
            nm := (parts.Length >= 2) ? parts[2] : ""
            return ["Loop end", nm, ""]
    }
    return [tok, "", ""]
}

BuilderSelRow() {
    if !IsObject(App.BuilderGui)
        return 0
    return App.BuilderGui["BLV"].GetNext(0)
}

; "Builder..." on the Macros tab: create a new structured macro.
MacroNewStructured(*) {
    OpenMacroBuilder("", "")
}

; Open the single-instance builder (rebuilt after a close). seq = "" starts empty.
OpenMacroBuilder(name, seq) {
    if !IsObject(App.BuilderGui)
        BuildBuilderWindow()
    bd := App.BuilderGui
    App.BuilderRows := []
    hdr := ParseMacroHeader(seq)
    pxX := "", pxY := "", pxColor := "", pxModeIdx := 1
    if (seq != "") {
        for , tok in StrSplit(seq, "|") {
            if (SubStr(tok, 1, 4) = "trg:")
                continue
            if (SubStr(tok, 1, 5) = "rbuf:" || SubStr(tok, 1, 5) = "rdel:")
                continue
            if (SubStr(tok, 1, 3) = "px:") {
                p := StrSplit(SubStr(tok, 4), ",")
                if (p.Length >= 3) {
                    pxX := p[1]
                    pxY := p[2]
                    pxColor := p[3]
                }
                if (p.Length >= 4 && StrLower(p[4]) = "from")
                    pxModeIdx := 2
                continue
            }
            if (tok != "")
                App.BuilderRows.Push({Tok: tok})
        }
    }
    if (name = "") {
        mn := 1
        Loop {
            cand := "Macro" mn
            taken := false
            for k, v in App.MacroLib {
                if (k = cand)
                    taken := true
            }
            if !taken {
                name := cand
                break
            }
            mn++
        }
    }
    bd["BName"].Value := name
    trigIdx := (hdr.Mode = "release") ? 2 : (hdr.Mode = "repeat") ? 3 : (hdr.Mode = "pixel") ? 4 : 1
    bd["BTrig"].Choose(trigIdx)
    bd["BBuf"].Value := hdr.Buf
    bd["BDelay"].Value := hdr.Del
    bd["BPX"].Value := (pxX = "") ? 0 : pxX
    bd["BPY"].Value := (pxY = "") ? 0 : pxY
    bd["BPColor"].Value := (pxColor = "") ? "FFFFFF" : pxColor
    bd["BPMode"].Choose(pxModeIdx)
    FillBuilderList()
    bd.Show("w820 h536")
}

; Build the builder window (once per open; BuilderWinClose destroys it).
BuildBuilderWindow() {
    bd := Gui("-MaximizeBox +OwnDialogs", App.Name " - Macro Builder")
    App.BuilderGui := bd
    bd.BackColor := App.Theme["Background"]
    ThemedFont(bd, "s10 c" App.Theme["Text"])
    bd.Add("Text", "x16 y22 w50 h22", "Name:")
    bd.Add("Edit", "x70 y20 w200 h22 vBName c" App.Theme["Text"] " +Background" App.Theme["Control"], "")
    bd.Add("Text", "x286 y22 w60 h22", "Trigger:")
    bd.Add("DDL", "x352 y20 w170 vBTrig Choose1", ["On key press", "On key release", "Repeat while held", "Pixel watch"])
    bd.Add("Text", "x16 y72 w60 h22", "Buf ms:")
    bd.Add("Edit", "x80 y70 w60 h22 vBBuf c" App.Theme["Text"] " +Background" App.Theme["Control"], 0)
    bd.Add("Text", "x150 y72 w60 h22", "Delay ms:")
    bd.Add("Edit", "x214 y70 w60 h22 vBDelay c" App.Theme["Text"] " +Background" App.Theme["Control"], 0)
    bd.Add("Text", "x16 y116 w60 h22", "Pixel X:")
    bd.Add("Edit", "x80 y114 w60 h22 vBPX c" App.Theme["Text"] " +Background" App.Theme["Control"], "")
    bd.Add("Text", "x146 y116 w20 h22", "Y:")
    bd.Add("Edit", "x170 y114 w60 h22 vBPY c" App.Theme["Text"] " +Background" App.Theme["Control"], "")
    bd.Add("Text", "x236 y116 w46 h22", "Color:")
    bd.Add("Edit", "x284 y114 w70 h22 vBPColor c" App.Theme["Text"] " +Background" App.Theme["Control"], "")
    bd.Add("DDL", "x360 y114 w130 vBPMode Choose1", ["turns to", "turns from"])
    ; Test run lives on the header row now (right side margin, wider
    ; than the old bottom-row button, which is Clone)
    hdrTestBtn := bd.Add("Button", "x704 y110 w100 h28 vBTest" BtnBg(), "Test run")
    hdrTestBtn.OnEvent("Click", BuilderTest)
    bd.Add("ListView", "x16 y164 w788 h278 vBLV NoSortHdr +Background" App.Theme["Background"]
        , ["#", "Action", "Value", "Detail"])
    lvb := bd["BLV"]
    lvb.ModifyCol(1, 44)
    lvb.ModifyCol(2, 120)
    lvb.ModifyCol(3, 300)
    lvb.ModifyCol(4, 788 - 44 - 120 - 300 - 8)
    lvb.OnEvent("DoubleClick", BuilderRowDouble)
    ; empty-state hint, centered over the action list (16+(788-220)/2, 164+278/2-11)
    bd.Add("Text", "x" (16 + (788 - 220) // 2) " y" (164 + (278 // 2) - 11) " w220 h22 vEmptyBld c" App.Theme["Hint"] " +BackgroundTrans Center"
        , "No actions yet - press Add action...")
    bd["EmptyBld"].Visible := false
    addBtn := bd.Add("Button", "x16 y502 w110 h28 vBAdd" BtnBg(), "Add action...")
    addBtn.OnEvent("Click", (*) => OpenActionDialog(0))
    editBtn := bd.Add("Button", "x136 y502 w110 h28 vBEdit" BtnBg(), "Edit action...")
    editBtn.OnEvent("Click", BuilderEditAction)
    delBtn := bd.Add("Button", "x256 y502 w88 h28 vBDelBtn" BtnBg(), "Delete")
    delBtn.OnEvent("Click", BuilderDeleteAction)
    upBtn := bd.Add("Button", "x354 y502 w60 h28 vBUp" BtnBg(), "Up")
    upBtn.OnEvent("Click", BuilderMove.Bind(-1))
    downBtn := bd.Add("Button", "x444 y502 w60 h28 vBDown" BtnBg(), "Down")
    downBtn.OnEvent("Click", BuilderMove.Bind(1))
    cloneBtn := bd.Add("Button", "x534 y502 w84 h28 vBClone" BtnBg(), "Clone")
    cloneBtn.OnEvent("Click", BuilderCloneAction)
    saveBtn := bd.Add("Button", "x628 y502 w84 h28 vBSave" BtnBg(), "Save")
    saveBtn.OnEvent("Click", BuilderSave)
    cancelBtn := bd.Add("Button", "x722 y502 w72 h28 vBCancel" BtnBg(), "Cancel")
    cancelBtn.OnEvent("Click", BuilderWinClose.Bind(bd))
    bd.OnEvent("Close", BuilderWinClose.Bind(bd))
    bd.OnEvent("Escape", BuilderWinClose.Bind(bd))
    bd.OnEvent("Size", BuilderSize)
    bd.Show("w820 h536")
}

; Builder resize - the main window's GuiSize pattern: event-driven,
; Ctrl.Move with omitted params, per-section try/catch. LV anchored
; top-left expanding right/down; the button row rides the bottom
; margin like the main Exit button.
; ? the .ks twin is reported not to apply under GTK (see the
;   "total_hours_wasted_here" note in rebindx.ks)
BuilderSize(bd, minMax, w, h) {
    if (minMax = 1)
        return
    if (w < 340 || h < 250)
        return
    try {
        lvH2 := h - 28 - 6 - 164 - 10
        bd["BLV"].Move(, , w - 32, lvH2)
        bd["EmptyBld"].Move(16 + ((w - 32) - 220) // 2, 164 + (lvH2 // 2) - 11, 220, 22)
    } catch as ErrL {
        LogError("builder list resize: " ErrL.Message)
    }
    try {
        btnY := h - 28 - 6
        for , n in ["BAdd", "BEdit", "BDelBtn", "BUp", "BDown", "BClone", "BSave", "BCancel"]
            bd[n].Move(, btnY)
    } catch as ErrB {
        LogError("builder buttons resize: " ErrB.Message)
    }
}

; Double-click an action row = edit it in the action dialog.
BuilderRowDouble(ctrl, info, *) {
    if (info = 0)
        return
    OpenActionDialog(info)
}

BuilderEditAction(*) {
    row := BuilderSelRow()
    if (row = 0) {
        SetStatus("Select an action first")
        return
    }
    OpenActionDialog(row)
}

BuilderDeleteAction(*) {
    row := BuilderSelRow()
    if (row = 0) {
        SetStatus("Select an action first")
        return
    }
    App.BuilderRows.RemoveAt(row)
    FillBuilderList()
}

; Move the selected action up (-1) or down (+1).
BuilderMove(delta, *) {
    row := BuilderSelRow()
    if (row = 0) {
        SetStatus("Select an action first")
        return
    }
    target := row + delta
    if (target < 1 || target > App.BuilderRows.Length)
        return
    moved := App.BuilderRows[row]
    App.BuilderRows.RemoveAt(row)
    App.BuilderRows.InsertAt(target, moved)
    FillBuilderList()
}

; Clone the SELECTED action(s): one row duplicates right after
; itself; a multi-selection pastes (in order) after the LAST
; selected row - one function covers both cases. The selection
; moves onto the clones so repeated presses compound.
BuilderCloneAction(*) {
    if !IsObject(App.BuilderGui)
        return
    lv := App.BuilderGui["BLV"]
    rows := []
    row := lv.GetNext(0)
    while (row != 0) {
        rows.Push(row)
        row := lv.GetNext(row)
    }
    if (rows.Length = 0) {
        SetStatus("Select an action first")
        return
    }
    ; snapshot the tokens BEFORE any insert shifts the indices
    toks := []
    for , r in rows
        toks.Push(App.BuilderRows[r].Tok)
    pos := rows[rows.Length]
    for , tok in toks {
        App.BuilderRows.InsertAt(pos + 1, {Tok: tok})
        pos++
    }
    FillBuilderList()
    ; move the selection onto the clones (guarded: a Keysharp LV
    ; Modify quirk must never break the clone itself)
    try {
        lv.Modify(0, "-Select")
        i := rows[rows.Length] + 1
        while (i <= rows[rows.Length] + toks.Length) {
            lv.Modify(i, "Select")
            i++
        }
    }
    catch as Err {
        LogError("clone selection: " Err.Message)
    }
    SetStatus("Cloned " toks.Length " action(s)")
}

; Test: execute the current rows as a sequence (header ignored).
BuilderTest(*) {
    if (App.BuilderRows.Length = 0) {
        SetStatus("No actions to test")
        return
    }
    seq := ""
    for i, r in App.BuilderRows
        seq .= r.Tok (i < App.BuilderRows.Length ? "|" : "")
    RunMacroSequence(seq)
    SetStatus("Test run finished")
}

BuilderSave(*) {
    g := App.BuilderGui
    if !IsObject(g)
        return
    mname := Trim(g["BName"].Value)
    if (mname = "" || InStr(mname, ";") || InStr(mname, "[") || InStr(mname, "]") || InStr(mname, "*") || InStr(mname, "|")) {
        MsgBox("Macro name cannot be empty or contain special characters", "Error", "Icon!")
        return
    }
    ; * Loop validation (rewritten, backward-scan matching; unit-tested):
    ;   each endloop claims the NEAREST unmatched loop start before it.
    ;   Names must match when both carry one; anonymous ends match any.
    rowsTxt := ""
    for i, r in App.BuilderRows
        rowsTxt .= i ": " r.Tok "`n"
    ; ! Array.Has() returns BLANK in this Keysharp build (proven in
    ;   the harness) - the matched set MUST be a Map, never an Array.
    matched := Map()
    for i, r in App.BuilderRows {
        tok := r.Tok
        if (SubStr(tok, 1, 7) != "endloop")
            continue
        nm := ""
        if (InStr(tok, ":"))
            nm := StrSplit(tok, ":", , 2)[2]
        found := 0
        j := i - 1
        while (j >= 1) {
            if (!matched.Has(j) && SubStr(App.BuilderRows[j].Tok, 1, 5) = "loop:") {
                found := j
                break
            }
            j--
        }
        if (found = 0) {
            MsgBox("endloop at row " i " has no open loop before it.`n`nCurrent actions:`n" rowsTxt, "Error", "Icon!")
            return
        }
        lp := StrSplit(App.BuilderRows[found].Tok, ":")
        openNm := (lp.Length >= 3) ? lp[2] : ""
        if (nm != "" && openNm != "" && nm != openNm) {
            MsgBox("endloop '" nm "' does not match the open loop '" openNm "' at row " found ".`n`nCurrent actions:`n" rowsTxt, "Error", "Icon!")
            return
        }
        matched[found] := true
    }
    unclosed := ""
    for i, r in App.BuilderRows {
        if (SubStr(r.Tok, 1, 5) = "loop:" && !matched.Has(i))
            unclosed .= i " "
    }
    if (unclosed != "") {
        MsgBox("Every loop must be closed before saving. Unclosed loop at row(s): " unclosed "`n`nCurrent actions:`n" rowsTxt, "Error", "Icon!")
        return
    }
    trigIdx := g["BTrig"].Value
    hdrToks := ""
    if (trigIdx = 2) {
        hdrToks := "trg:release|"
    } else if (trigIdx = 3) {
        ; buffer/delay are free-typed: require clean non-negative
        ; integers so the stored header always parses (ParseMacroHeader)
        bufV := SafeInt(Trim(g["BBuf"].Value), -1)
        delV := SafeInt(Trim(g["BDel"].Value), -1)
        if (bufV < 0 || delV < 0) {
            MsgBox("Repeat buffer and delay must be integers >= 0.", "Error", "Icon!")
            return
        }
        hdrToks := "trg:repeat|rbuf:" bufV "|rdel:" delV "|"
    } else if (trigIdx = 4) {
        px := Trim(g["BPX"].Value)
        py := Trim(g["BPY"].Value)
        pc := StrUpper(Trim(g["BPColor"].Value))
        pm := (g["BPMode"].Value = 2) ? "from" : "to"
        okXY := false
        try {
            okXY := (Integer(px) >= 0 && Integer(py) >= 0)   ; negatives are off-screen
        }
        if (!okXY || !RegExMatch(pc, "^[0-9A-F]{6}$")) {
            MsgBox("Pixel trigger needs non-negative integer X, Y and a 6-digit hex color (RRGGBB).", "Error", "Icon!")
            return
        }
        hdrToks := "trg:pixel|px:" px "," py "," pc "," pm "|"
    }
    seq := hdrToks
    for i, r in App.BuilderRows
        seq .= StrReplace(r.Tok, "|", "{PIPE}") (i < App.BuilderRows.Length ? "|" : "")
    PushUndo()
    App.MacroLib[mname] := seq
    SetDirty()
    RefreshGuiData()
    CloseActionDialog()
    try g.Destroy()
    App.BuilderGui := 0
    SetStatus("Macro '" mname "' saved (builder)")
}

; ---- action dialog (rebuilt on demand; fields shown per type) ----

; Open for append (rowIndex = 0) or edit (rowIndex > 0).
OpenActionDialog(rowIndex) {
    if !IsObject(App.ActionDlgGui)
        BuildActionDialog()
    g := App.ActionDlgGui
    App.ActionDlgRow := rowIndex
    ; default name for a new loop start: Loop1, Loop2, ...
    defaultName := ""
    if (rowIndex = 0) {
        ; Loop end defaults to the INNERMOST open loop's name
        st := []
        for , r in App.BuilderRows {
            lp := StrSplit(r.Tok, ":")
            if (lp[1] = "loop" && lp.Length >= 3)
                st.Push(lp[2])
            else if (lp[1] = "endloop" && st.Length > 0)
                st.Pop()
        }
        n := 1
        Loop {
            candidate := "Loop" n
            taken := false
            for , r in App.BuilderRows {
                lp := StrSplit(r.Tok, ":")
                if (lp.Length >= 3 && lp[2] = candidate)
                    taken := true
            }
            if !taken {
                defaultName := candidate
                break
            }
            n++
        }
        g["ALoopName"].Value := defaultName
        g["ALoopCount"].Value := 1
        g["AKey"].Value := ""
        g["AHoldMs"].Value := 1
        g["AWait"].Value := 100
        g["ACmd"].Value := ""
        g["ASeq"].Value := ""
        g["ARunWait"].Value := 0
        g["AMX"].Value := 0
        g["AMY"].Value := 0
        g["ARel"].Value := 0
        g["AHold"].Value := ""
        g["AType"].Choose(1)
        ActionDlgTypeChange(g["AType"])
    } else {
        ; a stale row number (list shrank since the click) must not crash
        if (rowIndex < 1 || rowIndex > App.BuilderRows.Length) {
            SetStatus("Action row not found")
            return
        }
        try PrefillActionDialog(g, App.BuilderRows[rowIndex].Tok)
        catch as Err {
            LogError("action prefill: " Err.Message)
            SetStatus("Action could not be loaded - see error log")
        }
    }
    g.Show()
}

BuildActionDialog() {
    g := Gui("-MaximizeBox +OwnDialogs", App.Name " - Macro Action")
    App.ActionDlgGui := g
    g.BackColor := App.Theme["Background"]
    ThemedFont(g, "s10 c" App.Theme["Text"])
    g.Add("Text", "x16 y22 w50 h22", "Type:")
    tddl := g.Add("DDL", "x86 y20 w180 vAType Choose1", ["Key press", "Key down", "Key up", "Wait", "Run command", "Mouse move", "Sequence", "Loop start", "Loop end"])
    tddl.OnEvent("Change", ActionDlgTypeChange)
    ; -- per-type field groups, all sharing the y56 row --
    g.Add("Text", "x16 y64 w40 h22 vLKey", "Key:")
    g.Add("Edit", "x60 y62 w200 h22 vAKey c" App.Theme["Text"] " +Background" App.Theme["Control"], "")
    g.Add("Text", "x280 y64 w62 h22 vLHold", "Hold ms:")
    g.Add("Edit", "x344 y62 w80 h22 vAHoldMs c" App.Theme["Text"] " +Background" App.Theme["Control"], "")
    g.Add("Text", "x16 y64 w110 h22 vLWait", "Duration (ms):")
    g.Add("Edit", "x130 y62 w100 h22 vAWait c" App.Theme["Text"] " +Background" App.Theme["Control"], "")
    g.Add("Text", "x16 y64 w80 h22 vLCmd", "Command:")
    g.Add("Edit", "x140 y62 w310 h22 vACmd c" App.Theme["Text"] " +Background" App.Theme["Control"], "")
    g.Add("CheckBox", "x140 y104 w240 h22 vARunWait" BtnBg(), "Wait until return before proceeding")
    g.Add("Text", "x16 y64 w70 h22 vLSeq", "Sequence:")
    g.Add("Edit", "x90 y62 w360 h22 vASeq c" App.Theme["Text"] " +Background" App.Theme["Control"], "")
    g.Add("Text", "x16 y64 w20 h22 vLMX", "X:")
    g.Add("Edit", "x40 y62 w60 h22 vAMX c" App.Theme["Text"] " +Background" App.Theme["Control"], "")
    g.Add("Text", "x106 y64 w20 h22 vLMY", "Y:")
    g.Add("Edit", "x130 y62 w60 h22 vAMY c" App.Theme["Text"] " +Background" App.Theme["Control"], "")
    g.Add("CheckBox", "x200 y60 w90 h22 vARel" BtnBg(), "Relative")
    g.Add("Text", "x296 y64 w40 h22 vLAHold", "Hold:")
    g.Add("Edit", "x340 y62 w110 h22 vAHold c" App.Theme["Text"] " +Background" App.Theme["Control"], "")
    g.Add("Text", "x16 y64 w50 h22 vLLoopName", "Name:")
    g.Add("Edit", "x70 y62 w140 h22 vALoopName c" App.Theme["Text"] " +Background" App.Theme["Control"], "")
    g.Add("Text", "x230 y64 w50 h22 vLLoopCount", "Count:")
    g.Add("Edit", "x284 y62 w70 h22 vALoopCount c" App.Theme["Text"] " +Background" App.Theme["Control"], "")
    saveBtn := g.Add("Button", "x86 y148 w90 h28" BtnBg(), "Save")
    saveBtn.OnEvent("Click", ActionDialogSave)
    cancelBtn := g.Add("Button", "x196 y148 w90 h28" BtnBg(), "Cancel")
    cancelBtn.OnEvent("Click", (*) => CloseActionDialog())
    g.OnEvent("Close", (*) => CloseActionDialog())
    g.OnEvent("Escape", (*) => CloseActionDialog())
    g.Show("w480 h204")
}

; Show only the fields belonging to the selected action type
; (user request: the UI must change with the type).
ActionDlgTypeChange(ctrl, *) {
    g := ctrl.Gui
    typ := ctrl.Text
    k := (typ = "Key press" || typ = "Key down" || typ = "Key up")
    AShowVis(g, k, ["LKey", "AKey"])
    AShowVis(g, (typ = "Key press"), ["LHold", "AHoldMs"])
    AShowVis(g, (typ = "Wait"), ["LWait", "AWait"])
    AShowVis(g, (typ = "Run command"), ["LCmd", "ACmd", "ARunWait"])
    AShowVis(g, (typ = "Mouse move"), ["LMX", "AMX", "LMY", "AMY", "ARel", "LAHold", "AHold"])
    AShowVis(g, (typ = "Sequence"), ["LSeq", "ASeq"])
    AShowVis(g, (typ = "Loop start" || typ = "Loop end"), ["LLoopName", "ALoopName"])
    AShowVis(g, (typ = "Loop start"), ["LLoopCount", "ALoopCount"])
    ; per-type defaults (user request): loop end -> innermost open loop,
    ; loop start -> next free LoopN, wait/mouse/hold prefilled once
    try {
        if (typ = "Loop end") {
            st := []
            for , r in App.BuilderRows {
                lp := StrSplit(r.Tok, ":")
                if (lp[1] = "loop" && lp.Length >= 3)
                    st.Push(lp[2])
                else if (lp[1] = "endloop" && st.Length > 0)
                    st.Pop()
            }
            if (st.Length > 0)
                g["ALoopName"].Value := st[st.Length]
        } else if (typ = "Loop start") {
            cur := Trim(g["ALoopName"].Value)
            if (cur = "") {
                n := 1
                Loop {
                    cand := "Loop" n
                    taken := false
                    for , r in App.BuilderRows {
                        lp := StrSplit(r.Tok, ":")
                        if (lp.Length >= 3 && lp[2] = cand)
                            taken := true
                    }
                    if !taken {
                        g["ALoopName"].Value := cand
                        break
                    }
                    n++
                }
            }
        }
    } catch as ErrD {
    }
}

; Set the dialog fields from an existing token.
PrefillActionDialog(g, tok) {
    parts := StrSplit(tok, ":")
    op := StrLower(parts[1])
    arg := (parts.Length >= 2) ? StrReplace(parts[2], "{PIPE}", "|") : ""
    which := 1
    if (op = "kd")
        which := 2
    else if (op = "ku")
        which := 3
    else if (op = "w") {
        which := 4
        g["AWait"].Value := arg
    } else if (op = "run" || op = "rw") {
        which := 5
        g["ACmd"].Value := arg
        g["ARunWait"].Value := (op = "rw") ? 1 : 0
    } else if (op = "sq") {
        which := 7
        g["ASeq"].Value := arg
    } else if (op = "mm") {
        which := 6
        p := StrSplit(StrReplace(SubStr(tok, 4), "{PIPE}", "|"), ",")
        if (p.Length >= 2) {
            g["AMX"].Value := p[1]
            g["AMY"].Value := p[2]
        }
        if (p.Length >= 3 && StrLower(p[3]) = "rel")
            g["ARel"].Value := 1
        if (p.Length >= 4 && SubStr(p[4], 1, 5) = "hold:")
            g["AHold"].Value := SubStr(p[4], 6)
    } else if (op = "loop") {
        which := 8
        if (parts.Length >= 3) {
            g["ALoopName"].Value := parts[2]
            g["ALoopCount"].Value := parts[3]
        } else {
            g["ALoopName"].Value := ""
            g["ALoopCount"].Value := (parts.Length >= 2) ? parts[2] : ""   ; bare "loop"
        }
    } else if (op = "endloop") {
        which := 9
        g["ALoopName"].Value := (parts.Length >= 2) ? parts[2] : ""
    }
    if (which <= 3) {
        g["AKey"].Value := arg
        if (op = "kp" && parts.Length >= 3)
            g["AHoldMs"].Value := parts[3]
    }
    g["AType"].Choose(which)
    ActionDlgTypeChange(g["AType"])
}

; Read the dialog (only the fields of the selected type matter),
; validate, write the token, hide the dialog, refresh the list.
ActionDialogSave(*) {
    g := App.ActionDlgGui
    if !IsObject(g)
        return
    typ := g["AType"].Text
    tok := ""
    if (typ = "Key press" || typ = "Key down" || typ = "Key up") {
        key := Trim(g["AKey"].Value)
        if (key = "") {
            MsgBox("Key cannot be empty.", "Error", "Icon!")
            return
        }
        op := "kp"
        if (typ = "Key down")
            op := "kd"
        else if (typ = "Key up")
            op := "ku"
        tok := op ":" key
        if (op = "kp") {
            hold := Trim(g["AHoldMs"].Value)
            if (hold != "") {
                ok := false
                try {
                    ok := (Integer(hold) >= 0)
                }
                if (!ok) {
                    MsgBox("Hold duration must be an integer >= 0.", "Error", "Icon!")
                    return
                }
                tok .= ":" hold
            }
        }
    } else if (typ = "Wait") {
        w := Trim(g["AWait"].Value)
        ok := false
        try {
            ok := (Integer(w) >= 0 && w != "")
        }
        if (!ok) {
            MsgBox("Wait duration must be an integer >= 0.", "Error", "Icon!")
            return
        }
        tok := "w:" w
    } else if (typ = "Run command") {
        cmd := Trim(g["ACmd"].Value)
        if (cmd = "") {
            MsgBox("Command cannot be empty.", "Error", "Icon!")
            return
        }
        tok := (g["ARunWait"].Value = 1) ? "rw:" : "run:"
        tok .= cmd
    } else if (typ = "Sequence") {
        sq := Trim(g["ASeq"].Value)
        if (sq = "") {
            MsgBox("Sequence cannot be empty.", "Error", "Icon!")
            return
        }
        tok := "sq:" sq
    } else if (typ = "Mouse move") {
        mx := Trim(g["AMX"].Value)
        my := Trim(g["AMY"].Value)
        ok := false
        try {
            Integer(mx)
            Integer(my)
            ok := (mx != "" && my != "")
        }
        if (!ok) {
            MsgBox("Mouse move needs integer X and Y.", "Error", "Icon!")
            return
        }
        tok := "mm:" mx "," my
        if (g["ARel"].Value = 1)
            tok .= ",rel"
        hold := Trim(g["AHold"].Value)
        if (hold != "")
            tok .= ",hold:" hold
    } else if (typ = "Loop start") {
        nm := Trim(g["ALoopName"].Value)
        cnt := Trim(g["ALoopCount"].Value)
        if (nm = "" || !RegExMatch(nm, "^[A-Za-z0-9_]+$")) {
            MsgBox("Loop name must be a non-empty word of letters/digits (a single character is fine).", "Error", "Icon!")
            return
        }
        n := 1
        ok := false
        try {
            n := Integer(cnt)
            ok := (n >= 1)
        }
        if (!ok) {
            MsgBox("Loop count must be an integer >= 1.", "Error", "Icon!")
            return
        }
        for ri, r in App.BuilderRows {
            if (ri = App.ActionDlgRow)   ; editing this row: its old name is free to keep
                continue
            lp := StrSplit(r.Tok, ":")
            if (lp.Length >= 3 && lp[2] = nm) {
                MsgBox("Loop name '" nm "' is not unique.", "Error", "Icon!")
                return
            }
        }
        tok := "loop:" nm ":" n
    } else if (typ = "Loop end") {
        nm := Trim(g["ALoopName"].Value)
        if (nm = "") {
            MsgBox("Loop end needs the name of the loop it closes.", "Error", "Icon!")
            return
        }
        ; must match a currently open loop (the row being edited is
        ; REPLACED by this one, so it is excluded from the simulation)
        depthNames := []
        found := false
        for ri, r in App.BuilderRows {
            if (ri = App.ActionDlgRow)
                continue
            rt := r.Tok
            if (SubStr(rt, 1, 5) = "loop:") {
                lp := StrSplit(rt, ":")
                if (lp.Length >= 3)
                    depthNames.Push(lp[2])
                else
                    depthNames.Push("")
            } else if (SubStr(rt, 1, 7) = "endloop") {
                if (depthNames.Length > 0)
                    depthNames.Pop()
            }
        }
        for , dn in depthNames {
            if (dn = nm)
                found := true
        }
        if (!found) {
            rowsTxt := ""
            for i, r in App.BuilderRows
                rowsTxt .= i ": " r.Tok "`n"
            MsgBox("No open loop named '" nm "' to close.`n`nCurrent actions:`n" rowsTxt, "Error", "Icon!")
            return
        }
        tok := "endloop:" nm
    }
    if (tok = "") {
        MsgBox("Fill the fields for the selected action type.", "Error", "Icon!")
        return
    }
    if (App.ActionDlgRow = 0)
        App.BuilderRows.Push({Tok: tok})
    else
        App.BuilderRows[App.ActionDlgRow].Tok := tok
    CloseActionDialog()
    FillBuilderList()
}

; ---- Hotstrings tab logic ----

; Fill the Hotstrings list with every hotstring-triggered binding
; of the active profile (any binding type; typically commands).
FillHotstringList() {
    if !IsObject(App.LV_Hotstrings)
        return
    App.LV_Hotstrings.Opt("-Redraw")
    App.LV_Hotstrings.Delete()
    shownHs := 0
    for , b in ActiveProfileMap() {
        if (SubStr(b["Key"], 1, 3) != "hs:")
            continue
        App.LV_Hotstrings.Add("", SubStr(b["Key"], 4), b["Action"], b["Enabled"] ? "Enabled" : "Disabled")
        shownHs++
    }
    App.LV_Hotstrings.Opt("+Redraw")
    ; empty state: centered overlay hint (mirrors the binding lists)
    if App.Ui.Has("EmptyHs")
        App.Ui["EmptyHs"].Visible := (shownHs = 0)
}

; Binding id for a Hotstrings-tab row (match on the trigger text).
HsRowId(row) {
    trig := ""
    try trig := App.LV_Hotstrings.GetText(row, 1)
    if (trig = "")
        return ""
    want := "hs:" trig
    ; prefer the UNSCOPED binding: several rows can share one trigger
    ; text (different scopes, indistinguishable in this list)
    fallbackId := ""
    for id, b in ActiveProfileMap() {
        if (b["Key"] = want) {
            if (b["Scope"] = "")
                return id
            if (fallbackId = "")
                fallbackId := id
        }
    }
    return fallbackId
}

; New hotstring: binding editor prefilled with the Hotstring trigger.
HsNew(*) {
    pre := Map("Type", "cmd", "Trig", "hs")
    OpenEditor("Add", "", pre)
}

HsEditSelected(*) {
    row := App.LV_Hotstrings.GetNext(0)
    if (row = 0) {
        SetStatus("Select a hotstring first")
        return
    }
    id := HsRowId(row)
    if (id != "")
        OpenEditor("Edit", id)
    else
        SetStatus("Hotstring not found")
}

HsDoubleClick(ctrl, info, *) {
    if (info = 0)
        return
    id := HsRowId(info)
    if (id != "")
        OpenEditor("Edit", id)
}

HsDeleteSelected(*) {
    row := App.LV_Hotstrings.GetNext(0)
    if (row = 0) {
        SetStatus("Select a hotstring first")
        return
    }
    id := HsRowId(row)
    if (id = "") {
        SetStatus("Hotstring not found")
        return
    }
    PushUndo()
    RemoveBinding(id)
    SetDirty()
    RefreshGuiData()
    SetStatus("Hotstring deleted")
}

HsToggleSelected(*) {
    row := App.LV_Hotstrings.GetNext(0)
    if (row = 0) {
        SetStatus("Select a hotstring first")
        return
    }
    id := HsRowId(row)
    if (id = "")
        return
    b := GetBinding(id)
    if !IsObject(b)
        return
    PushUndo()
    SetBindingEnabled(id, !b["Enabled"])
    RefreshGuiData()
}

; ---- Profile management (user request) ----
; * Macros and the three repeat settings are PER-PROFILE now: the
;   active profile's macro map is the App.MacroLib VIEW, and the
;   repeat settings sync between App.Settings and the profile store
;   at save time. Written as macro:/set: lines inside each section.

; Point App.MacroLib and the repeat settings at a profile.
SetProfileView(name) {
    if !App.ProfileMacros.Has(name)
        App.ProfileMacros[name] := Map()
    if !App.ProfileSettings.Has(name)
        App.ProfileSettings[name] := Map()
    App.MacroLib := App.ProfileMacros[name]
    ps := App.ProfileSettings[name]
    for , k in ["DoRepeatOutputs", "RepeatBuffer", "RepeatDelay"] {
        if ps.Has(k) {
            ; ! hand-edited set: lines can carry anything ("abcd", "-13");
            ;   sanitize before the values reach Sleep()/the UpDowns
            v := SafeInt(ps[k], -1)
            if (k = "DoRepeatOutputs")
                App.Settings[k] := (v = 1) ? 1 : 0
            else {
                if (v < 0)
                    v := 0
                if (v > 1000)
                    v := 1000
                if (k = "RepeatDelay" && v > 500)
                    v := 500
                App.Settings[k] := v
            }
        } else
            ps[k] := App.Settings[k]
    }
}

; * Write-through for the three per-profile repeat settings: every
;   live change lands in the ACTIVE profile's store immediately, so
;   Save + restart restores them from the profile (the INI value is
;   only the fallback when the profile has no set: line yet).
SyncProfileSetting(k) {
    if !App.ProfileSettings.Has(App.ActiveProfile)
        App.ProfileSettings[App.ActiveProfile] := Map()
    App.ProfileSettings[App.ActiveProfile][k] := App.Settings[k]
}

; Refresh the Profiles tab widgets from the current state.
FillProfilesTab() {
    if !App.Ui.Has("ProfNameEdit")
        return
    try {
        App.Ui["ProfNameEdit"].Value := App.ActiveProfile
        if App.Ui.Has("PDeleteBtn")
            App.Ui["PDeleteBtn"].Text := (App.ActiveProfile = "Default") ? "Clear profile" : "Delete profile"
        ; renaming Default is not allowed - disable the controls
        isDef := (App.ActiveProfile = "Default")
        if App.Ui.Has("PRenameBtn")
            App.Ui["PRenameBtn"].Enabled := !isDef
        App.Ui["ProfNameEdit"].Enabled := !isDef
        if App.Ui.Has("ProfHint")
            App.Ui["ProfHint"].Text := isDef ? "Renaming is disabled for the Default profile." : "Rename target: type the new name for the ACTIVE profile, then press Rename."
        if App.Ui.Has("ProfileDDL")
            PopulateProfileDDL()
    } catch as Err {
        LogError("profiles tab refresh: " Err.Message)
    }
}

ProfileSave(*) {
    ; one-time warning when overriding Default
    if (App.ActiveProfile = "Default" && !App.Settings["WarnedDefaultOverride"]) {
        r := MsgBox("You are about to save into the DEFAULT profile.`nThis is the profile ReBindX loads at startup.`n`nSave anyway?", App.Name, "YesNo Icon! Default2")
        if (r != "Yes")
            return
        App.Settings["WarnedDefaultOverride"] := 1
        try SaveSettings()
    }
    if SaveConfig(App.ConfigFile)
        SetStatus("Profile '" App.ActiveProfile "' saved")
}

; "New profile...": three creation modes (user request).
ProfileNewDialog(*) {
    pd := Gui("-MaximizeBox +OwnDialogs", App.Name " - New Profile")
    pd.BackColor := App.Theme["Background"]
    ThemedFont(pd, "s10 c" App.Theme["Text"])
    pd.Add("Text", "x16 y14 w340 h20", "How should the new profile be created?")
    modeDDL := pd.Add("DDL", "x16 y40 w340 vMode Choose1"
        , ["Create from current settings", "Clone an existing profile", "Create new empty profile"])
    modeDDL.OnEvent("Change", NewDlgModeChange)
    pd.Add("Text", "x16 y78 w340 h20", "New profile name:")
    pd.Add("Edit", "x16 y102 w340 h22 vNName c" App.Theme["Text"] " +Background" App.Theme["Control"], "")
    cloneDDL := pd.Add("DDL", "x16 y138 w340 vClone", [])
    pd.Add("Text", "x16 y172 w340 h20 vCloneLbl", "(select the profile to copy)")
    cloneDDL.Visible := false
    pd["CloneLbl"].Visible := false
    cloneCount := 0
    for , pn in ProfileNamesSorted() {
        if (pn != "Default") {
            cloneDDL.Add(pn)
            cloneCount++
        }
    }
    ; ! Choose(1) on an EMPTY list throws on both engines - the first
    ;   run (only the Default profile exists) must not crash the dialog
    if (cloneCount > 0)
        cloneDDL.Choose(1)
    okBtn := pd.Add("Button", "x96 y206 w100 h30" BtnBg(), "Create")
    okBtn.OnEvent("Click", ProfileNewCreate.Bind(pd))
    caBtn := pd.Add("Button", "x206 y206 w100 h30" BtnBg(), "Cancel")
    caBtn.OnEvent("Click", (*) => pd.Destroy())
    pd.Show("w390 h250")
}

; Mode DDL: the clone selector is visible only in "Clone" mode (2).
NewDlgModeChange(ctrl, *) {
    g := ctrl.Gui
    show := (ctrl.Value = 2)
    try g["Clone"].Visible := show
    try g["CloneLbl"].Visible := show
}

ProfileNamesSorted() {
    names := []
    for name, profile in App.Profiles
        names.Push(name)
    return names
}

ProfileNewCreate(pd, *) {
    mode := pd["Mode"].Value
    name := Trim(pd["NName"].Value)
    if !ProfileNameOk(name)
        return
    if App.Profiles.Has(name) {
        MsgBox("A profile named '" name "' already exists.", "Error", "Icon!")
        return
    }
    ; read the clone target BEFORE Destroy: control access on a
    ; destroyed Gui throws (matches the .ks ordering)
    cloneName := pd["Clone"].Text
    pd.Destroy()
    App.Profiles[name] := Map()
    App.ProfileMacros[name] := Map()
    App.ProfileSettings[name] := Map()
    if (mode = 1) {
        ; from current settings: copy bindings, macros, settings of the ACTIVE profile
        dst := App.Profiles[name]
        for id, b in App.Profiles[App.ActiveProfile]
            dst[id] := CloneBinding(b)
        for mn, ms in App.MacroLib
            App.ProfileMacros[name][mn] := ms
        for k, v in App.ProfileSettings[App.ActiveProfile]
            App.ProfileSettings[name][k] := v
    } else if (mode = 2) {
        if (cloneName = "" || !App.Profiles.Has(cloneName)) {
            MsgBox("Select a profile to clone.", "Error", "Icon!")
            return
        }
        dst := App.Profiles[name]
        for id, b in App.Profiles[cloneName]
            dst[id] := CloneBinding(b)
        for mn, ms in App.ProfileMacros[cloneName]
            App.ProfileMacros[name][mn] := ms
        for k, v in App.ProfileSettings[cloneName]
            App.ProfileSettings[name][k] := v
    }
    SwitchProfile(name)
    RebuildProfilesMenu()
    RefreshGuiData()
    SetDirty()
    SetStatus((mode = 1) ? "Profile '" name "' created from current" : (mode = 2) ? "Profile '" name "' cloned from '" cloneName "'" : "Profile '" name "' created (empty)")
}

ProfileSaveAs(*) {
    ib := InputBox("Save the current profile as:", App.Name " - Save As", "w400 h160")
    if (ib.Result != "OK")
        return
    name := Trim(ib.Value)
    if !ProfileNameOk(name)
        return
    if (App.Profiles.Has(name) && name != App.ActiveProfile) {
        if (MsgBox("Profile '" name "' already exists. Overwrite?", App.Name, "YesNo Icon! Default2") != "Yes")
            return
    }
    if !App.Profiles.Has(name)
        App.Profiles[name] := Map()
    ; deep-copy bindings, macros, settings into the new profile
    dst := App.Profiles[name]
    for id, b in App.Profiles[App.ActiveProfile]
        dst[id] := CloneBinding(b)
    App.ProfileMacros[name] := Map()
    for mn, ms in App.MacroLib
        App.ProfileMacros[name][mn] := ms
    App.ProfileSettings[name] := Map()
    for k, v in App.ProfileSettings[App.ActiveProfile]
        App.ProfileSettings[name][k] := v
    SwitchProfile(name)
    if SaveConfig(App.ConfigFile)
        SetStatus("Saved as profile '" name "' (now active)")
}

ProfileNameOk(name) {
    if (name = "" || InStr(name, ";") || InStr(name, "[") || InStr(name, "]") || InStr(name, "*") || InStr(name, "|")) {
        MsgBox("Profile name cannot be empty or contain special characters", "Error", "Icon!")
        return false
    }
    return true
}

ProfileRename(*) {
    if !App.Ui.Has("ProfNameEdit")
        return
    if (App.ActiveProfile = "Default") {
        SetStatus("The Default profile cannot be renamed")
        return
    }
    newName := Trim(App.Ui["ProfNameEdit"].Value)
    oldName := App.ActiveProfile
    if !ProfileNameOk(newName)
        return
    if (newName = oldName)
        return
    if App.Profiles.Has(newName) {
        MsgBox("A profile named '" newName "' already exists.", "Error", "Icon!")
        return
    }
    App.Profiles[newName] := App.Profiles[oldName]
    App.Profiles.Delete(oldName)
    App.ProfileMacros[newName] := App.MacroLib
    if App.ProfileMacros.Has(oldName)
        App.ProfileMacros.Delete(oldName)
    App.ProfileSettings[newName] := App.ProfileSettings.Has(oldName) ? App.ProfileSettings[oldName] : Map()
    if App.ProfileSettings.Has(oldName)
        App.ProfileSettings.Delete(oldName)
    App.ActiveProfile := newName
    App.Settings["ActiveProfile"] := newName
    ; // the old no-op self-assignment of WarnedDefaultOverride removed
    RebuildProfilesMenu()
    RefreshGuiData()
    SetDirty()
    SetStatus("Profile renamed to '" newName "'")
}

ProfileExport(*) {
    file := FileSelect("S24", A_ScriptDir "\profile.cfg", "Export profile", "Config Files (*.cfg)")
    if (file = "")
        return
    SyncProfileSettings()
    text := ""
    name := App.ActiveProfile
    if (name = "Default") {
        ; Default exports with its full section so imports land correctly
        text .= ProfileSectionText("Default", App.Profiles["Default"])
    } else {
        text .= ProfileSectionText(name, App.Profiles[name])
    }
    try {
        if FileExist(file)
            FileDelete(file)
        FileAppend(text, file, "UTF-8-RAW")
        SetStatus("Profile '" name "' exported")
    } catch as Err {
        LogError("profile export: " Err.Message)
        SetStatus("Profile export failed - see error log")
    }
}

ProfileImport(*) {
    file := FileSelect(3, , "Select a profile .cfg to import", "Config Files (*.cfg)")
    if (file = "")
        return
    PushUndo()
    added := 0
    try {
        ; entries before any [Profile:] header land in Default (a
        ; headerless keybinds.cfg-style file still imports)
        if !App.Profiles.Has("Default")
            App.Profiles["Default"] := Map()
        if !App.ProfileMacros.Has("Default")
            App.ProfileMacros["Default"] := Map()
        if !App.ProfileSettings.Has("Default")
            App.ProfileSettings["Default"] := Map()
        curP := App.Profiles["Default"]
        curM := App.ProfileMacros["Default"]
        curS := App.ProfileSettings["Default"]
        section := "cmd"
        for , raw in StrSplit(FileRead(file, "UTF-8"), "`n", "`r") {
            line := Trim(raw)
            if (line = "" || SubStr(line, 1, 1) = ";")
                continue
            ; the --- separator switches command -> remap entries, so
            ; remaps from a profile export keep their binding type
            if RegExMatch(line, "^-{3,}$") {
                section := "key"
                continue
            }
            if (SubStr(line, 1, 9) = "[Profile:") {
                pname := Trim(SubStr(line, 10, StrLen(line) - 10))
                if (pname = "")
                    continue
                if !App.Profiles.Has(pname) {
                    App.Profiles[pname] := Map()
                    App.ProfileMacros[pname] := Map()
                    App.ProfileSettings[pname] := Map()
                }
                curP := App.Profiles[pname]
                curM := App.ProfileMacros[pname]
                curS := App.ProfileSettings[pname]
                section := "cmd"
                continue
            }
            parts := StrSplit(line, ";", , 2)
            if (parts.Length < 2)
                continue
            keypart := Trim(parts[1])
            payload := StrReplace(Trim(parts[2]), "{SEMICOLON}", ";")
            if (SubStr(keypart, 1, 6) = "macro:" && SubStr(keypart, 7) != "") {
                curM[SubStr(keypart, 7)] := payload
                added++
            } else if (SubStr(keypart, 1, 4) = "set:" && SubStr(keypart, 5) != "") {
                curS[SubStr(keypart, 5)] := payload
                added++
            } else {
                enabled := true
                if (SubStr(keypart, 1, 1) = "*") {
                    enabled := false
                    keypart := Trim(SubStr(keypart, 2))
                }
                scope := ""
                if RegExMatch(keypart, "^([^\[\]]*)\[(.*)\]$", &m) {
                    keypart := Trim(m[1])
                    scope := m[2]
                }
                type := (section = "key") ? "key" : "cmd"
                id := ""
                icp := ""
                if (SubStr(keypart, 1, 3) = "hs:" || SubStr(keypart, 1, 3) = "px:") {
                    id := "cmd|" keypart "|" scope
                } else {
                    ; trailing ~/$/* run = the interception type
                    if RegExMatch(keypart, "[~$*]+$", &im2) {
                        icp := im2[0]
                        keypart := SubStr(keypart, 1, StrLen(keypart) - StrLen(icp))
                    }
                    nk := NormalizeKey(keypart)
                    if (nk = "")
                        continue
                    id := type "|" nk "|" scope
                }
                act := (type = "key") ? NormalizeAction(payload) : payload
                curP[id] := Map("Type", type, "Key", SubStr(id, InStr(id, "|") + 1, InStr(id, "|", false, InStr(id, "|") + 1) - InStr(id, "|") - 1), "Scope", scope, "Action", act, "Enabled", enabled, "Icp", icp, "Seq", ++App.Seq)
                added++
            }
        }
        UnregisterAllHotkeys()   ; imported enabled bindings must activate
        RegisterAllHotkeys()
        RebuildProfilesMenu()
        RefreshGuiData()
        SetDirty()
        SetStatus("Imported " added " entries into matching profiles")
    } catch as Err {
        LogError("profile import: " Err.Message)
        SetStatus("Profile import failed - see error log")
    }
}

ProfileDeleteOrClear(*) {
    name := App.ActiveProfile
    if (name = "Default") {
        if (MsgBox("Clear the Default profile's bindings, macros and settings?", App.Name, "YesNo Icon! Default2") != "Yes")
            return
        PushUndo()
        App.Profiles["Default"] := Map()
        App.ProfileMacros["Default"] := Map()
        App.ProfileSettings["Default"] := Map()
        SetProfileView("Default")
    } else {
        if (MsgBox("Delete profile '" name "'? This cannot be undone after saving.", App.Name, "YesNo Icon! Default2") != "Yes")
            return
        PushUndo()
        ; ! Has()-guarded: Map.Delete throws UnsetItemError on a missing
        ;   key, which would kill the handler mid-way and leave the UI stale
        if App.Profiles.Has(name)
            App.Profiles.Delete(name)
        if App.ProfileMacros.Has(name)
            App.ProfileMacros.Delete(name)
        if App.ProfileSettings.Has(name)
            App.ProfileSettings.Delete(name)
        if (App.ActiveProfile = name)
            App.ActiveProfile := "Default"
        if (App.Settings["ActiveProfile"] = name)
            App.Settings["ActiveProfile"] := "Default"
        SetProfileView("Default")   ; swap macro/settings view + App.MacroLib
    }
    UnregisterAllHotkeys()   ; the deleted/cleared profile's hotkeys must go
    RegisterAllHotkeys()
    RebuildProfilesMenu()
    RefreshGuiData()
    SetDirty()
    SetStatus((name = "Default") ? "Default profile cleared" : "Profile '" name "' deleted")
}

; Sync the live repeat settings into the active profile's store.
SyncProfileSettings() {
    if !App.ProfileSettings.Has(App.ActiveProfile)
        App.ProfileSettings[App.ActiveProfile] := Map()
    ps := App.ProfileSettings[App.ActiveProfile]
    for , k in ["DoRepeatOutputs", "RepeatBuffer", "RepeatDelay"]
        ps[k] := App.Settings[k]
}

; Sidebar "Save to...": copy the SELECTED items (bindings / macros /
; hotstrings, per the active tab) into a profile picked from a
; dropdown of every existing profile + "New empty profile...".
SaveSelectedTo(*) {
    names := []
    ids := []
    if (App.CTab = 4) {
        row := App.LV_Macros.GetNext(0)
        while (row != 0) {
            try names.Push(App.LV_Macros.GetText(row, 1))
            row := App.LV_Macros.GetNext(row)
        }
    } else if (App.CTab = 3) {
        row := App.LV_Hotstrings.GetNext(0)
        while (row != 0) {
            id := HsRowId(row)
            if (id != "")
                ids.Push(id)
            row := App.LV_Hotstrings.GetNext(row)
        }
    } else {
        lv := CurrentTabLV()
        if IsObject(lv) {
            row := lv.GetNext(0)
            while (row != 0) {
                id := BindingIdFromRow(lv, row)
                if (id != "")
                    ids.Push(id)
                row := lv.GetNext(row)
            }
        }
    }
    if (names.Length = 0 && ids.Length = 0) {
        SetStatus("Select the item(s) to save first")
        return
    }
    ; profile picker: every existing profile + "New empty profile..."
    ; (replaces the old free-typed InputBox - user request, round 115)
    sd := Gui("-MaximizeBox +Owner" App.MainGui.Hwnd " +OwnDialogs", App.Name " - Save To")
    sd.BackColor := App.Theme["Background"]
    ThemedFont(sd, "s10 c" App.Theme["Text"])
    sd.Add("Text", "x16 y16 w340 h22", "Save " (names.Length + ids.Length) " selected item(s) to profile:")
    sd.Add("DDL", "x16 y44 w340 vPProf Choose1", SaveToChoices())
    okBtn := sd.Add("Button", "x96 y92 w100 h30" BtnBg(), "Save")
    okBtn.OnEvent("Click", SaveToPicked.Bind(sd, ids, names))
    caBtn := sd.Add("Button", "x206 y92 w100 h30" BtnBg(), "Cancel")
    caBtn.OnEvent("Click", (*) => sd.Destroy())
    sd.OnEvent("Close", (*) => sd.Destroy())
    sd.OnEvent("Escape", (*) => sd.Destroy())
    sd.Show("w390 h150")
}

; Dropdown entries for Save to...: every profile + the new entry.
SaveToChoices() {
    choices := ProfileNamesSorted()
    choices.Push("New empty profile...")
    return choices
}

; Save to... confirmed: apply the choice. The "New empty profile..."
; entry asks for a name first (validated like every other creation
; path). The choice is read BEFORE Destroy (round-111 lesson).
SaveToPicked(sd, ids, names, *) {
    choice := sd["PProf"].Text
    try sd.Destroy()
    if (choice = "")
        return
    pname := choice
    if (choice = "New empty profile...") {
        ib := InputBox("Name for the new profile:", App.Name " - New Profile", "w400 h160")
        if (ib.Result != "OK")
            return
        pname := Trim(ib.Value)
        if !ProfileNameOk(pname)
            return
        if App.Profiles.Has(pname) {
            MsgBox("A profile named '" pname "' already exists.", "Error", "Icon!")
            return
        }
    }
    if !App.Profiles.Has(pname) {
        App.Profiles[pname] := Map()
        App.ProfileMacros[pname] := Map()
        App.ProfileSettings[pname] := Map()
        RebuildProfilesMenu()
    }
    n := 0
    for , id in ids {
        b := GetBinding(id)
        if IsObject(b) {
            App.Profiles[pname][id] := CloneBinding(b)
            n++
        }
    }
    for , mn in names {
        if App.MacroLib.Has(mn) {
            App.ProfileMacros[pname][mn] := App.MacroLib[mn]
            n++
        }
    }
    SetDirty()
    SetStatus(n " item(s) saved to profile '" pname "'")
}

; =============================================================
; 10. Tray menu, profiles, undo, macro recorder
; =============================================================

BuildTrayMenu() {
    try TraySetIcon(JoinPath(A_ScriptDir, "icons", "gear.ico"))
    tray := A_TrayMenu
    tray.Delete()   ; removes ALL items, standard ones included (facts section 8)
    tray.Add("Show / Hide", TrayShowHide)
    tray.Default := "Show / Hide"   ; double-click... 
    tray.ClickCount := 1            ; ...and single-click show/hide
    tray.Add()
    tray.Add("Save", SaveBindings)
    tray.Add("Load", LoadBindings)
    tray.Add("Import...", ImportConfig)
    tray.Add("Export...", ExportConfig)
    tray.Add()
    RebuildProfilesMenu()   ; adds the "Profiles" submenu
    tray.Add()
    tray.Add("Record Macro...", TrayRecordMacro)
    tray.Add()
    tray.Add("Exit", DoExit)
}

; Profiles submenu: rebuilt whenever the profile set changes.
; Items carry the "Radio" option; the active name is checked and
; the previous one is unchecked by the rebuild itself.
RebuildProfilesMenu() {
    try {
        prof := Menu()
        names := []
        for name, profile in App.Profiles
            names.Push(name)
        for , name in names
            prof.Add(name, TraySwitchProfile, "Radio")
        if App.Profiles.Has(App.ActiveProfile)
            prof.Check(App.ActiveProfile)
        prof.Add()
        prof.Add("New...", TrayNewProfile)
        A_TrayMenu.Add("Profiles", prof)
    } catch as Err {
        LogError("profiles menu: " Err.Message)
    }
    PopulateProfileDDL()
}

; Tray default item (single/double click): toggle the main window.
TrayShowHide(*) {
    ToggleGui()
}

TraySwitchProfile(ItemName, *) {
    SwitchProfile(ItemName)
}

TrayNewProfile(*) {
    name := NewProfileName()
    if (name = "")
        return
    SwitchProfile(name)   ; unknown name -> created empty
}

; InputBox per facts section 16, with cancel handling.
NewProfileName() {
    IB := InputBox("Enter a name for the new profile:", App.Name " - New Profile", "w400 h160")
    if (IB.Result != "OK") {          ; "OK" | "Cancel" | "Timeout"
        SetStatus("Profile creation cancelled")
        return ""
    }
    name := Trim(IB.Value)
    if (name = "") {
        SetStatus("Profile name cannot be empty")
        return ""
    }
    ; ! same character rules as ProfileNameOk (Profiles tab) - a bad
    ;   name here would corrupt keybinds.cfg on the next save
    if (InStr(name, ";") || InStr(name, "[") || InStr(name, "]") || InStr(name, "*") || InStr(name, "|")) {
        SetStatus("Profile name cannot contain special characters")
        return ""
    }
    return name
}

; Switch (or create) a profile; the tray radio-check and the
; Settings DDL are rebuilt; ActiveProfile is remembered.
SwitchProfile(name) {
    if (name = "")
        return
    PushUndo()
    UnregisterAllHotkeys()
    if !App.Profiles.Has(name)
        App.Profiles[name] := Map()
    App.ActiveProfile := name
    App.Settings["ActiveProfile"] := name   ; persisted at next SaveSettings
    SetProfileView(name)   ; macro/settings view + sanitized 3-setting sync
    FillProfilesTab()
    RegisterAllHotkeys()
    RebuildProfilesMenu()
    RefreshGuiData()
    SetDirty()
    SetStatus("Profile: " name)
}

; --- Undo (feature 9; Map.Clone is shallow - manual deep clone) ---

; Deep-clone a single binding Map (all scalar fields).
CloneBinding(b) {
    nb := Map()
    for k, v in b
        nb[k] := v
    return nb
}

CloneBindings(profile) {
    clone := Map()
    for id, b in profile {
        nb := Map()
        nb["Type"] := b["Type"]
        nb["Key"] := b["Key"]
        nb["Scope"] := b["Scope"]
        nb["Action"] := b["Action"]
        nb["Enabled"] := b["Enabled"]
        nb["Seq"] := b["Seq"]
        clone[id] := nb
    }
    return clone
}

PushUndo() {
    ; MacroLib values are plain strings, so a shallow Clone is a
    ; complete snapshot of the library.
    App.UndoStack.Push({Profile: App.ActiveProfile, Bindings: CloneBindings(ActiveProfileMap())
        , Macros: App.MacroLib.Clone()})
    while (App.UndoStack.Length > 10)
        App.UndoStack.RemoveAt(1)   ; oldest dropped
}

Undo(*) {
    if (App.UndoStack.Length = 0) {
        SetStatus("Nothing to undo")
        return
    }
    snap := App.UndoStack.Pop()
    UnregisterAllHotkeys()
    App.Profiles[snap.Profile] := snap.Bindings
    if snap.HasProp("Macros") {
        App.MacroLib := snap.Macros
        ; ! keep the profile store in sync with the restored view, else
        ;   switching away and back would resurrect the undone macros
        App.ProfileMacros[snap.Profile] := snap.Macros
    }
    App.ActiveProfile := snap.Profile
    App.Settings["ActiveProfile"] := snap.Profile
    RegisterAllHotkeys()
    RebuildProfilesMenu()
    RefreshGuiData()
    SetDirty()
    SetStatus("Undo")
}

; --- Macro recorder (feature 12; InputHook facts section 5) ---

TrayRecordMacro(*) {
    RecordMacroFlow()
}

RecordMacroFlow() {
    static recording := false
    if (recording) {
        SetStatus("Already recording")
        return
    }
    recording := true
    ; bindings must not fire while recording
    UnregisterAllHotkeys()
    SetStatus("Recording - press Esc to stop")
    TrayTip("Recording - press Esc to stop", App.Name, "Iconi")
    seq := ""
    ok := true
    try seq := RecordMacro(BuildRecorderEndKeys())
    catch as Err {
        LogError("recorder failed: " Err.Message)
        ok := false
    }
    recording := false
    RegisterAllHotkeys()
    if !ok {
        SetStatus("Recording failed - see error log")
        return
    }
    if (seq = "") {
        SetStatus("Recording cancelled")
        return
    }
    ; store into the macro library (macros are managed in their own
    ; tab and assigned to keys from there)
    ib := InputBox("Name for the recorded macro (" StrLen(seq) " chars):", App.Name " - Save Macro", "w400 h160")
    if (ib.Result != "OK" || Trim(ib.Value) = "") {
        SetStatus("Recording discarded - no name given")
        return
    }
    mname := Trim(ib.Value)
    if (InStr(mname, ";") || InStr(mname, "[") || InStr(mname, "]") || InStr(mname, "*") || InStr(mname, "|")) {
        SetStatus("Macro name cannot contain special characters - not saved")
        return
    }
    PushUndo()
    App.MacroLib[mname] := seq
    SetDirty()
    RefreshGuiData()
    SetStatus("Macro '" mname "' saved - assign it from the Macros tab")
}

; Braced canonical names of every multi-char KEY_LIST entry.
; Mouse names are harmless here - InputHook is keyboard-only and
; can never fire them; single-char keys accumulate in .Input.
BuildRecorderEndKeys() {
    endKeys := ""
    for , name in StrSplit(Keys.List, ",")
        endKeys .= "{" name "}"
    return endKeys
}

; Facts section 5 copy-ready loop: "V" passes keystrokes through
; to the active window; buffer resets on every Start(); Escape
; terminates and is NOT appended; EndKey comes back normalized.
; * Recorded TEXT is escaped so literal !, #, +, ^, { and } replay
;   as characters instead of modifiers/braces (security review F13).
RecordMacro(endKeys) {
    seq := ""
    ih := InputHook("V", endKeys)
    loop {
        ih.Start()
        reason := ih.Wait()
        if (reason != "EndKey")
            break
        if (ih.EndKey = "Escape")
            break
        seq .= EscapeSendText(ih.Input) . "{" . ih.EndKey . "}"
        if (StrLen(seq) > 100000)
            break
    }
    ih.Stop()   ; safe no-op when not in progress
    return seq
}

; Escape Send-special characters in recorded text: !, #, +, ^, { and
; } become their braced literal forms ({!}, {#}, ...). Built with
; SubStr stepping - no regex callbacks (see ConvertModifierWords).
EscapeSendText(s) {
    out := ""
    pos := 1
    loop StrLen(s) {
        c := SubStr(s, pos, 1)
        out .= InStr("!#+^{}", c) ? "{" c "}" : c
        pos++
    }
    return out
}

; =============================================================
; 11. Exit path (BUG-04, BUG-08, D-07; facts section 4)
; =============================================================

; The single exit path: button + tray Exit both land here. The
; dirty-state prompt lives in ExitFunc (OnExit), which runs for
; every exit path - including this one - so explicit exits are
; protected too (BUG-04/BUG-08; review finding 3).
DoExit(*) {
    ExitApp
}

; Vetoable OnExit callback. Rules (all doc-verified):
; ! - never throw, never call ExitApp inside the callback;
; - always try SaveSettings() first;
; - never block Logoff/Shutdown; Single (replacing instance)
;   exits WITHOUT saving bindings (the file may have been edited
;   externally and must not be clobbered);
; - any other reason: prompt whenever there are unsaved changes;
;   Cancel = return 1 (veto, stay). A failed save is surfaced
;   instead of silently exiting with the config destroyed.
ExitFunc(ExitReason, ExitCode) {
    try SaveSettings()
    catch as Err {
        LogError("exit settings save failed: " Err.Message)
    }
    if (ExitReason = "Logoff" || ExitReason = "Shutdown")
        return 0
    if (ExitReason = "Single")
        return 0
    if (App.IsDirty) {
        result := MsgBox("You have unsaved binding changes.`n`nYes = Save and exit`nNo = Exit without saving`nCancel = Stay"
            , App.Name, "YesNoCancel Icon! Default2")
        if (result = "Yes") {
            if SaveConfig(App.ConfigFile) {
                ; // App.ExitConfirmed := true removed - never read anywhere
                return 0
            }
            LogError("exit save failed - config not written")
            if (MsgBox("Saving the configuration failed - see the error log.`nExit anyway?"
                    , App.Name, "YesNo Icon! Default2") = "Yes")
                return 0
            return 1   ; veto - stay and let the user recover the file
        }
        if (result = "No")
            return 0
        return 1   ; veto - stay
    }
    return 0
}
