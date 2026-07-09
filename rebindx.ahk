#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook

ProcessSetPriority "AboveNormal"
SetWinDelay(-1)
SetControlDelay(-1)

global AppName := "ReBindX"
global AppTitle := AppName " - Key remapper utility"
global CmdMap := Map()
global LV_Cmd := 0
global LV_Key := 0
global CTab := 1
global KeyMap := Map()
global Settings := Map()
global Theme := Map()
global ActiveHotkeys := Map()
global EditorState := Map()
global guielements := Map()

global configFile := A_ScriptDir "\keybinds.cfg"
global themeFile := A_ScriptDir "\theme.cfg"
global iniFile := A_ScriptDir "\rebindxsettings.ini"
global startupLnk := A_Startup "\" AppName ".lnk"

global complexKeys := ["Tab", "Enter", "Escape", "Space", "Backspace", "Delete", "Insert", "Home", "End", "PgUp", "PgDn", "Up", "Down", "Left", "Right", "NumpadEnter", "NumpadAdd", "NumpadSub", "NumpadMult", "NumpadDiv"]
global funcKeys := []
Loop 24 {
    funcKeys.Push("F" A_Index)
}
global mouseKeys := ["LButton", "RButton", "MButton", "XButton1", "XButton2"]
global validKeys := Map()

for _, keyx in complexKeys
    validKeys[StrUpper(keyx)] := 1
for _, keyx in funcKeys
    validKeys[StrUpper(keyx)] := 1
for _, keyx in mouseKeys
    validKeys[StrUpper(keyx)] := 1

InitApp()

InitApp() {
    LoadTheme()
    LoadSettings()
    
    isSilent := false
    for arg in A_Args {
        if arg = "--silent" {
            isSilent := true
            break
        }
    }
    Settings["GuiVisible"] := !isSilent

    LoadConfig()
    BuildMainGui()
    ApplyTheme()
    RefreshGuiData()
    
    if Settings["GuiVisible"] {
        MainGui.Show()
    }
    
    OnExit(ExitFunc)
}

ExitFunc(*) {
    SaveSettings()
    return 0
}

; --- File I/O ---
LoadTheme() {
    defaultTheme := Map(
        "Background", "1E1E1E",
        "Control", "2D2D2D",
        "Text", "FFFFFF",
        "Transparency", "255"
    )
    
    if FileExist(themeFile) {
        Loop Read, themeFile {
            if InStr(A_LoopReadLine, "=") {
                parts := StrSplit(A_LoopReadLine, "=", , 2)
                key := Trim(parts[1])
                val := Trim(parts[2])
                if defaultTheme.Has(key) {
                    defaultTheme[key] := val
                }
            }
        }
    }
    global Theme := defaultTheme
}

StyleListView(LV) {
    global Theme
    bg := Integer("0x" Theme["Background"])
    txt := Integer("0x" Theme["Text"])
    bg_bgr := (bg & 0xFF) << 16 | (bg & 0xFF00) | (bg & 0xFF0000) >> 16
    txt_bgr := (txt & 0xFF) << 16 | (txt & 0xFF00) | (txt & 0xFF0000) >> 16
    
    LV.Opt("+Background" Theme["Background"])
    DllCall("SendMessage", "Ptr", LV.Hwnd, "UInt", 0x30B, "Ptr", 0, "Ptr", bg_bgr) ; LVM_SETBKCOLOR
    DllCall("SendMessage", "Ptr", LV.Hwnd, "UInt", 0x30C, "Ptr", 0, "Ptr", txt_bgr) ; LVM_SETTEXTCOLOR
    DllCall("SendMessage", "Ptr", LV.Hwnd, "UInt", 0x1001, "Ptr", 0, "Ptr", bg_bgr) ; LVM_SETTEXTBKCOLOR
}

LoadSettings() {
    defaultSettings := Map(
        "DoRepeatOutputs", 0,
        "RepeatBuffer", 0,
        "RepeatDelay", 0,
        "DoStartup", FileExist(startupLnk) ? 1 : 0
    )
    
    if FileExist(iniFile) {
        defaultSettings["DoRepeatOutputs"] := IniRead(iniFile, "SETTINGS", "DoRepeatOutputs", 0)
        defaultSettings["RepeatBuffer"] := IniRead(iniFile, "SETTINGS", "RepeatBuffer", 0)
        defaultSettings["RepeatDelay"] := IniRead(iniFile, "SETTINGS", "RepeatDelay", 0)
    }
    
    global Settings := defaultSettings
}

SaveSettings() {
    IniWrite Settings["DoRepeatOutputs"], iniFile, "SETTINGS", "DoRepeatOutputs"
    IniWrite Settings["RepeatBuffer"], iniFile, "SETTINGS", "RepeatBuffer"
    IniWrite Settings["RepeatDelay"], iniFile, "SETTINGS", "RepeatDelay"
}

LoadConfig(file := "") {
    global CmdMap, KeyMap
    if file = ""
        file := configFile
        
    if !FileExist(file)
        return
        
    CmdMap.Clear()
    KeyMap.Clear()
    UnregisterAllHotkeys()
    
    hitSeparator := false
    Loop Read, file {
        line := Trim(A_LoopReadLine)
        if line = "" or SubStr(line, 1, 1) = ";"
            continue
            
        if SubStr(line, 1, 1) = "-" {
            hitSeparator := true
            continue
        }
        
        pos := InStr(line, ";")
        if !pos
            continue
            
        key := Trim(SubStr(line, 1, pos - 1))
        cmd := Trim(SubStr(line, pos + 1))
        cmd := StrReplace(cmd, "{SEMICOLON}", ";")
        
        if !hitSeparator
            RegHotkey(key, cmd, "cmd")
        else
            RegHotkey(key, cmd, "key")
    }
}

SaveConfig(file := "") {
    global CmdMap, KeyMap
    if file = ""
        file := configFile
        
    if FileExist(file)
        FileDelete(file)
        
    text := ""
    for key, cmd in CmdMap {
        safeCmd := StrReplace(cmd, ";", "{SEMICOLON}")
        text .= key ";" safeCmd "`n"
    }
    text .= "-------------`n"
    for key, out in KeyMap {
        safeOut := StrReplace(out, ";", "{SEMICOLON}")
        text .= key ";" safeOut "`n"
    }
    FileAppend(text, file)
}

; --- Hotkey Engine ---
NormalizeKey(key) {
    if key = ""
        return ""
        
    key := StrUpper(Trim(key))
    key := RegExReplace(key, "\s")
    
    key := StrReplace(key, "WIN+", "#")
    key := StrReplace(key, "CTRL+", "^")
    key := StrReplace(key, "ALT+", "!")
    key := StrReplace(key, "SHIFT+", "+")
    
    key := StrReplace(key, "WIN", "#")
    key := StrReplace(key, "CTRL", "^")
    key := StrReplace(key, "ALT", "!")
    key := StrReplace(key, "SHIFT", "+")
    
    pos := RegExMatch(key, "[\w]")
    if pos = 0
        return ""
        
    modifiers := SubStr(key, 1, pos - 1)
    baseKey := SubStr(key, pos)
    
    if StrLen(baseKey) != 1 {
        if !validKeys.Has(baseKey)
            return ""
    }
    
    seen := ""
    Loop Parse, modifiers {
        if InStr(seen, A_LoopField)
            return ""
        seen .= A_LoopField
    }
    
    if !RegExMatch(baseKey, "^[\w]+$")
        return ""
        
    if !RegExMatch(key, "^[\^!+#]*[\w]+$")
        return ""
        
    return key
}

RegHotkey(key, action, type) {
    global CmdMap, KeyMap, ActiveHotkeys
    cleanKey := RegExReplace(key, "^\$", "")
    cleanKey := NormalizeKey(cleanKey)
    
    if cleanKey = ""
        return
        
    if type = "cmd" {
        CmdMap[cleanKey] := action
    } else {
        KeyMap[cleanKey] := action
    }
    
    if ActiveHotkeys.Has(cleanKey)
        Hotkey("$" cleanKey, "Off")
        
    fn := type = "cmd" ? BindCmd.Bind(cleanKey) : BindKey.Bind(cleanKey)
    ActiveHotkeys[cleanKey] := fn
    Hotkey("$" cleanKey, fn, "On")
}

UnregisterAllHotkeys() {
    global ActiveHotkeys
    for key, fn in ActiveHotkeys {
        Hotkey("$" key, fn, "Off")
    }
    ActiveHotkeys.Clear()
}

BindCmd(boundKey, *) {
    global CmdMap
    cmd := CmdMap[boundKey]
    if cmd != ""
        Run(A_ComSpec " /c " cmd,, "Hide")
}

BindKey(boundKey, *) {
    global KeyMap, Settings
    out := KeyMap[boundKey]
    if out = ""
        return
        
    pos := RegExMatch(out, "[\w]")
    if pos > 1 {
        modifiers := SubStr(out, 1, pos - 1)
        baseKey := SubStr(out, pos)
        Send(modifiers "{" baseKey "}")
        
        if Settings["DoRepeatOutputs"] {
            if Settings["RepeatBuffer"] != 0
                Sleep(Settings["RepeatBuffer"])
            baseBoundKey := RegExReplace(boundKey, "[\^!+#*~\$]")
            while GetKeyState(baseBoundKey, "P") {
                Send(modifiers "{" baseKey "}")
                if Settings["RepeatDelay"] != 0
                    Sleep(Settings["RepeatDelay"])
            }
        }
    } else {
        Send("{" out "}")
        if Settings["DoRepeatOutputs"] {
            if Settings["RepeatBuffer"] != 0
                Sleep(Settings["RepeatBuffer"])
            baseBoundKey := RegExReplace(boundKey, "[\^!+#*~\$]")
            while GetKeyState(baseBoundKey, "P") {
                Send("{" out "}")
                if Settings["RepeatDelay"] != 0
                    Sleep(Settings["RepeatDelay"])
            }
        }
    }
}

BuildMainGui() {
    global MainGui, Theme, Settings, LV_Cmd, LV_Key, guielements
    MainGui := Gui("-Resize -Caption +Border +OwnDialogs", AppTitle)
    MainGui.SetFont("s10 c" Theme["Text"], "Segoe UI")
    guielements := Map()
    
    ; Sidebar title
    MainGui.SetFont("s12 bold c" Theme["Text"], "Segoe UI")
    MainGui.Add("Text", "x15 y15 w120 h30 +BackgroundTrans", AppName)
    
    ; Sidebar buttons
    MainGui.SetFont("s10 norm c" Theme["Text"], "Segoe UI")
    btnW := 130
    btnX := 10
    y := 60
    
    guielements["addbindbtn"] := MainGui.Add("Button", "x" btnX " y" y " w" btnW " h30", "+ Add Binding")
    guielements["addbindbtn"].OnEvent("Click", OpenEditor)
    y += 40
    guielements["delbindbtn"] := MainGui.Add("Button", "x" btnX " y" y " w" btnW " h30", "Delete Selected")
    guielements["delbindbtn"].OnEvent("Click", DeleteSelected)
    y += 40
    guielements["clearbindbtn"] := MainGui.Add("Button", "x" btnX " y" y " w" btnW " h30", "Clear Bindings")
    guielements["clearbindbtn"].OnEvent("Click", ClearBindings)
    y += 40
    guielements["applybtn"] := MainGui.Add("Button", "x" btnX " y" y " w" btnW " h30", "Apply")
    guielements["applybtn"].OnEvent("Click", ApplyBindings)
    y += 40
    guielements["savebtn"] := MainGui.Add("Button", "x" btnX " y" y " w" btnW " h30", "Save")
    guielements["savebtn"].OnEvent("Click", SaveBindings)
    y += 40
    guielements["loadbtn"] := MainGui.Add("Button", "x" btnX " y" y " w" btnW " h30", "Load")
    guielements["loadbtn"].OnEvent("Click", LoadBindings)
    y += 40
    guielements["importbtn"] := MainGui.Add("Button", "x" btnX " y" y " w" btnW " h30", "Import")
    guielements["importbtn"].OnEvent("Click", ImportConfig)
    y += 40
    guielements["exportbtn"] := MainGui.Add("Button", "x" btnX " y" y " w" btnW " h30", "Export")
    guielements["exportbtn"].OnEvent("Click", ExportConfig)
    
    guielements["exitbtn"] := MainGui.Add("Button", "x" btnX " y510 w" btnW " h30", "Exit")
    guielements["exitbtn"].OnEvent("Click", SafeExit)
    
    ; Main content area
    MainGui.SetFont("s10 c" Theme["Text"], "Segoe UI")
    guielements["TAB"] := MainGui.Add("Tab3", "x160 y10 w730 h530 AltSubmit c" Theme["Text"], ["Command Mapper", "Key Remapper", "Settings", "Usage Guide"])
    guielements["TAB"].OnEvent("Change", TabCh)
    
    guielements["TAB"].UseTab(1)
    LV_Cmd := MainGui.Add("ListView", "x170 y40 w710 h490 -Multi NoSortHdr Checked vlvcmd +Background" Theme["Background"], ["Key", "Command"])
    LV_Cmd.ModifyCol(1, 200)
    LV_Cmd.ModifyCol(2, 500)
    StyleListView(LV_Cmd)
    
    guielements["TAB"].UseTab(2)
    LV_Key := MainGui.Add("ListView", "x170 y40 w710 h490 -Multi NoSortHdr Checked vlvkey +Background" Theme["Background"], ["Input", "Output"])
    LV_Key.ModifyCol(1, 200)
    LV_Key.ModifyCol(2, 500)
    StyleListView(LV_Key)
    
    guielements["TAB"].UseTab(3)
    MainGui.Add("Text", "x170 y50 w300 h25 +BackgroundTrans", "Repeat outputs while held (remaps only)")
    MainGui.Add("Text", "x170 y+20 w300 h25 +BackgroundTrans", "Repeat buffer (ms)")
    MainGui.Add("Text", "x170 y+20 w300 h25 +BackgroundTrans", "Repeat delay (ms)")
    MainGui.Add("Text", "x170 y+20 w300 h25 +BackgroundTrans", "Run at startup (requires admin)")
    
    guielements["repeatbtn"] := MainGui.Add("Button", "x480 y45 w100 h30 vRepeatBtn", Settings["DoRepeatOutputs"] ? "Disable" : "Enable")
    guielements["repeatbtn"].OnEvent("Click", ToggleRepeat)
    MainGui.Add("Edit", "x480 y+15 w100 h30 vRepeatBuffer c" Theme["Text"], Settings["RepeatBuffer"])
    MainGui.Add("UpDown", "Range0-1000", Settings["RepeatBuffer"])
    MainGui.Add("Edit", "x480 y+15 w100 h30 vRepeatDelay c" Theme["Text"], Settings["RepeatDelay"])
    MainGui.Add("UpDown", "Range0-500", Settings["RepeatDelay"])
    guielements["startupbtn"] := MainGui.Add("Button", "x480 y+15 w100 h30 vStartupBtn", Settings["DoStartup"] ? "Disable" : "Enable")
    guielements["startupbtn"].OnEvent("Click", ToggleStartup)
    
    guielements["TAB"].UseTab(4)
    MainGui.Add("Text", "x170 y50 w700 +BackgroundTrans", "With the command mapper, you can map valid terminal commands to keybinds. Some examples:")
    MainGui.Add("Text", "x170 y+5 w700 +BackgroundTrans", "start chrome.exe | taskmgr | shutdown /f")
    MainGui.Add("Text", "x170 y+15 w700 +BackgroundTrans", "With the input remapper, you can remap your keyboard keys or map simpler macros to them.`nEvery input field accepts the following syntax:")
    MainGui.Add("Text", "x170 y+5 w700 +BackgroundTrans", "AHK syntax: #^!G | Text syntax: WIN+CTRL+ALT+G or WIN CTRL ALT G")
    MainGui.Add("Text", "x170 y+5 w700 +BackgroundTrans", "It is also possible to add simple macros with AHK syntax:`n!Tab 2 (holds Alt, presses Tab twice, releases Alt)")
    MainGui.Add("Text", "x170 y+5 w700 +BackgroundTrans", "Non-single character keys (esc, tab) are to be referred with their full names (ESCAPE, TAB)`nMouse keys are to be referred as LButton, RButton, Mbutton, XButton1 and XButton2")
    MainGui.Add("Text", "x170 y+15 w700 +BackgroundTrans", "Press F1 to hide/show this GUI. (You can rebind this actually c:)")
    
    guielements["TAB"].UseTab()
    
    MainGui.OnEvent("Close", HideGui)
    MainGui.OnEvent("Escape", HideGui)
    
    Hotkey("F1", ToggleGui)
}

TabCh(*) {
    global MainGui, CTab, guielements
    MainGui.Submit(false)
    CTab := guielements["TAB"].Value
}

ApplyTheme() {
    global MainGui, Theme
    MainGui.BackColor := Theme["Background"]
    WinSetTransparent(Theme["Transparency"], MainGui)
}

OpenEditor(*) {
    global EditorState
    EditorState := Map("Mode", "Add", "Type", "cmd", "Key", "", "Action", "")
    
    EditorGui := Gui("-MaximizeBox +Owner" MainGui.Hwnd, "ReBindX - Remap Editor")
    editorelements := Map()
    EditorGui.SetFont("s10", "Segoe UI Bold")
    EditorGui.BackColor := Theme["Background"]
    
    EditorGui.Add("Text", "x20 y20", "Type:")
    editorelements["comremapdropdown"] := EditorGui.Add("DropDownList", "x100 y15 w120 vType Choose1", ["Command", "Key Remap"])
    editorelements["comremapdropdown"].OnEvent("Change", ChangeEditorType)
    
    EditorGui.Add("Text", "x20 y60", "Keybind:")
    EditorGui.Add("Edit", "x100 y55 w300 h30 vKey")
    
    EditorGui.Add("Text", "x20 y100 vActionLabel", "Command:")
    EditorGui.Add("Edit", "x100 y95 w300 h120 vAction Multi")
    
    editorelements["testbtn"] := EditorGui.Add("Button", "x100 y240 w90 h30", "Test")
    editorelements["testbtn"].OnEvent("Click", TestRemap)
    editorelements["savebtn"] := EditorGui.Add("Button", "x200 y240 w90 h30", "Save")
    editorelements["savebtn"].OnEvent("Click", SaveRemap)
    editorelements["cancelbtn"] := EditorGui.Add("Button", "x300 y240 w90 h30", "Cancel")
    editorelements["cancelbtn"].OnEvent("Click", (*) => EditorGui.Destroy())
    
    EditorGui.Show("w420 h300")
}

ChangeEditorType(ctrl, *) {
    global EditorState
    val := ctrl.Text
    EditorState["Type"] := val = "Command" ? "cmd" : "key"
    ctrl.Gui["ActionLabel"].Value := val = "Command" ? "Command:" : "Output Key:"
    if val = "Key Remap"
        ctrl.Gui["Action"].Opt("h30")
    else
        ctrl.Gui["Action"].Opt("h120")
}

TestRemap(ctrl, *) {
    global EditorState
    key := NormalizeKey(ctrl.Gui["Key"].Value)
    action := Trim(ctrl.Gui["Action"].Value)
    
    if key = "" {
        MsgBox("Invalid key format.", "Error", 48)
        return
    }
    
    if EditorState["Type"] = "cmd"
        Run(A_ComSpec " /c " action,, "Hide")
    else {
        pos := RegExMatch(action, "[\w]")
        if pos > 1 {
            modifiers := SubStr(action, 1, pos - 1)
            baseKey := SubStr(action, pos)
            Send(modifiers "{" baseKey "}")
        } else {
            Send("{" action "}")
        }
    }
}

SaveRemap(ctrl, *) {
    global EditorState, CmdMap, KeyMap
    key := NormalizeKey(ctrl.Gui["Key"].Value)
    action := Trim(ctrl.Gui["Action"].Value) ; Trim newlines/spaces
    
    if key = "" {
        MsgBox("Invalid key format.", "Error", 48)
        return
    }
    
    if action = "" {
        MsgBox("Action cannot be empty.", "Error", 48)
        return
    }
    
    RegHotkey(key, action, EditorState["Type"])
    RefreshGuiData()
    ctrl.Gui.Destroy()
}

DeleteSelected(*) {
    global MainGui, CmdMap, KeyMap, ActiveHotkeys, LV_Cmd, LV_Key, CTab
    currentTab := CTab
    
    if (currentTab = 1) {
        LV := LV_Cmd
        targetMap := CmdMap
    } else if (currentTab = 2) {
        LV := LV_Key
        targetMap := KeyMap
    } else {
        return
    }
    RowsLeft := LV.GetCount()
    RowNumber := 0
    while RowNumber < RowsLeft
    {
        RowNumber++
        ItemState := SendMessage(0x102C, RowNumber - 1, 0xF000, LV)
        IsChecked := (ItemState >> 12) - 1
        if IsChecked
        {
            key := LV.GetText(RowNumber, 1)
            if ActiveHotkeys.Has(key)
                Hotkey("$" key, , "Off")
            ActiveHotkeys.Delete(key)
            if targetMap.Has(key)
                targetMap.Delete(key)
            LV.Delete(RowNumber)
            RowNumber--
            RowsLeft--
        }
    }
    RefreshGuiData()
}

RefreshGuiData() {
    global CmdMap, KeyMap, LV_Cmd, LV_Key
    LV_Cmd := MainGui["lvcmd"]
    LV_Key := MainGui["lvkey"]
    
    LV_Cmd.Delete()
    LV_Key.Delete()
    
    for key, cmd in CmdMap {
        LV_Cmd.Add("", key, cmd)
    }
    for key, out in KeyMap {
        LV_Key.Add("", key, out)
    }
}

; --- GUI Events ---
ToggleGui(*) {
    global MainGui, Settings
    if WinExist(AppTitle) {
        if Settings["GuiVisible"] {
            HideGui()
        } else {
            MainGui.Show()
            Settings["GuiVisible"] := true
        }
    } else {
        BuildMainGui()
        ApplyTheme()
        RefreshGuiData()
        MainGui.Show()
        Settings["GuiVisible"] := true
    }
}

HideGui(*) {
    global MainGui, Settings
    MainGui.Hide()
    Settings["GuiVisible"] := false
    TrayTip(AppName, "Running in the background...", 1)
}

SafeExit(*) {
    result := MsgBox("Are you sure you want to exit? All unsaved changes will be lost.", "Confirm", 308)
    if result = "Yes"
        ExitApp
}

ToggleRepeat(*) {
    global Settings, MainGui
    Settings["DoRepeatOutputs"] := !Settings["DoRepeatOutputs"]
    MainGui["RepeatBtn"].Value := Settings["DoRepeatOutputs"] ? "Disable" : "Enable"
}

ToggleStartup(*) {
    global Settings, MainGui
    if !A_IsAdmin {
        MsgBox("This setting requires the program to have administrator privileges.`nPlease launch the program again as administrator.", "Insufficient permissions", 16)
        return
    }
    
    Settings["DoStartup"] := !Settings["DoStartup"]
    
    if FileExist(startupLnk) && !Settings["DoStartup"] {
        FileDelete(startupLnk)
    } else if !FileExist(startupLnk) && Settings["DoStartup"] {
        FileCreateShortcut(A_ScriptFullPath, startupLnk, A_ScriptDir, "--silent", AppName " startup entry")
    }
    
    MainGui["StartupBtn"].Value := Settings["DoStartup"] ? "Disable" : "Enable"
}

ApplyBindings(*) {
    SaveBindings()
}

SaveBindings(*) {
    SaveConfig()
    TrayTip(AppName, "Saved " (CmdMap.Count + KeyMap.Count) " bindings", 1)
}

LoadBindings(*) {
    LoadConfig()
    LoadTheme()
    LoadSettings()
    RefreshGuiData()
    TrayTip(AppName, "Configuration loaded", 1)
}

ClearBindings(*) {
    global CmdMap, KeyMap
    result := MsgBox("Remove all keybinds?", "Confirm", 308)
    if result = "Yes" {
        UnregisterAllHotkeys()
        CmdMap.Clear()
        KeyMap.Clear()
        RefreshGuiData()
    }
}

ImportConfig(*) {
    file := FileSelect(3,, "Select a .cfg file to import", "Config Files (*.cfg)")
    if file != "" {
        LoadConfig(file)
        RefreshGuiData()
    }
}

ExportConfig(*) {
    file := FileSelect("S24", A_ScriptDir "\save.cfg", "Save settings", "Config Files (*.cfg)")
    if file != "" {
        SaveConfig(file)
    }
}