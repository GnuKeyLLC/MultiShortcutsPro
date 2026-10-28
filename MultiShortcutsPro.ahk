#Requires AutoHotkey v2.0
#SingleInstance Force

;================================================
; MULTISHORTCUTS PRO v2.0.0 - 2026
; STARTER & FULL MODES - ; / ` / = SHORTCUT FAMILIES
;================================================
; © GnuKey LLC
; Implementation assisted by Claude (Anthropic)
; Code review by Gemini (Google)
; Part of the SpeedKee Ecosystem
;================================================
; HOTKEYS:
;   Alt+T  Add Text Expansion
;   Alt+A  Add App Launcher
;   Alt+C  Capture Selected Text as Expansion
;   Alt+D  Add Document Launcher
;   Alt+E  Edit Shortcuts GUI
;   Alt+W  Add Web/Email Launcher
;   Alt+B  Backup Now
;   Alt+Q  Quick Expansion Picker
;   Alt+Z  Undo Last Expansion
;   Alt+P  Pause/Resume
;   Alt+H  Help
;   Alt+R  Reload
;================================================

;------------------------------------------------
; CONFIGURATION
;------------------------------------------------
global config := Map(
    "Hotkeys", Map(
        "AddExpansion",        "!t",
        "AddLauncher",         "!a",
        "CaptureExpansion",    "!c",
        "AddDocumentLauncher", "!d",
        "ShowEditGUI",         "!e",
        "AddWebLauncher",      "!w",
        "ImmediateBackup",     "!b",
        "QuickTextExpansion",  "!q",
        "ManageLaunchers",     "!l",
        "ManageExpansions",    "!m",
        "ShowAllShortcuts",    "!s",
        "ReloadScript",        "!r",
        "ShowHelp",            "!h",
        "PauseResume",         "!p",
        "UndoExpansion",       "!z",
        "SnipTool",            "!+s"
    ),
    "Security", Map(
        "ConfirmDangerousTargets", true,
        "MaxShortcutLength", 50,
        "MinShortcutLength", 2,
        "BlockedProtocols", ["cmd", "powershell", "runas", "regedit",
                             "ms-settings", "vbscript", "javascript",
                             "wscript", "cscript", "ms-msdt", "search-ms",
                             "shell", "calculator", "ms-help", "file"],
        ; File types a launcher may open. Anything else (scripts, installers,
        ; .com, .scr, .js, .reg ...) is refused. Folders are always allowed.
        "AllowedExtensions", ["exe", "lnk",
                              "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
                              "odt", "ods", "odp", "rtf", "txt", "md", "csv", "log",
                              "png", "jpg", "jpeg", "gif", "bmp", "webp",
                              "mp3", "mp4", "wav", "m4a", "mov", "zip"]
    ),
    "Performance", Map(
        "MaxBackupFiles",     10,
        "FileRetryAttempts",  3,
        "FileRetryDelay",     100,
        "LargeTextThreshold", 6000,
        "FileWatchInterval",  5000,
        "SequenceDelay",      150,    ; ms between sequence tokens (key/wait/focus) - increase for slow apps
        "ClipWaitTimeout",    3       ; seconds to wait for clipboard after Ctrl+C
    ),
    "TextExpander", Map(
        "SmartTriggering", true,
        "AutoSpace",       true,
        "BackupOnSave",    true,
        "MaxHistorySize",  20
    ),
    "Triggers", Map(
        ; Trigger characters for the built-in shortcut families.
        ; User-editable via tray menu → "Trigger Keys Setup…"
        ; Persisted in prefs.ini [Triggers].
        "WinCmd",    ";",   ; Windows commands family  (e.g. ;c = Ctrl+C)
        "AppLaunch", "``"   ; Quick app launch family  (e.g. `S = Snip Tool)
    ),
    "Feedback", Map(
        "PlaySounds",    false,
        "ExpandSound",   "*48",
        "LaunchSound",   "*48",
        "ErrorSound",    "*64",
        "BackupSound",   "*48"
    )
)

;------------------------------------------------
; MODE: STARTER (default) vs FULL
; Starter = only ; ` = families active. Lightweight intro.
; Full    = everything: text expansion engine, launchers, GUI editor,
;           file watcher, CSV import/export, etc.
;
; Stored in prefs.ini [Mode] Level=starter | full
; One-way unlock via tray menu - once Full, stays Full.
;------------------------------------------------
global appMode := "starter"     ; flipped to "full" during init if prefs say so

;------------------------------------------------
; GLOBAL STATE
;------------------------------------------------
global launcherPath      := A_ScriptDir . "\launchers.ahk"
global textExpansionPath := A_ScriptDir . "\text_expansion.ahk"
global backupDir         := A_ScriptDir . "\backups"
global statsPath         := A_ScriptDir . "\usage_stats.ini"
global historyPath       := A_ScriptDir . "\expansion_history.ini"
global exportPath        := A_ScriptDir . "\shortcuts_export.csv"
global prefsPath         := A_ScriptDir . "\prefs.ini"
global loadedLaunchers       := Map()
global loadedExpansions      := Map()
global registeredLaunchers   := []
global registeredExpansions  := Map()  ; shortcut -> opts used for registration
global instantExpansions     := Map()  ; shortcuts saved with the $$ instant-fire suffix
global expansionHistory  := []
global usageStats        := Map()
global lvSortCol         := Map("launchers", 0, "expansions", 0)
global lvSortAsc         := Map("launchers", true, "expansions", true)
global holdKeysOn        := false     ; hold ; = Ctrl, hold ` = Alt (see HOLD KEYS)
global holdKeysMs        := 200
global holdKeysMenu      := "Hold `; for Ctrl, hold `` for Alt"
global holdKeysNews      := false     ; true = upgrade: show the one-time What's New
global capsKeyOn         := false     ; Caps Lock: tap = backtick, hold = Alt (on by default)
global capsKeyMenu       := "Caps Lock: tap = ``, hold = Alt"
global mouseKeyOn        := false     ; middle mouse button in use (on by default, like ;)
global mouseKeyMode      := "ctrl"    ; "alt"  = click types `, hold = Alt   (like Caps Lock)
                                      ; "ctrl" = click types ;, hold = Ctrl  (like the semicolon)
global mouseSubMenu      := ""        ; the tray sub-menu (rebuilt with the tray menu)
global mouseItemOff      := "Off - normal middle click"
global mouseItemAlt      := "Click = ``, hold = Alt   (like Caps Lock)"
global mouseItemCtrl     := "Click = `;, hold = Ctrl   (like the semicolon)"

;------------------------------------------------
; AUTO-RELOAD ON EXTERNAL FILE CHANGE
;------------------------------------------------
global lastLauncherMod := 0
global lastExpMod := 0
global lastReload      := 0

CheckFileTimes() {
    global launcherPath, textExpansionPath, lastLauncherMod, lastExpMod, lastReload
    if (A_TickCount - lastReload < 5000)
        return
    ; Don't reload if a write is in progress (lock file present and recent)
    for , lp in [launcherPath . ".lock", textExpansionPath . ".lock"] {
        if (FileExist(lp) && !IsStaleLock(lp))
            return
    }
    tLauncher := 0
    tExp      := 0
    if (FileExist(launcherPath))
        tLauncher := FileGetTime(launcherPath, "M")
    if (FileExist(textExpansionPath))
        tExp := FileGetTime(textExpansionPath, "M")
    if (tLauncher > lastLauncherMod || tExp > lastExpMod) {
        ; Verify files aren't mid-write by an external editor (no .lock file present)
        ; FileOpen read attempt will fail if file is exclusively locked by another process
        try {
            if (tLauncher > lastLauncherMod)
                FileOpen(launcherPath, "r").Close()
            if (tExp > lastExpMod)
                FileOpen(textExpansionPath, "r").Close()
        } catch {
            return  ; File still busy - skip this cycle, will retry on next poll
        }
        lastLauncherMod := tLauncher
        lastExpMod      := tExp
        lastReload      := A_TickCount
        ; Don't reload if user has a script GUI open - would wipe unsaved input
        if (!WinExist("ahk_class AutoHotkeyGUI")) {
            TrayTip("File Change Detected",
                    "Shortcuts file modified externally.`nReloading in 2 seconds...", "Iconi")
            SetTimer(ReloadScriptSilent, -2000)
        }
    }
}

ReloadScriptSilent() {
    Reload()
}

;------------------------------------------------
; INITIALIZATION
;------------------------------------------------
SafeInitialize()

SafeInitialize() {
    global backupDir, loadedLaunchers, loadedExpansions, appMode
    global launcherPath, textExpansionPath, lastLauncherMod, lastExpMod
    try {
        ; Mode + sound + triggers always load (cheap, needed in both modes)
        LoadSoundPrefs()
        LoadTriggerPrefs()
        LoadModePref()
        LoadHoldKeysPrefs()

        ; Always set up the data files - seeding the built-in ; ` = families
        ; happens here. Starter mode users get them too.
        if (!DirExist(backupDir))
            DirCreate(backupDir)
        InitializeFiles()
        MigrateDateSyntax()
        MigratePipeSeparators()
        LoadLaunchers()
        LoadTextExpansions()
        ApplyHoldKeys()

        ; The built-in families are registered as hotstrings via LoadTextExpansions
        ; and LoadLaunchers above. Those work in BOTH modes.
        ; What gets gated by Full mode is everything *else* - the editor, the
        ; user-customizable workflows, the heavy background machinery.

        if (appMode = "full") {
            LoadUsageStats()
            LoadExpansionHistory()
            SetupHotkeys()
            SetTimer(SaveUsageStats, 60000)

            if (FileExist(launcherPath))
                lastLauncherMod := FileGetTime(launcherPath, "M")
            else
                lastLauncherMod := 0
            if (FileExist(textExpansionPath))
                lastExpMod := FileGetTime(textExpansionPath, "M")
            else
                lastExpMod := 0
            SetTimer(CheckFileTimes, config["Performance"]["FileWatchInterval"])
        }

        SetupTrayMenu()
        CheckFirstRun()
        if (holdKeysNews)
            SetTimer(ShowHoldKeysNews, -1500)   ; after start-up, so it doesn't block it

        if (appMode = "full") {
            TrayTip("MultiShortcuts v2.0.0 - Full",
                "Online - " . loadedLaunchers.Count . " launchers, " .
                loadedExpansions.Count . " expansions`nAuto-reload active", "Iconi")
        } else {
            starterMsg := "Ready! Built-in shortcuts work right away."
            starterMsg .= "`nRight-click the tray icon to learn more."
            TrayTip("MultiShortcuts v2.0.0 - Starter", starterMsg, "Iconi")
        }
    } catch Error as err {
        MsgBox("Initialization failed: " . err.Message .
               "`n`nScript will continue in limited mode.", "Error", "Icon!")
    }
}

;------------------------------------------------
; FIRST RUN SETUP
;------------------------------------------------
CheckFirstRun() {
    global prefsPath, config, appMode, holdKeysOn, capsKeyOn, mouseKeyOn, mouseKeyMode
    if (FileExist(prefsPath))
        return

    result := MsgBox(
        "Welcome to MultiShortcuts!`n`n" .
        "Would you like sound feedback when shortcuts fire?`n`n" .
        "You can change this anytime from the tray menu.",
        "First Run Setup", "YesNo Iconi")

    if (result = "Yes") {
        config["Feedback"]["PlaySounds"] := true
        try A_TrayMenu.Check("Sound Feedback")
    }

    try FileAppend("FirstRun=done`n", prefsPath)
    if (holdKeysOn)
        try IniWrite("1", prefsPath, "HoldKeys", "Enabled")
    if (capsKeyOn)
        try IniWrite("1", prefsPath, "HoldKeys", "CapsLock")
    try IniWrite(mouseKeyOn ? mouseKeyMode : "0", prefsPath, "HoldKeys", "MiddleButton")

    wc := config["Triggers"]["WinCmd"]
    al := config["Triggers"]["AppLaunch"]

    if (appMode = "starter") {
        MsgBox(
            "You're running MultiShortcuts in Starter mode.`n`n" .
            "Try these right now - they work anywhere you can type:`n`n" .
            "  " . wc . "c  - Copy           " . wc . "v  - Paste`n" .
            "  " . wc . "s  - Save           " . wc . "p  - Print`n" .
            "  " . wc . "t  - Top of page    " . wc . "b  - Bottom`n" .
            "  " . al . "S  - Snip Tool      " . al . "C  - Calculator`n" .
            "  -=  - Today's date  1m=  - One month from now`n`n" .
            "NEW - Ctrl and Alt, now on your home row:`n" .
            "the same shortcuts, without the reach.`n" .
            "`n" .
            "SEMICOLON  -  hold it for Ctrl`n" .
            "   hold `; + C = Copy,   hold `; + V = Paste`n" .
            "`n" .
            "CAPS LOCK  -  hold it for Alt, tap it for ```n" .
            "   hold Caps Lock + Tab = switch windows`n" .
            "   tap Caps Lock, then c = open Claude`n" .
            "   Shift + Caps Lock = normal Caps Lock`n" .
            "`n" .
            "MIDDLE MOUSE BUTTON  -  works like `;`n" .
            "   click it, then v = Paste`n" .
            "   highlight, hold the wheel, tap C = Copy`n" .
            "   Shift + middle click = normal middle click`n" .
            "`n" .
            "A quick tap of `; still types it, so your`n" .
            "shortcuts work as before.`n" .
            "Change any of this in the tray menu.`n" .
            "`n" .
            "When you want more - custom shortcuts, an editor GUI and more - `n" .
            "right-click the tray icon and choose * Unlock Full Features.",
            "MultiShortcuts - Starter Mode", "Iconi")
    } else {
        MsgBox(
            "Quick Start (Full mode):`n`n" .
            "  Alt+T  - Add a text expansion`n" .
            "  Alt+A  - Add an app launcher`n" .
            "  Alt+C  - Capture selected text`n" .
            "  Alt+E  - Edit all shortcuts`n" .
            "  Alt+H  - Help`n`n" .
            "Right-click the tray icon for all options.",
            "MultiShortcuts - Getting Started", "Iconi")
    }
}

SetupHotkeys() {
    global config
    hk := config["Hotkeys"]
    try {
        Hotkey(hk["AddExpansion"],        (*) => AddNewExpansion())
        Hotkey(hk["AddLauncher"],         (*) => AddNewLauncher())
        Hotkey(hk["CaptureExpansion"],    (*) => CaptureSelectedText())
        Hotkey(hk["AddDocumentLauncher"], (*) => AddDocumentLauncher())
        Hotkey(hk["ShowEditGUI"],         (*) => ShowEditGUI("launchers"))
        Hotkey(hk["AddWebLauncher"],      (*) => AddWebLauncher())
        Hotkey(hk["ImmediateBackup"],     (*) => ImmediateBackup())
        Hotkey(hk["QuickTextExpansion"],  (*) => QuickTextExpansion())
        Hotkey(hk["ManageLaunchers"],     (*) => ShowEditGUI("launchers"))
        Hotkey(hk["ManageExpansions"],    (*) => ShowEditGUI("expansions"))
        Hotkey(hk["ShowAllShortcuts"],    (*) => ShowEditGUI("launchers"))
        Hotkey(hk["ReloadScript"],        (*) => ReloadScript())
        Hotkey(hk["ShowHelp"],            (*) => ShowHelp())
        Hotkey(hk["PauseResume"],         (*) => ToggleMacrosPause(), "S")
        Hotkey(hk["UndoExpansion"],       (*) => UndoLastExpansion())
        Hotkey(hk["SnipTool"],            (*) => Send("#+s"))
    } catch Error as err {
        MsgBox("Hotkey setup error: " . err.Message, "Warning", "Icon!")
    }
}

HotkeyLabel(raw) {
    label := StrReplace(raw, "+", "Shift+")
    label := StrReplace(label, "!", "Alt+")
    label := StrReplace(label, "^", "Ctrl+")
    label := StrReplace(label, "#", "Win+")
    return StrUpper(label)
}

SetupTrayMenu() {
    global appMode
    A_TrayMenu.Delete()
    if (appMode = "starter") {
        SetupStarterTrayMenu()
    } else {
        SetupFullTrayMenu()
    }
    UpdateTrayTooltip()
}

SetupStarterTrayMenu() {
    global config, holdKeysOn, holdKeysMenu, capsKeyOn, capsKeyMenu
    A_TrayMenu.Add("MultiShortcuts (Starter)", (*) => 0)
    A_TrayMenu.Disable("MultiShortcuts (Starter)")
    A_TrayMenu.Add()
    A_TrayMenu.Add("Show Built-in Shortcuts",  (*) => ShowHelp())
    A_TrayMenu.Add("Trigger Keys Setup...",      (*) => ShowTriggerSetup())
    A_TrayMenu.Add(holdKeysMenu,                 ToggleHoldKeys)
    A_TrayMenu.Add(capsKeyMenu,                  ToggleCapsKey)
    A_TrayMenu.Add("Middle mouse button", BuildMouseMenu())
    A_TrayMenu.Add("Hold Keys Timing...",        SetHoldKeysTime)
    if (holdKeysOn)
        A_TrayMenu.Check(holdKeysMenu)
    if (capsKeyOn)
        A_TrayMenu.Check(capsKeyMenu)
    A_TrayMenu.Add()
    A_TrayMenu.Add("* Unlock Full Features",   (*) => UnlockFullMode())
    A_TrayMenu.Add()
    A_TrayMenu.Add("Run on Windows Startup",   (*) => ToggleStartup())
    A_TrayMenu.Add("Sound Feedback",           (*) => ToggleSounds())
    A_TrayMenu.Add("Reload Script",            (*) => Reload())
    A_TrayMenu.Add("Exit",                     (*) => ExitApp())
    A_TrayMenu.Default := "Show Built-in Shortcuts"
    if (FileExist(GetStartupLinkPath()))
        A_TrayMenu.Check("Run on Windows Startup")
    if (config["Feedback"]["PlaySounds"])
        A_TrayMenu.Check("Sound Feedback")
}

SetupFullTrayMenu() {
    global holdKeysOn, holdKeysMenu, capsKeyOn, capsKeyMenu
    A_TrayMenu.Add("Show Help",               (*) => ShowHelp())
    A_TrayMenu.Add("Edit Shortcuts (Alt+E)",  (*) => ShowEditGUI("launchers"))
    A_TrayMenu.Add()
    A_TrayMenu.Add("Add Text Expansion (Alt+T)",    (*) => AddNewExpansion())
    A_TrayMenu.Add("Add App Launcher (Alt+A)",      (*) => AddNewLauncher())
    A_TrayMenu.Add("Add Document (Alt+D)",          (*) => AddDocumentLauncher())
    A_TrayMenu.Add("Add Web/Email (Alt+W)",         (*) => AddWebLauncher())
    A_TrayMenu.Add("Capture Selection (Alt+C)",     (*) => CaptureSelectedText())
    A_TrayMenu.Add("Snip Tool (Alt+Shift+S)",        (*) => Send("#+s"))
    A_TrayMenu.Add()
    A_TrayMenu.Add("Quick Expansion Picker (Alt+Q)", (*) => QuickTextExpansion())
    A_TrayMenu.Add("Undo Last Expansion (Alt+Z)",    (*) => UndoLastExpansion())
    A_TrayMenu.Add()
    A_TrayMenu.Add("Usage Statistics",        (*) => ShowUsageStats())
    A_TrayMenu.Add("Backup Now (Alt+B)",      (*) => ImmediateBackup())
    A_TrayMenu.Add("Export to CSV",           (*) => ExportToCSV())
    A_TrayMenu.Add("Import from CSV",         (*) => ImportFromCSV())
    A_TrayMenu.Add()
    A_TrayMenu.Add("Run on Windows Startup",  (*) => ToggleStartup())
    A_TrayMenu.Add("Sound Feedback",          (*) => ToggleSounds())
    A_TrayMenu.Add("Trigger Keys Setup...",     (*) => ShowTriggerSetup())
    A_TrayMenu.Add(holdKeysMenu,                ToggleHoldKeys)
    A_TrayMenu.Add(capsKeyMenu,                 ToggleCapsKey)
    A_TrayMenu.Add("Middle mouse button", BuildMouseMenu())
    A_TrayMenu.Add("Hold Keys Timing...",       SetHoldKeysTime)
    if (holdKeysOn)
        A_TrayMenu.Check(holdKeysMenu)
    if (capsKeyOn)
        A_TrayMenu.Check(capsKeyMenu)
    A_TrayMenu.Add("Pause/Resume (Alt+P)",    (*) => ToggleMacrosPause())
    A_TrayMenu.Add("Reload Script",           (*) => Reload())
    A_TrayMenu.Add("Exit",                    (*) => ExitApp())
    A_TrayMenu.Default := "Edit Shortcuts (Alt+E)"
    if (FileExist(GetStartupLinkPath()))
        A_TrayMenu.Check("Run on Windows Startup")
    if (config["Feedback"]["PlaySounds"])
        A_TrayMenu.Check("Sound Feedback")
}

UpdateTrayTooltip() {
    global loadedLaunchers, loadedExpansions, appMode
    if (appMode = "starter") {
        A_IconTip := "MultiShortcuts (Starter) v2.0.0" .
                     "`nBuilt-in trigger families active" .
                     "`nRight-click for menu - Unlock Full when ready"
        return
    }
    status   := A_IsSuspended ? "PAUSED" : "Active"
    A_IconTip := "MultiShortcuts (Full) v2.0.0 (" . status . ")"
              . "`nLaunchers: "  . loadedLaunchers.Count
              . "   Expansions: " . loadedExpansions.Count
}

;------------------------------------------------
; SHARED HELPERS
;------------------------------------------------
; Record the current file times after this script writes a data file, so
; the file watcher doesn't treat our own save as an external change and
; reload the whole script.
MarkOwnWrite() {
    global launcherPath, textExpansionPath, lastLauncherMod, lastExpMod
    try lastLauncherMod := FileExist(launcherPath) ? FileGetTime(launcherPath, "M") : 0
    try lastExpMod      := FileExist(textExpansionPath) ? FileGetTime(textExpansionPath, "M") : 0
}

; A lock file older than 30 seconds is assumed to be left over from a
; crash or power cut - no real save takes that long.
IsStaleLock(lockPath) {
    try return DateDiff(A_Now, FileGetTime(lockPath, "M"), "Seconds") > 30
    return false
}

; Waits up to 5 seconds for another save to finish, then creates the lock.
; Returns false if the file is still locked (caller must not write).
AcquireLock(lockPath) {
    retries := 50    ; 5 s - allows for OneDrive/Dropbox sync delays
    while (FileExist(lockPath) && retries > 0) {
        if (IsStaleLock(lockPath)) {
            try FileDelete(lockPath)
            break
        }
        Sleep(100)
        retries--
    }
    if (FileExist(lockPath))
        return false
    try FileAppend("", lockPath, "UTF-8")
    return true
}

; Data files store one entry per line; real newlines become [NEWLINE]
EncodeNewlines(text) {
    return StrReplace(StrReplace(text, "`r`n", "`n"), "`n", "[NEWLINE]")
}

CheckShortcutConflict(shortcut, existingMap) {
    if (!existingMap.Has(shortcut))
        return true
    result := MsgBox("Shortcut '" . shortcut . "' already exists.`n`nOverwrite it?",
                     "Shortcut Exists", "YesNo Icon?")
    return result = "Yes"
}

CheckGlobalConflict(shortcut) {
    global loadedLaunchers, loadedExpansions
    hits := []
    if (loadedLaunchers.Has(shortcut))
        hits.Push("Launcher  (launchers.ahk)")
    if (loadedExpansions.Has(shortcut))
        hits.Push("Text Expansion  (text_expansion.ahk)")
    if (hits.Length = 0)
        return true
    whereList := ""
    for , h in hits
        whereList .= "  * " . h . "`n"
    answer := MsgBox(
        "Shortcut '" . shortcut . "' already exists in:`n`n" . whereList .
        "`nOverwrite it everywhere?",
        "Shortcut Conflict", "YesNo Icon?")
    return answer = "Yes"
}

SaveEntry(filePath, shortcut, target, reloadFn, successTitle, successMsg) {
    global config, loadedLaunchers, loadedExpansions, launcherPath, textExpansionPath
    try {
        if (config["TextExpander"]["BackupOnSave"])
            BackupFile(filePath)
        ; True overwrite: if shortcut exists, rewrite file instead of appending
        ownerMap    := ""
        ownerHeader := ""
        if (filePath = launcherPath) {
            ownerMap    := loadedLaunchers
            ownerHeader := "; Launcher file - Format: shortcut target"
        } else if (filePath = textExpansionPath) {
            ownerMap    := loadedExpansions
            ownerHeader := "; Text Expansion file - Format: shortcut expansion"
        }
        if (ownerMap != "" && ownerMap.Has(shortcut)) {
            ownerMap[shortcut] := target
            RewriteFile(filePath, ownerMap, ownerHeader)
        } else {
            LockedFileAppend(filePath, shortcut . " " . EncodeNewlines(target) . "`n")
        }
        ; "Overwrite it everywhere": if the same trigger also exists in the
        ; other file, remove it there so two hotstrings don't fight over it.
        if (filePath = launcherPath && loadedExpansions.Has(shortcut)) {
            loadedExpansions.Delete(shortcut)
            RewriteFile(textExpansionPath, loadedExpansions,
                        "; Text Expansion file - Format: shortcut expansion")
            LoadTextExpansions()
        } else if (filePath = textExpansionPath && loadedLaunchers.Has(shortcut)) {
            loadedLaunchers.Delete(shortcut)
            RewriteFile(launcherPath, loadedLaunchers,
                        "; Launcher file - Format: shortcut target")
            LoadLaunchers()
        }
        reloadFn.Call()
        TrayTip(successTitle, successMsg, "Iconi")
        return true
    } catch Error as err {
        MsgBox("Failed to save: " . err.Message, "Error", "Icon!")
        return false
    }
}

RewriteFile(filePath, dataMap, headerComment) {
    global config, textExpansionPath, instantExpansions
    lockPath := filePath . ".lock"
    tempPath := filePath . ".tmp"
    backPath := filePath . ".bak"
    ; Never write while another save holds the lock (and never delete
    ; someone else's lock)
    if (!AcquireLock(lockPath)) {
        MsgBox("Could not save - the file is locked:`n" . filePath .
               "`n`nIf this keeps happening, delete the file:`n" . lockPath,
               "Save Failed", "Icon!")
        return false
    }
    try {
        if (config["TextExpander"]["BackupOnSave"])
            BackupFile(filePath)
        content := headerComment . "`n"
        for shortcut, target in dataMap {
            key := shortcut
            ; Keep the $$ instant-fire marker on expansions that had it
            if (filePath = textExpansionPath && instantExpansions.Has(shortcut))
                key .= "$$"
            content .= key . " " . EncodeNewlines(target) . "`n"
        }
        try {
            ; Write to temp first
            if (FileExist(tempPath))
                FileDelete(tempPath)
            FileAppend(content, tempPath, "UTF-8")
            ; Keep backup of original in case the replace fails
            if (FileExist(filePath))
                FileCopy(filePath, backPath, 1)
            ; Atomic OS-level file replacement - safe against power loss/crash
            if (!DllCall("ReplaceFile",
                    "Str", filePath, "Str", tempPath, "Ptr", 0,
                    "UInt", 1, "Ptr", 0, "Ptr", 0)) {
                ; Fallback if ReplaceFile fails (e.g. file doesn't exist yet)
                FileCopy(tempPath, filePath, 1)
            }
            try FileDelete(tempPath)
            try FileDelete(backPath)
        } finally {
            try FileDelete(lockPath)
        }
        MarkOwnWrite()
        return true
    } catch Error as err {
        try FileDelete(lockPath)
        try FileDelete(tempPath)
        ; Restore from backup if available
        if (FileExist(backPath) && !FileExist(filePath))
            try FileCopy(backPath, filePath, 1)
        try FileDelete(backPath)
        MsgBox("Failed to rewrite file: " . err.Message, "Error", "Icon!")
        return false
    }
}

LockedFileAppend(filePath, content) {
    lockPath := filePath . ".lock"
    if (!AcquireLock(lockPath)) {
        MsgBox("Could not save - the file is locked:`n" . filePath .
               "`n`nIf this keeps happening, delete the file:`n" . lockPath,
               "Save Failed", "Icon!")
        return false
    }
    try {
        FileAppend(content, filePath, "UTF-8")
    } finally {
        try FileDelete(lockPath)
    }
    MarkOwnWrite()
    return true
}

PromptShortcut(prompt, title) {
    IB := InputBox(prompt, title, "w370 h150")
    if (IB.Result = "Cancel" || IB.Value = "")
        return ""
    shortcut := Trim(IB.Value)
    if (!IsValidShortcut(shortcut)) {
        MsgBox("Invalid shortcut. Cannot be empty or contain the | character.",
               "Invalid Input", "Icon!")
        return ""
    }
    return shortcut
}

;------------------------------------------------
; AUTO-BACKUP
;------------------------------------------------
BackupFile(filePath) {
    global backupDir
    if (!FileExist(filePath))
        return
    try {
        SplitPath(filePath, &fName)
        timestamp := FormatTime(, "yyyyMMdd_HHmmss")
        destPath  := backupDir . "\" . fName . "." . timestamp . ".bak"
        FileCopy(filePath, destPath)
        PruneBackups(fName)
    } catch {
        ; Silent
    }
}

PruneBackups(baseName) {
    global backupDir, config
    maxFiles := config["Performance"]["MaxBackupFiles"]
    backups  := []
    loop files, backupDir . "\" . baseName . ".*.bak" {
        backups.Push([A_LoopFileFullPath, A_LoopFileTimeCreated])
    }
    loop backups.Length - 1 {
        i := A_Index + 1
        while (i > 1 && backups[i][2] < backups[i-1][2]) {
            tmp           := backups[i]
            backups[i]    := backups[i-1]
            backups[i-1]  := tmp
            i--
        }
    }
    while (backups.Length > maxFiles) {
        try FileDelete(backups[1][1])
        backups.RemoveAt(1)
    }
}

SortArray(arr) {
    if (arr.Length = 0)
        return []

    joined := ""
    for , val in arr
        joined .= val "`n"

    sorted_str := Sort(joined, "D`n C")

    result := StrSplit(sorted_str, "`n")
    while (result.Length > 0 && result[result.Length] = "")
        result.Pop()
    return result
}

;------------------------------------------------
; ADD NEW ENTRY FUNCTIONS
;------------------------------------------------
AddNewLauncher() {
    global launcherPath, loadedLaunchers
    shortcut := PromptShortcut(
        "Enter shortcut trigger name:`n`nExample: 'word' to open Microsoft Word",
        "Add App Launcher")
    if (shortcut = "")
        return
    if (!CheckGlobalConflict(shortcut))
        return
    selectedFile := FileSelect(1, A_ProgramFiles, "Select Application Executable",
                               "Applications (*.exe; *.lnk)")
    if (selectedFile = "")
        return
    ; IsAllowedTarget resolves .lnk files and checks what they point to
    if (!IsAllowedTarget(selectedFile))
        return
    SaveEntry(launcherPath, shortcut, selectedFile, LoadLaunchers,
              "App Launcher Added", shortcut . " -> " . selectedFile)
}

AddDocumentLauncher() {
    global launcherPath, loadedLaunchers
    shortcut := PromptShortcut(
        "Enter shortcut name for the document:`n`nExample: 'resume'",
        "Add Document Launcher")
    if (shortcut = "")
        return
    if (!CheckGlobalConflict(shortcut))
        return
    selectedFile := FileSelect(1, A_MyDocuments, "Select Document",
                               "Documents (*.doc;*.docx;*.pdf;*.txt;*.xlsx;*.pptx;*.csv)")
    if (selectedFile = "")
        return
    if (!IsAllowedTarget(selectedFile))
        return
    SaveEntry(launcherPath, shortcut, selectedFile, LoadLaunchers,
              "Document Launcher Added", shortcut . " -> " . selectedFile)
}

;----------------------------------------------
; TARGET VALIDATION
;----------------------------------------------
; Splits a launcher target into the program/file path and any arguments.
; Handles quoted paths, unquoted paths containing spaces
; (C:\Program Files (x86)\App\app.exe --flag) and bare names (calc.exe).
SplitTarget(t, &path, &args) {
    t    := Trim(t)
    path := t
    args := ""
    if (RegExMatch(t, '^"([^"]+)"\s*(.*)$', &m)) {
        path := m[1]
        args := m[2]
        return
    }
    if (FileExist(t))
        return
    ; Unquoted path followed by arguments: find the shortest prefix
    ; (ending at a space) that is an existing file.
    pos := 0
    while (pos := InStr(t, " ", , pos + 1)) {
        cand := SubStr(t, 1, pos - 1)
        attr := FileExist(cand)
        if (attr != "" && !InStr(attr, "D")) {
            path := cand
            args := LTrim(SubStr(t, pos + 1))
            return
        }
    }
    ; File not present right now (e.g. offline drive) - split after .exe/.lnk
    if (RegExMatch(t, "i)^(.+?\.(?:exe|lnk))\s+(.*)$", &m)) {
        path := m[1]
        args := m[2]
    }
}

; Returns true if a launcher target is safe to save (action = "add") or
; to run (action = "launch"). Launchers are checked again every time they
; fire, so a target written into launchers.ahk by anything other than this
; script (a sync conflict, another program, a hand edit) is still checked.
IsAllowedTarget(target, action := "add", depth := 0) {
    global config
    raw     := Trim(target)
    cleaned := StrLower(raw)
    verb    := (action = "launch") ? "launch" : "add"

    if (cleaned = "")
        return false

    ; Block environment variable references like %comspec%
    if (RegExMatch(cleaned, "%\w+%")) {
        MsgBox("Environment variable references (e.g. %comspec%) are not permitted.`n" .
               "Use a full path instead.`n`n" . raw,
               "Security Block", "Icon!")
        return false
    }

    ; Web and email links open in the browser / mail client
    if (RegExMatch(cleaned, "^(https?://|mailto:|ftp://)"))
        return true

    ; Protocol handlers such as ms-screenclip:  (two or more letters, so a
    ; drive letter like C: is not mistaken for a protocol)
    if (RegExMatch(cleaned, "^([a-z][a-z0-9+.\-]+):", &pm)) {
        for , proto in config["Security"]["BlockedProtocols"] {
            if (pm[1] = proto) {
                MsgBox("Blocked protocol: '" . proto . ":'`n" .
                       "Only web links, email, normal programs, documents and folders are permitted.`n`n" . raw,
                       "Security Block", "Icon!")
                return false
            }
        }
        return true
    }

    ; Local program, document or folder
    SplitTarget(raw, &path, &args)

    ; Run() does not go through a command shell, so these characters can't
    ; chain commands - but there's no legitimate reason for them in launcher
    ; arguments, so refuse them as a precaution.
    if (args != "" && RegExMatch(args, "[&|<>]")) {
        MsgBox("The characters & | < > are not permitted in launcher arguments.`n`n" . raw,
               "Security Block", "Icon!")
        return false
    }

    if (DirExist(path))
        return true    ; folders open in File Explorer

    SplitPath(path, &fileName, , &ext)
    ext := StrLower(ext)
    allowed := false
    for , okExt in config["Security"]["AllowedExtensions"] {
        if (ext = okExt) {
            allowed := true
            break
        }
    }
    if (!allowed) {
        MsgBox("File type '" . (ext = "" ? "(none)" : "." . ext) . "' is not permitted as a launcher target.`n`n" .
               "Launchers can open programs (.exe), shortcuts (.lnk), common documents, " .
               "media files and folders. Scripts and installers are blocked.`n`n" . raw,
               "Security Block", "Icon!")
        return false
    }

    ; A .lnk can point anywhere - check what it actually opens
    if (ext = "lnk" && depth < 2) {
        lnkTarget := ""
        try FileGetShortcut(path, &lnkTarget)
        ; If Windows can't read the .lnk (deleted, or an advertised Start
        ; menu shortcut), FileGetShortcut leaves lnkTarget unset - carry on
        ; instead of crashing. A missing file is reported at launch.
        if (IsSet(lnkTarget) && lnkTarget != "" && StrLower(lnkTarget) != StrLower(path))
            return IsAllowedTarget(lnkTarget, action, depth + 1)
        return true
    }

    ; Ask before adding or running powerful system tools
    if (config["Security"]["ConfirmDangerousTargets"]) {
        dangerousExes := ["cmd.exe", "powershell.exe", "pwsh.exe", "wscript.exe",
                          "cscript.exe", "mshta.exe", "regsvr32.exe", "rundll32.exe",
                          "msiexec.exe", "wmic.exe", "forfiles.exe", "regedit.exe",
                          "certutil.exe", "bitsadmin.exe", "schtasks.exe", "reg.exe"]
        isDangerous := false
        lowName := StrLower(fileName)
        for , exe in dangerousExes {
            if (lowName = exe) {
                isDangerous := true
                break
            }
        }
        ; When adding, also flag anything else inside the Windows system
        ; folders. (Not checked on every launch - it would nag about
        ; ordinary tools like notepad.exe.)
        if (!isDangerous && action != "launch") {
            for , dir in ["\system32\", "\syswow64\", "\sysnative\"] {
                if (InStr(StrLower(path), dir)) {
                    isDangerous := true
                    break
                }
            }
        }
        if (isDangerous) {
            question := (verb = "launch")
                ? "Are you sure you want to run it?"
                : "Are you sure you want to add this launcher?"
            if (MsgBox("Warning: This target is a powerful system program.`n`n" .
                       raw . "`n`n" . question,
                       "Security Warning", "YesNo Icon!") != "Yes")
                return false
        }
    }

    return true
}

;---------------------------------------------
AddWebLauncher() {
    global launcherPath, loadedLaunchers
    shortcut := PromptShortcut(
        "Enter trigger name:`n`nExample: 'gmail' or 'news'",
        "Web/Email Launcher")
    if (shortcut = "")
        return
    if (!CheckGlobalConflict(shortcut))
        return
    I2 := InputBox(
        "Enter URL or Email address:`n`nExamples:`nhttps://gmail.com`njohn@example.com",
        "Target Address", "w400 h160", "https://")
    if (I2.Result = "Cancel" || I2.Value = "")
        return
    target := Trim(I2.Value)
    if (InStr(target, "@") && !InStr(target, "://") && !InStr(target, "mailto:"))
        target := "mailto:" . target
    ; Warn if user adds plain HTTP instead of HTTPS
    if (RegExMatch(target, "^http://")) {
        result := MsgBox("This URL uses HTTP which is not secure.`n`n" .
                         "Would you like to use HTTPS instead?",
                         "Security Warning", "YesNo Icon!")
        if (result = "Yes")
            target := "https://" . SubStr(target, 8)
    }
    if (!IsAllowedTarget(target))
        return
    SaveEntry(launcherPath, shortcut, target, LoadLaunchers,
              "Web Launcher Added", shortcut . " -> " . target)
}

AddNewExpansion() {
    global textExpansionPath, loadedExpansions
    shortcut := PromptShortcut(
        "Enter abbreviation to expand:`n`nExample: 'addr' for your address",
        "Add Text Expansion")
    if (shortcut = "")
        return
    if (!CheckGlobalConflict(shortcut))
        return

    gExp := Gui("+ToolWindow +AlwaysOnTop", "Add Text Expansion - " . shortcut)
    gExp.SetFont("s10", "Segoe UI")
    gExp.Add("Text", "x10 y10 w460 cGray",
        "Enter expansion text. Multi-line paste supported.")
    editVal := gExp.Add("Edit", "x10 y32 w460 h140 +Multi +WantReturn", "")
    gExp.Add("Text", "x10 y180 w460 h100 cGray",
        "Placeholders:  {clip} {clip:100} {clip:trim} {clip:lower} {clip:upper}" .
        "`n  {date} {date:locale} {date:dd/MM/yyyy}   {time} {time:h:mm tt}" .
        "`n  {day} {month} {year}   {user} = login name   {comp} = computer name" .
        "`n  {cursor} = place caret here after expansion   {cursor:5} = move left 5" .
        "`n  {prompt:Question?} = ask for input   {prompt:Question?|default}" .
        "`n  -- Sequence tokens --" .
        "`n  {key:F6} = press a key   {key:^s} = Ctrl+S   {key:{Tab}} = Tab" .
        "`n  {wait:500} = pause 500 ms   {focus:Notepad} = activate window by title")
    gExp.Add("Text", "x10 y286 w480 cGray", "Quick insert:")
    gExp.Add("Button", "x10 y304 w106 h24", "Date yyyy-MM-dd")
        .OnEvent("Click", (*) => InsertIntoEdit(editVal, "{date}"))
    gExp.Add("Button", "x122 y304 w106 h24", "Date dd/MM/yyyy")
        .OnEvent("Click", (*) => InsertIntoEdit(editVal, "{date:dd/MM/yyyy}"))
    gExp.Add("Button", "x234 y304 w100 h24", "Time HH:mm")
        .OnEvent("Click", (*) => InsertIntoEdit(editVal, "{time}"))
    gExp.Add("Button", "x340 y304 w130 h24", "Time h:mm AM/PM")
        .OnEvent("Click", (*) => InsertIntoEdit(editVal, "{time:h:mm tt}"))
    gExp.Add("Button", "x10 y338 w110 h28", "&Save")
        .OnEvent("Click", DoSave)
    gExp.Add("Button", "x128 y338 w110 h28", "&Preview")
        .OnEvent("Click", (*) => MsgBox(ResolvePlaceholders(editVal.Value),
                                        "Preview", "Iconi"))
    gExp.Add("Button", "x246 y338 w110 h28", "Cancel")
        .OnEvent("Click", (*) => gExp.Destroy())
    gExp.Show("w480 h380")
    editVal.Focus()

    DoSave(*) {
        expansion := editVal.Value
        if (expansion = "") {
            MsgBox("Expansion text cannot be empty.", "Validation", "Icon!")
            return
        }
        gExp.Destroy()
        SaveEntry(textExpansionPath, shortcut, expansion, LoadTextExpansions,
                  "Expansion Added", shortcut . " -> " . SubStr(expansion, 1, 40))
    }
}

;------------------------------------------------
; CAPTURE SELECTED TEXT AS EXPANSION
;------------------------------------------------
CaptureSelectedText() {
    global textExpansionPath, loadedExpansions

    clipSaved := ClipboardAll()
    A_Clipboard := ""
    Send("^c")
    if (!ClipWait(config["Performance"]["ClipWaitTimeout"])) {
        A_Clipboard := clipSaved
        MsgBox("No text was selected.`n`nHighlight some text first, then press Alt+C.",
               "Nothing Selected", "Iconi")
        return
    }
    selectedText := A_Clipboard
    A_Clipboard := clipSaved

    if (Trim(selectedText) = "") {
        MsgBox("No text was selected.`n`nHighlight some text first, then press Alt+C.",
               "Nothing Selected", "Iconi")
        return
    }

    preview := StrLen(selectedText) > 150
               ? SubStr(selectedText, 1, 147) . "..."
               : selectedText

    gCap := Gui("+ToolWindow +AlwaysOnTop", "Capture Text as Expansion")
    gCap.SetFont("s10", "Segoe UI")
    gCap.Add("Text", "x10 y10 w440 cGray", "Captured text:")
    previewCtrl := gCap.Add("Edit", "x10 y30 w440 h80 +ReadOnly +Multi", preview)
    previewCtrl.SetFont("s9", "Consolas")
    gCap.Add("Text", "x10 y120 w440", "Enter a shortcut trigger for this text:")
    scEdit := gCap.Add("Edit", "x10 y142 w440 h24")
    gCap.Add("Button", "x10 y178 w120 h28", "Save")
        .OnEvent("Click", DoCaptureSave)
    gCap.Add("Button", "x138 y178 w120 h28", "Cancel")
        .OnEvent("Click", (*) => gCap.Destroy())
    gCap.Show("w460 h218")
    scEdit.Focus()

    DoCaptureSave(*) {
        shortcut := Trim(scEdit.Value)
        if (shortcut = "") {
            MsgBox("Please enter a shortcut name.", "Required", "Icon!")
            return
        }
        if (!IsValidShortcut(shortcut)) {
            MsgBox("Invalid shortcut. Cannot be empty or contain the | character.",
                   "Invalid", "Icon!")
            return
        }
        if (!CheckGlobalConflict(shortcut))
            return
        gCap.Destroy()                          ; close window immediately
        sc  := shortcut
        txt := selectedText
        SetTimer(() => SaveEntry(textExpansionPath, sc, txt, LoadTextExpansions,
                  "Expansion Captured", sc . " -> " . SubStr(txt, 1, 40)), -1)
    }
}

;------------------------------------------------
; IMMEDIATE BACKUP
;------------------------------------------------
ImmediateBackup() {
    global launcherPath, textExpansionPath
    try {
        BackupFile(launcherPath)
        BackupFile(textExpansionPath)
        PlayFeedback("BackupSound")
        TrayTip("Backup Complete", "Both files backed up to \backups\ folder", "Iconi")
    } catch Error as err {
        PlayFeedback("ErrorSound")
        MsgBox("Backup failed: " . err.Message, "Error", "Icon!")
    }
}

;------------------------------------------------
; QUICK TEXT EXPANSION
;------------------------------------------------
QuickTextExpansion() {
    global loadedExpansions
    if (loadedExpansions.Count = 0) {
        MsgBox("No text expansions defined yet.`n`nUse Alt+T to add one.",
               "No Expansions", "Iconi")
        return
    }
    items := []
    for shortcut, expansion in loadedExpansions {
        previewText := StrReplace(StrReplace(expansion, "`r`n", " <- "), "`n", " <- ")
        preview := StrLen(previewText) > 60
                   ? SubStr(previewText, 1, 57) . "..."
                   : previewText
        items.Push(shortcut . "  ->  " . preview)
    }
    items := SortArray(items)

    gPick := Gui("+ToolWindow +AlwaysOnTop", "Quick Text Expansion")
    gPick.SetFont("s10", "Segoe UI")
    gPick.BackColor := "FFFFFF"
    gPick.Add("Text", "x10 y10 w380 cGray",
              "Search and double-click or press Enter to paste:")
    searchBox := gPick.Add("Edit", "x10 y32 w380 h24 vSearch")
    lv := gPick.Add("ListView", "x10 y62 w380 h240 -Hdr Grid", [""])
    lv.ModifyCol(1, 370)
    PopulateQuickList(lv, items, "")
    searchBox.OnEvent("Change", (*) => PopulateQuickList(lv, items, searchBox.Value))

    PasteSelected(*) {
        row := lv.GetNext(0, "Focused")
        if (!row)
            row := lv.GetNext()
        if (!row)
            return
        rowText := lv.GetText(row, 1)
        sc := Trim(StrSplit(rowText, "  ->  ")[1])
        if (loadedExpansions.Has(sc)) {
            gPick.Destroy()
            Sleep(80)
            expansion := loadedExpansions[sc]
            RecordExpansionHistory(sc, sc, StrLen(expansion))
            SendText(expansion)
            TrackUsage(sc, "expansion")
        }
    }

    lv.OnEvent("DoubleClick", PasteSelected)
    gPick.Add("Button", "x10 y312 w180 h28", "Paste Selected")
        .OnEvent("Click", PasteSelected)
    gPick.Add("Button", "x200 y312 w190 h28", "Cancel")
        .OnEvent("Click", (*) => gPick.Destroy())
    gPick.Show("w400 h352")
    searchBox.Focus()
}

PopulateQuickList(lv, items, filter := "") {
    lv.Delete()
    ; Fix 8: use default parameter instead of ?? operator for v2 compatibility
    for , item in items {
        if (filter = "" || InStr(item, filter))
            lv.Add("", item)
    }
    if (lv.GetCount() > 0)
        lv.Modify(1, "Select Focus")
}

;------------------------------------------------
; UNDO LAST EXPANSION
;------------------------------------------------
UndoLastExpansion() {
    global expansionHistory
    if (expansionHistory.Length = 0) {
        TrayTip("Nothing to Undo", "No recent expansions in history", "Iconi")
        return
    }
    last     := expansionHistory[expansionHistory.Length]
    original := last["shortcut"]
    delCount := last.Has("length") ? last["length"] : -1
    if (delCount < 0) {
        expansionHistory.Pop()
        SaveExpansionHistory()
        TrayTip("Can't Undo",
                "'" . original . "' sent keystrokes or moved the cursor, so it can't be undone automatically.",
                "Iconi")
        return
    }
    Send("{BS " . delCount . "}")
    Sleep(30)
    SendText(original)
    expansionHistory.Pop()
    SaveExpansionHistory()
    TrayTip("Undone", "Restored '" . original . "'", "Iconi")
}

; typedLength = exact number of characters typed (including any trailing
; space), or -1 when the expansion can't be undone by backspacing.
RecordExpansionHistory(shortcut, original, typedLength) {
    global expansionHistory, config, appMode
    if (appMode != "full")
        return    ; Undo is a Full-mode feature - don't write history in Starter
    maxSize := config["TextExpander"]["MaxHistorySize"]
    ; Store only shortcut + timestamp + length - NOT the expanded text
    ; This protects patient data, private messages, and sensitive content
    expansionHistory.Push(Map(
        "shortcut", shortcut,
        "original", original,
        "length",   typedLength,
        "time",     A_Now
    ))
    while (expansionHistory.Length > maxSize)
        expansionHistory.RemoveAt(1)
    SaveExpansionHistory()
}

;------------------------------------------------
; EXPANSION HISTORY PERSISTENCE
;------------------------------------------------
SaveExpansionHistory() {
    global expansionHistory, historyPath
    try {
        content := ""
        for entry in expansionHistory {
            sc  := StrReplace(entry["shortcut"], "|", "[PIPE]")
            len := entry.Has("length") ? entry["length"] : 0
            content .= sc . "|" . len . "|" . entry["time"] . "`n"
        }
        if (FileExist(historyPath))
            FileDelete(historyPath)
        if (content != "")
            FileAppend(content, historyPath)
    } catch Error as err {
        if (InStr(err.Message, "disk") || InStr(err.Message, "space") ||
            InStr(err.Message, "denied") || InStr(err.Message, "permission"))
            TrayTip("Save Warning", "Could not save history: " . err.Message, "Icon!")
    }
}

LoadExpansionHistory() {
    global expansionHistory, historyPath, config
    expansionHistory := []
    if (!FileExist(historyPath))
        return
    try {
        maxSize := config["TextExpander"]["MaxHistorySize"]
        content := FileRead(historyPath, "UTF-8")
        for line in StrSplit(content, "`n", "`r") {
            line := Trim(line)
            if (line = "")
                continue
            parts := StrSplit(line, "|", , 3)
            if (parts.Length >= 3) {
                expansionHistory.Push(Map(
                    "shortcut", StrReplace(parts[1], "[PIPE]", "|"),
                    "length",   Integer(parts[2]),
                    "time",     parts[3]
                ))
            }
        }
        while (expansionHistory.Length > maxSize)
            expansionHistory.RemoveAt(1)
    } catch Error as err {
        ; Silent
    }
}

;------------------------------------------------
; USAGE STATS PERSISTENCE
;------------------------------------------------
SaveUsageStats() {
    global usageStats, statsPath
    try {
        content := ""
        for key, data in usageStats
            content .= key . "|" . data["count"] . "|" . data["lastUsed"] . "`n"
        if (FileExist(statsPath))
            FileDelete(statsPath)
        if (content != "")
            FileAppend(content, statsPath)
    } catch Error as err {
        ; Fix 9: surface disk-full or permission errors
        if (InStr(err.Message, "disk") || InStr(err.Message, "space") ||
            InStr(err.Message, "denied") || InStr(err.Message, "permission"))
            TrayTip("Save Warning", "Could not save stats: " . err.Message, "Icon!")
    }
}

LoadUsageStats() {
    global usageStats, statsPath
    usageStats := Map()
    if (!FileExist(statsPath))
        return
    try {
        content := FileRead(statsPath, "UTF-8")
        for line in StrSplit(content, "`n", "`r") {
            line := Trim(line)
            if (line = "")
                continue
            parts := StrSplit(line, "|", , 3)
            if (parts.Length >= 3)
                usageStats[parts[1]] := Map(
                    "count",    Integer(parts[2]),
                    "lastUsed", parts[3])
        }
    } catch Error as err {
        ; Silent
    }
}

TrackUsage(shortcut, type) {
    global usageStats
    key := type . "|" . shortcut
    if (!usageStats.Has(key))
        usageStats[key] := Map("count", 0, "lastUsed", "")
    usageStats[key]["count"]++
    usageStats[key]["lastUsed"] := A_Now
    ; Stats are saved to disk by a background timer every 60 seconds
    ; rather than on every keystroke to prevent disk thrashing
}

;------------------------------------------------
; USAGE STATS GUI
;------------------------------------------------
ShowUsageStats() {
    global usageStats
    if (usageStats.Count = 0) {
        MsgBox("No usage data yet.`n`nShortcuts are tracked as you use them.",
               "Usage Statistics", "Iconi")
        return
    }
    rows := []
    for key, data in usageStats {
        parts := StrSplit(key, "|", , 2)
        rows.Push([data["count"], parts[2], parts[1], data["lastUsed"]])
    }
    loop rows.Length - 1 {
        i := A_Index + 1
        while (i > 1 && rows[i][1] > rows[i-1][1]) {
            tmp       := rows[i]
            rows[i]   := rows[i-1]
            rows[i-1] := tmp
            i--
        }
    }
    gStats := Gui("+ToolWindow +Resize", "Usage Statistics")
    gStats.SetFont("s10", "Segoe UI")
    gStats.Add("Text", "x10 y10 w560 cGray", "Most-used shortcuts (all time):")
    lv := gStats.Add("ListView", "x10 y32 w560 h320 Grid",
                     ["Shortcut", "Type", "Uses", "Last Used"])
    loop lv.GetCount("Col")
        lv.ModifyCol(A_Index, "AutoHdr")
    for row in rows {
        lastUsed := row[4] != "" ? FormatTime(row[4], "yyyy-MM-dd  HH:mm") : "-"
        lv.Add("", row[2], row[3], row[1], lastUsed)
    }
    gStats.Add("Button", "x10 y362 w120 h28", "Clear Stats")
        .OnEvent("Click", (*) => ClearStats(gStats))
    gStats.Add("Button", "x138 y362 w120 h28", "Export Stats")
        .OnEvent("Click", (*) => ExportStats(rows))
    gStats.Add("Button", "x448 y362 w120 h28", "Close")
        .OnEvent("Click", (*) => gStats.Destroy())
    gStats.OnEvent("Close",  (*) => gStats.Destroy())
    gStats.OnEvent("Escape", (*) => gStats.Destroy())
    gStats.Show("w580 h402")
}

ClearStats(gStats) {
    global usageStats
    if (MsgBox("Clear all usage statistics?", "Confirm", "YesNo Icon?") = "Yes") {
        usageStats := Map()
        SaveUsageStats()
        gStats.Destroy()
        TrayTip("Cleared", "Usage stats reset", "Iconi")
    }
}

ExportStats(rows) {
    savePath := FileSelect("S", A_ScriptDir . "\usage_stats_export.csv",
                           "Export Usage Stats", "CSV Files (*.csv)")
    if (savePath = "")
        return
    try {
        content := "Shortcut,Type,Uses,Last Used`n"
        for row in rows {
            lastUsed := row[4] != "" ? FormatTime(row[4], "yyyy-MM-dd HH:mm") : ""
            content .= EscapeCSV(row[2]) . "," . EscapeCSV(row[3]) . ","
                     . row[1] . "," . EscapeCSV(lastUsed) . "`n"
        }
        if (FileExist(savePath))
            FileDelete(savePath)
        FileAppend(content, savePath)
        TrayTip("Stats Exported", "Saved to " . savePath, "Iconi")
    } catch Error as err {
        MsgBox("Export failed: " . err.Message, "Error", "Icon!")
    }
}

;------------------------------------------------
; EXPORT TO CSV
;------------------------------------------------
ExportToCSV() {
    global loadedLaunchers, loadedExpansions, exportPath
    savePath := FileSelect("S", exportPath, "Export Shortcuts to CSV",
                           "CSV Files (*.csv)")
    if (savePath = "")
        return
    try {
        content := "Type,Shortcut,Target/Expansion`n"
        for sc, target in loadedLaunchers
            content .= "Launcher," . EscapeCSV(sc) . "," . EscapeCSV(target) . "`n"
        for sc, exp in loadedExpansions
            content .= "Expansion," . EscapeCSV(sc) . "," . EscapeCSV(exp) . "`n"
        if (FileExist(savePath))
            FileDelete(savePath)
        FileAppend(content, savePath)
        MsgBox("Exported " . (loadedLaunchers.Count + loadedExpansions.Count) .
               " shortcuts to:`n" . savePath, "Export Complete", "Iconi")
    } catch Error as err {
        MsgBox("Export failed: " . err.Message, "Error", "Icon!")
    }
}

EscapeCSV(val) {
    ; Substitute newlines with token before CSV encoding
    val := StrReplace(val, "`r`n", "[NEWLINE]")
    val := StrReplace(val, "`n",   "[NEWLINE]")
    val := StrReplace(val, "`r",   "[NEWLINE]")
    ; Prefix cells starting with formula characters to prevent Excel injection
    ; e.g. =cmd|, @SUM, +calc, -1+1+cmd|
    if (RegExMatch(val, "^[=@+\-]"))
        val := "'" . val
    if (InStr(val, ",") || InStr(val, '"')) {
        val := StrReplace(val, '"', '""')
        return '"' . val . '"'
    }
    return val
}

;------------------------------------------------
; IMPORT FROM CSV
;------------------------------------------------
; Splits one CSV line into fields, honouring "quoted, fields" and "" escapes
ParseCSVLine(line) {
    fields := []
    field  := ""
    inQ    := false
    i      := 1
    n      := StrLen(line)
    while (i <= n) {
        ch := SubStr(line, i, 1)
        if (inQ) {
            if (ch = '"') {
                if (SubStr(line, i + 1, 1) = '"') {
                    field .= '"'
                    i += 2
                    continue
                }
                inQ := false
            } else {
                field .= ch
            }
        } else if (ch = '"') {
            inQ := true
        } else if (ch = ",") {
            fields.Push(field)
            field := ""
        } else {
            field .= ch
        }
        i++
    }
    fields.Push(field)
    ; Hand-made files may leave commas in the last column unquoted
    while (fields.Length > 3) {
        last := fields.Pop()
        fields[fields.Length] .= "," . last
    }
    return fields
}

; Reverses what EscapeCSV did on export
UnescapeCSVValue(val) {
    ; Export prefixes ' to values starting with = @ + - (spreadsheet
    ; formula guard). Remove it so -= comes back as -= and not '-=.
    if (RegExMatch(val, "^'[=@+\-]"))
        val := SubStr(val, 2)
    return StrReplace(val, "[NEWLINE]", "`n")
}

ImportFromCSV() {
    global loadedLaunchers, loadedExpansions, launcherPath, textExpansionPath
    ; Warn user about trusted sources before importing
    result := MsgBox("Only import shortcut files from sources you trust.`n`n" .
                     "Imported expansions may send keystrokes, use clipboard content,`n" .
                     "or activate windows on your computer.`n`nContinue with import?",
                     "Import Warning", "YesNo Icon!")
    if (result != "Yes")
        return
    filePath := FileSelect(1, A_ScriptDir, "Import Shortcuts from CSV",
                           "CSV Files (*.csv)")
    if (filePath = "")
        return

    try {
        lines := StrSplit(FileRead(filePath, "UTF-8"), "`n", "`r")
    } catch Error as err {
        MsgBox("Could not read the file: " . err.Message, "Import Failed", "Icon!")
        return
    }

    ; ── Pre-scan: count expansions that send keystrokes or switch windows.
    ; {key:...} sends raw keystrokes - an imported {key:#r} would open Run,
    ; {key:^w} would close the active window, etc. Make the user aware.
    riskyCount   := 0
    riskySamples := []
    for i, line in lines {
        line := Trim(line)
        if (line = "" || (i = 1 && InStr(line, "Type,Shortcut")))
            continue
        f := ParseCSVLine(line)
        if (f.Length < 3 || Trim(f[1]) != "Expansion")
            continue
        ; Shortcuts you already have are skipped on import (including the
        ; built-in ; and = families), so they aren't a risk - don't count them
        sc := UnescapeCSVValue(Trim(f[2]))
        if (loadedExpansions.Has(sc) || loadedLaunchers.Has(sc))
            continue
        if (InStr(f[3], "{key:") || InStr(f[3], "{focus:")) {
            riskyCount++
            if (riskySamples.Length < 3)
                riskySamples.Push(sc)
        }
    }
    if (riskyCount > 0) {
        sampleList := ""
        for , smp in riskySamples
            sampleList .= "  * " . smp . "`n"
        if (riskyCount > riskySamples.Length)
            sampleList .= "  * ...and " . (riskyCount - riskySamples.Length) . " more`n"
        warn := riskyCount . " expansion(s) in this CSV send keystrokes or activate "
        warn .= "windows via {key:} or {focus:} tokens.`n`n"
        warn .= sampleList . "`n"
        warn .= "These can perform actions like closing windows, opening dialogs, "
        warn .= "or running Win+R. Only import if you trust the source.`n`n"
        warn .= "Proceed with the import?"
        if (MsgBox(warn, "Risky Tokens Detected", "YesNo Icon!") != "Yes")
            return
    }

    imported := 0
    skipped  := 0
    seen     := Map()   ; avoid adding the same trigger twice from one file
    for i, line in lines {
        line := Trim(line)
        if (line = "" || (i = 1 && InStr(line, "Type,Shortcut")))
            continue
        f := ParseCSVLine(line)
        if (f.Length < 3) {
            skipped++
            continue
        }
        type := Trim(f[1])
        sc   := UnescapeCSVValue(Trim(f[2]))
        val  := UnescapeCSVValue(f[3])
        if (type = "Launcher")
            val := Trim(val)
        if (!IsValidShortcut(sc, false) || Trim(val) = "" || seen.Has(sc)) {
            skipped++
            continue
        }
        if (loadedLaunchers.Has(sc) || loadedExpansions.Has(sc)) {
            skipped++    ; never overwrite existing shortcuts on import
            continue
        }
        if (type = "Launcher") {
            if (IsAllowedTarget(val)
                && LockedFileAppend(launcherPath, sc . " " . EncodeNewlines(val) . "`n")) {
                seen[sc] := true
                imported++
            } else {
                skipped++
            }
        } else if (type = "Expansion") {
            if (LockedFileAppend(textExpansionPath, sc . " " . EncodeNewlines(val) . "`n")) {
                seen[sc] := true
                imported++
            } else {
                skipped++
            }
        } else {
            skipped++
        }
    }
    LoadLaunchers()
    LoadTextExpansions()
    MsgBox("Import complete.`n`nImported: " . imported .
           "`nSkipped: " . skipped .
           (skipped > 0 ? "`n`n(Existing shortcuts are never overwritten by an import.)" : ""),
           "Import Results", "Iconi")
}

;------------------------------------------------
; RUN ON STARTUP
;------------------------------------------------
GetStartupLinkPath() {
    return A_Startup . "\MultiShortcuts.lnk"
}

ToggleStartup() {
    linkPath := GetStartupLinkPath()
    if (FileExist(linkPath)) {
        FileDelete(linkPath)
        A_TrayMenu.Uncheck("Run on Windows Startup")
        TrayTip("Startup Disabled", "Script will not run on login", "Iconi")
    } else {
        FileCreateShortcut(A_ScriptFullPath, linkPath, A_ScriptDir)
        A_TrayMenu.Check("Run on Windows Startup")
        TrayTip("Startup Enabled", "Script will run automatically on login", "Iconi")
    }
}

LoadSoundPrefs() {
    global prefsPath, config
    if (!FileExist(prefsPath))
        return
    try {
        saved := IniRead(prefsPath, "Settings", "PlaySounds", "unset")
        if (saved != "unset") {
            config["Feedback"]["PlaySounds"] := (saved = "true")
        }
    }
}

ToggleSounds() {
    global config, prefsPath
    ; Toggle the boolean value in memory
    currentStatus := config["Feedback"]["PlaySounds"]
    newStatus := !currentStatus
    config["Feedback"]["PlaySounds"] := newStatus

    ; Properly save only the PlaySounds key to the [Settings] section
    try {
        IniWrite(newStatus ? "true" : "false", prefsPath, "Settings", "PlaySounds")
    }

    if (newStatus) {
        A_TrayMenu.Check("Sound Feedback")
        try SoundPlay("*48")
        TrayTip("Sounds On", "Sound feedback enabled", "Iconi")
    } else {
        A_TrayMenu.Uncheck("Sound Feedback")
        TrayTip("Sounds Off", "Sound feedback disabled", "Iconi")
    }
}

;------------------------------------------------
; TRIGGER KEYS  (; family for Windows commands, ` family for app launch)
;------------------------------------------------
LoadTriggerPrefs() {
    global prefsPath, config
    if (!FileExist(prefsPath))
        return
    try {
        winCmd := IniRead(prefsPath, "Triggers", "WinCmd", "unset")
        if (winCmd != "unset" && winCmd != "")
            config["Triggers"]["WinCmd"] := winCmd
        appLaunch := IniRead(prefsPath, "Triggers", "AppLaunch", "unset")
        if (appLaunch != "unset" && appLaunch != "")
            config["Triggers"]["AppLaunch"] := appLaunch
    }
}

SaveTriggerPrefs() {
    global prefsPath, config
    try {
        IniWrite(config["Triggers"]["WinCmd"],    prefsPath, "Triggers", "WinCmd")
        IniWrite(config["Triggers"]["AppLaunch"], prefsPath, "Triggers", "AppLaunch")
    }
}

;------------------------------------------------
; MODE: Starter / Full
;------------------------------------------------
LoadModePref() {
    global prefsPath, appMode
    if (!FileExist(prefsPath))
        return
    try {
        saved := IniRead(prefsPath, "Mode", "Level", "starter")
        if (saved = "full")
            appMode := "full"
    }
}

SaveModePref(level) {
    global prefsPath
    try IniWrite(level, prefsPath, "Mode", "Level")
}

UnlockFullMode() {
    global appMode
    if (appMode = "full") {
        TrayTip("Already Unlocked",
                "Full features are already active.", "Iconi")
        return
    }
    msg := "Unlock MultiShortcuts Full?`n`n"
    msg .= "Full mode adds:`n"
    msg .= "  * Custom text expansions and app launchers`n"
    msg .= "  * Edit Shortcuts GUI`n"
    msg .= "  * Capture selected text as expansion`n"
    msg .= "  * Quick Expansion Picker - Undo - Backups`n"
    msg .= "  * CSV import/export - Usage stats`n`n"
    msg .= "All free. The built-in shortcuts you already use will keep working.`n`n"
    msg .= "This is a one-way unlock - Starter mode won't be available after.`n`n"
    msg .= "Continue?"
    if (MsgBox(msg, "Unlock Full Features", "YesNo Icon?") != "Yes")
        return
    SaveModePref("full")
    TrayTip("Unlocking Full Mode",
            "Reloading MultiShortcuts...", "Iconi")
    SetTimer(ReloadScriptSilent, -600)
}

; Validate a candidate trigger character.
; Must be a single character, not whitespace, not used by other families,
; and not a character that breaks hotstring registration.
IsValidTriggerChar(ch, otherTrigger) {
    if (StrLen(ch) != 1)
        return "Trigger must be exactly one character."
    if (ch = " " || ch = "`t")
        return "Trigger cannot be whitespace."
    ; Block characters that would conflict with other families or break parsing.
    ; '=' is reserved by the date/utility family.
    ; '|' is the file separator in the data files.
    ; '"' would break the quoted string in the file.
    reserved := ["=", "|", '"', "/", "\"]
    for , r in reserved {
        if (ch = r)
            return "The character '" . ch . "' is reserved and cannot be used as a trigger."
    }
    if (ch = otherTrigger)
        return "That character is already in use by the other trigger family."
    ; Block plain letters/digits - they'd fire mid-word constantly
    if (RegExMatch(ch, "[A-Za-z0-9]"))
        return "Letters and digits make poor triggers (they fire mid-word).`nUse a punctuation character like comma, period, or tilde."
    return ""  ; empty string = valid
}

ShowTriggerSetup() {
    global config
    curWinCmd    := config["Triggers"]["WinCmd"]
    curAppLaunch := config["Triggers"]["AppLaunch"]

    g := Gui("+ToolWindow", "Trigger Keys Setup")
    g.SetFont("s10", "Segoe UI")
    g.BackColor := "FFFFFF"

    g.Add("Text", "x15 y15 w470",
        "Customize the prefix character for the two built-in shortcut families.`n" .
        "Changes apply on save. Existing shortcuts using the old prefix will be migrated.")

    g.Add("Text", "x15 y65 w200", "Windows Commands family (default semicolon)")
    edWinCmd := g.Add("Edit", "x230 y62 w40 Limit1 Center", curWinCmd)

    g.Add("Text", "x290 y65 w200 cGray", "e.g. semicolon-c = Copy, semicolon-v = Paste")

    g.Add("Text", "x15 y100 w200", "App Launch family (default backtick)")
    edAppLaunch := g.Add("Edit", "x230 y97 w40 Limit1 Center", curAppLaunch)

    g.Add("Text", "x290 y100 w200 cGray", "e.g. backtick-S = Snip, backtick-C = Calc")

    g.Add("Text", "x15 y140 w470 cGray",
        "Tip: avoid letters and digits - they fire in the middle of words.`n" .
        "Good choices: comma, period, tilde, or slash  (each character must be unique)")

    g.Add("Button", "x230 y195 w90 Default", "Save").OnEvent("Click", SaveTriggers)
    g.Add("Button", "x330 y195 w90", "Cancel").OnEvent("Click", (*) => g.Destroy())

    g.OnEvent("Escape", (*) => g.Destroy())
    g.Show("w500 h240")

    SaveTriggers(*) {
        newWin := edWinCmd.Value
        newApp := edAppLaunch.Value

        ; Validate each character (each must be valid against the *other* new value)
        err := IsValidTriggerChar(newWin, newApp)
        if (err != "") {
            MsgBox("Windows Commands trigger:`n`n" . err, "Invalid Trigger", "Icon!")
            return
        }
        err := IsValidTriggerChar(newApp, newWin)
        if (err != "") {
            MsgBox("App Launch trigger:`n`n" . err, "Invalid Trigger", "Icon!")
            return
        }

        ; No-op if nothing changed
        if (newWin = curWinCmd && newApp = curAppLaunch) {
            g.Destroy()
            return
        }

        ; Migrate existing shortcuts that use the old prefixes
        migrated := MigrateTriggerPrefix(curWinCmd, newWin)
                  + MigrateTriggerPrefix(curAppLaunch, newApp)

        config["Triggers"]["WinCmd"]    := newWin
        config["Triggers"]["AppLaunch"] := newApp
        SaveTriggerPrefs()

        ; Re-seed defaults under the new prefixes (won't overwrite anything that exists)
        SeedDefaultExpansions()

        g.Destroy()
        msg := "Triggers updated:`n   Windows Commands: " . newWin
        msg .= "`n   App Launch: " . newApp
        if (migrated > 0)
            msg .= "`n`n" . migrated . " existing shortcut(s) migrated to the new prefix."
        msg .= "`n`nReloading..."
        TrayTip("Trigger Keys Updated", msg, "Iconi")
        SetTimer(ReloadScriptSilent, -800)
    }
}

; Rewrites the appropriate data file to replace oldPrefix with newPrefix on
; built-in family shortcuts. Returns count of shortcuts migrated.
;
; A shortcut is considered a "family member" if it starts with the old prefix
; AND the rest is a single letter, digit, or symbol (everything the seeder uses).
; We migrate from text_expansion.ahk for ; family and launchers.ahk for ` family.
MigrateTriggerPrefix(oldPrefix, newPrefix) {
    global loadedExpansions, loadedLaunchers
    global textExpansionPath, launcherPath
    if (oldPrefix = newPrefix || oldPrefix = "" || newPrefix = "")
        return 0
    total := 0
    total += MigratePrefixIn(loadedExpansions, textExpansionPath, oldPrefix, newPrefix,
                              "; Text Expansion file - Format: shortcut expansion")
    total += MigratePrefixIn(loadedLaunchers, launcherPath, oldPrefix, newPrefix,
                              "; Launcher file - Format: shortcut target")
    return total
}

MigratePrefixIn(dataMap, filePath, oldPrefix, newPrefix, headerComment) {
    count := 0
    newMap := Map()
    for sc, target in dataMap {
        ; Match: oldPrefix followed by exactly one alphanumeric or punctuation char.
        ; We restrict to a single-char suffix so we never touch a user's
        ; multi-character shortcut that happens to start with the prefix.
        if (SubStr(sc, 1, StrLen(oldPrefix)) = oldPrefix
            && StrLen(sc) = StrLen(oldPrefix) + 1) {
            newSc := newPrefix . SubStr(sc, StrLen(oldPrefix) + 1)
            if (!dataMap.Has(newSc) && !newMap.Has(newSc)) {
                newMap[newSc] := target
                count++
                continue
            }
        }
        newMap[sc] := target
    }
    if (count > 0) {
        ; Mutate the original Map in place - clear and refill so the caller's
        ; global variable still points at the same Map object
        dataMap.Clear()
        for k, v in newMap
            dataMap[k] := v
        RewriteFile(filePath, dataMap, headerComment)
    }
    return count
}

;------------------------------------------------
; EDIT GUI
;------------------------------------------------
ShowEditGUI(startTab := "launchers") {
    gEdit := Gui("+Resize +MinSize640x460", "MultiShortcuts v2.0.0 - Manage Shortcuts")
    gEdit.SetFont("s10", "Segoe UI")
    gEdit.BackColor := "F5F5F5"
    tabs := gEdit.Add("Tab3", "x8 y8 w784 h460 +BackgroundF5F5F5",
                      ["Launchers", "Text Expansions"])

    ; --- TAB 1: LAUNCHERS ---
    tabs.UseTab(1)
    gEdit.Add("Text", "x18 y48 w60 h24 +0x200", "Search:")
    searchL := gEdit.Add("Edit", "x80 y46 w260 h24 vSearchL")
    gEdit.Add("Button", "x346 y46 w24 h24", "X")
        .OnEvent("Click", (*) => (searchL.Value := "", RefreshLauncherTab(lvL, searchL, countL)))
    countL := gEdit.Add("Text", "x380 y48 w390 h20 +Right cGray vCountL", "")
    lvL := gEdit.Add("ListView", "x18 y76 w764 h320 Grid +LV0x10000 vLvL",
                     ["Shortcut", "Target", "Type"])
    lvL.ModifyCol(1, "AutoHdr")
    lvL.ModifyCol(2, "Auto")
    lvL.ModifyCol(3, "AutoHdr")
    gEdit.Add("Button", "x18  y406 w110 h26", "&Edit")
        .OnEvent("Click", (*) => EditSelectedRow(lvL, "launchers", gEdit, searchL, countL))
    gEdit.Add("Button", "x134 y406 w110 h26", "&Delete")
        .OnEvent("Click", (*) => DeleteSelectedRow(lvL, "launchers", gEdit, countL))
    gEdit.Add("Button", "x250 y406 w110 h26", "&Add New")
        .OnEvent("Click", (*) => (gEdit.Hide(), AddNewLauncher(), gEdit.Show(),
                                   RefreshLauncherTab(lvL, searchL, countL)))
    gEdit.Add("Button", "x366 y406 w110 h26", "&Test")
        .OnEvent("Click", (*) => TestSelectedRow(lvL, "launchers"))
    gEdit.Add("Button", "x668 y406 w114 h26", "&Reload")
        .OnEvent("Click", (*) => RefreshLauncherTab(lvL, searchL, countL))
    lvL.OnEvent("DoubleClick", (*) => EditSelectedRow(lvL, "launchers", gEdit, searchL, countL))
    lvL.OnEvent("ColClick",    (lv, col) => SortLV(lv, col, "launchers", searchL, countL))
    searchL.OnEvent("Change",  (*) => RefreshLauncherTab(lvL, searchL, countL))

    ; --- TAB 2: EXPANSIONS ---
    tabs.UseTab(2)
    gEdit.Add("Text", "x18 y48 w60 h24 +0x200", "Search:")
    searchE := gEdit.Add("Edit", "x80 y46 w260 h24 vSearchE")
    gEdit.Add("Button", "x346 y46 w24 h24", "X")
        .OnEvent("Click", (*) => (searchE.Value := "", RefreshExpansionTab(lvE, searchE, countE)))
    countE := gEdit.Add("Text", "x380 y48 w390 h20 +Right cGray vCountE", "")
    lvE := gEdit.Add("ListView", "x18 y76 w764 h320 Grid +LV0x10000 vLvE",
                     ["Shortcut", "Expands To"])
    lvE.ModifyCol(1, "AutoHdr")
    lvE.ModifyCol(2, "Auto")
    gEdit.Add("Button", "x18  y406 w110 h26", "&Edit")
        .OnEvent("Click", (*) => EditSelectedRow(lvE, "expansions", gEdit, searchE, countE))
    gEdit.Add("Button", "x134 y406 w110 h26", "&Delete")
        .OnEvent("Click", (*) => DeleteSelectedRow(lvE, "expansions", gEdit, countE))
    gEdit.Add("Button", "x250 y406 w110 h26", "&Add New")
        .OnEvent("Click", (*) => (gEdit.Hide(), AddNewExpansion(), gEdit.Show(),
                                   RefreshExpansionTab(lvE, searchE, countE)))
    gEdit.Add("Button", "x366 y406 w110 h26", "&Test")
        .OnEvent("Click", (*) => TestSelectedRow(lvE, "expansions"))
    gEdit.Add("Button", "x668 y406 w114 h26", "&Reload")
        .OnEvent("Click", (*) => RefreshExpansionTab(lvE, searchE, countE))
    lvE.OnEvent("DoubleClick", (*) => EditSelectedRow(lvE, "expansions", gEdit, searchE, countE))
    lvE.OnEvent("ColClick",    (lv, col) => SortLV(lv, col, "expansions", searchE, countE))
    searchE.OnEvent("Change",  (*) => RefreshExpansionTab(lvE, searchE, countE))

    tabs.UseTab()
    gEdit.Add("Text", "x8 y474 w784 h20 BackgroundE0E0E0 c444444",
              "  Double-click a row to edit   |   Click column header to sort")

    RefreshLauncherTab(lvL, searchL, countL)
    RefreshExpansionTab(lvE, searchE, countE)
    if (startTab = "expansions")
        tabs.Value := 2
    gEdit.OnEvent("Close",  (*) => gEdit.Destroy())
    gEdit.OnEvent("Escape", (*) => gEdit.Destroy())
    gEdit.Show("w800 h500")
}

RefreshLauncherTab(lv, search, countCtrl) {
    global loadedLaunchers
    if (loadedLaunchers.Count = 0)
        LoadLaunchers()
    n := PopulateLauncherList(lv, search.Value)
    countCtrl.Value := n . " launcher" . (n = 1 ? "" : "s")
                     . (search.Value != "" ? " (filtered)" : "")
}

RefreshExpansionTab(lv, search, countCtrl) {
    global loadedExpansions
    if (loadedExpansions.Count = 0)
        LoadTextExpansions()
    n := PopulateExpansionList(lv, search.Value)
    countCtrl.Value := n . " expansion" . (n = 1 ? "" : "s")
                     . (search.Value != "" ? " (filtered)" : "")
}

PopulateLauncherList(lv, filter) {
    global loadedLaunchers
    lv.Delete()
    filter := Trim(filter ?? "")
    count  := 0
    for shortcut, target in loadedLaunchers {
        if (filter != "" && !InStr(shortcut, filter) && !InStr(target, filter))
            continue
        lv.Add("", shortcut, target, LauncherType(target))
        count++
    }
    return count
}

; Label for the Type column. String checks only, so an offline drive
; can't slow the list down. Looks at the program path itself, so quoted
; paths and launchers with arguments are labelled correctly.
LauncherType(target) {
    t := StrLower(Trim(target))
    if (InStr(t, "://") || InStr(t, "mailto:"))
        return "Web/Email"
    if (RegExMatch(t, '^"([^"]+)"', &m))
        t := m[1]
    if (RegExMatch(t, "\.(exe|lnk)(\s|$)"))
        return "App"
    if (RegExMatch(t, "^[a-z][a-z0-9+.\-]+:"))
        return "App"          ; protocol handler such as ms-screenclip:
    return "Document"
}

PopulateExpansionList(lv, filter) {
    global loadedExpansions
    lv.Delete()
    filter := Trim(filter ?? "")
    count  := 0
    for shortcut, expansion in loadedExpansions {
        if (filter != "" && !InStr(shortcut, filter) && !InStr(expansion, filter))
            continue
        lv.Add("", shortcut, StrReplace(StrReplace(expansion, "`r`n", " <- "), "`n", " <- "))
        count++
    }
    return count
}

SortLV(lv, col, dataType, searchCtrl, countCtrl) {
    global lvSortCol, lvSortAsc
    ; Toggle sort direction on repeated column click
    if (lvSortCol[dataType] = col)
        lvSortAsc[dataType] := !lvSortAsc[dataType]
    else {
        lvSortCol[dataType] := col
        lvSortAsc[dataType] := true
    }
    ; Use native Windows ListView sort - no rebuild, no flicker
    if (lvSortAsc[dataType])
        lv.ModifyCol(col, "Sort")
    else
        lv.ModifyCol(col, "SortDesc")
}

EditSelectedRow(lv, dataType, parentGui, searchCtrl, countCtrl) {
    global loadedLaunchers, loadedExpansions, launcherPath, textExpansionPath
    row := lv.GetNext(0, "Focused")
    if (!row)
        row := lv.GetNext()
    if (!row) {
        MsgBox("Please select a row to edit.", "Nothing Selected", "Iconi")
        return
    }
    oldShortcut := lv.GetText(row, 1)
    ; The list shows multi-line expansions with " <- " in place of line
    ; breaks - edit the stored value, not the display copy.
    if (dataType = "launchers")
        oldTarget := loadedLaunchers.Has(oldShortcut) ? loadedLaunchers[oldShortcut] : lv.GetText(row, 2)
    else
        oldTarget := loadedExpansions.Has(oldShortcut) ? loadedExpansions[oldShortcut] : lv.GetText(row, 2)

    gInline := Gui("+Owner" . parentGui.Hwnd . " +ToolWindow", "Edit: " . oldShortcut)
    gInline.SetFont("s10", "Segoe UI")
    gInline.Add("Text", "x10 y12 w110", "Shortcut:")
    editSC := gInline.Add("Edit", "x120 y10 w320 h24", oldShortcut)
    gInline.Add("Text", "x10 y44 w110", dataType = "launchers" ? "Target:" : "Expands To:")
    editVal := gInline.Add("Edit", "x120 y42 w320 h70 +Multi +WantReturn", oldTarget)
    gInline.Add("Button", "x120 y124 w100 h28", "Save")
        .OnEvent("Click", SaveInlineEdit)
    gInline.Add("Button", "x226 y124 w100 h28", "Cancel")
        .OnEvent("Click", (*) => gInline.Destroy())
    gInline.Show("w460 h164")
    editSC.Focus()

    SaveInlineEdit(*) {
        newShortcut := Trim(editSC.Value)
        ; Keep intentional leading/trailing spaces in expansions
        newTarget   := (dataType = "launchers") ? Trim(editVal.Value) : editVal.Value
        if (newShortcut = "" || Trim(newTarget) = "") {
            MsgBox("Both fields are required.", "Validation", "Icon!")
            return
        }
        if (!IsValidShortcut(newShortcut)) {
            MsgBox("Invalid shortcut name.", "Validation", "Icon!")
            return
        }
        if (dataType = "launchers") {
            if (!IsAllowedTarget(newTarget))
                return
            if (oldShortcut != newShortcut)
                loadedLaunchers.Delete(oldShortcut)
            loadedLaunchers[newShortcut] := newTarget
            RewriteFile(launcherPath, loadedLaunchers, "; Launcher file - Format: shortcut target")
            LoadLaunchers()
            RefreshLauncherTab(lv, searchCtrl, countCtrl)
        } else {
            if (oldShortcut != newShortcut)
                loadedExpansions.Delete(oldShortcut)
            loadedExpansions[newShortcut] := newTarget
            RewriteFile(textExpansionPath, loadedExpansions, "; Text Expansion file - Format: shortcut expansion")
            LoadTextExpansions()
            RefreshExpansionTab(lv, searchCtrl, countCtrl)
        }
        gInline.Destroy()
        TrayTip("Saved", newShortcut . " updated", "Iconi")
    }
}

DeleteSelectedRow(lv, dataType, parentGui, countCtrl) {
    global loadedLaunchers, loadedExpansions, launcherPath, textExpansionPath
    row := lv.GetNext(0, "Focused")
    if (!row)
        row := lv.GetNext()
    if (!row) {
        MsgBox("Please select a row to delete.", "Nothing Selected", "Iconi")
        return
    }
    shortcut := lv.GetText(row, 1)
    if (MsgBox("Delete '" . shortcut . "'?`n`nThis cannot be undone.",
               "Confirm Delete", "YesNo Icon!") != "Yes")
        return
    if (dataType = "launchers") {
        loadedLaunchers.Delete(shortcut)
        RewriteFile(launcherPath, loadedLaunchers, "; Launcher file - Format: shortcut target")
        LoadLaunchers()
        RefreshLauncherTab(lv, {Value:""}, countCtrl)
    } else {
        loadedExpansions.Delete(shortcut)
        RewriteFile(textExpansionPath, loadedExpansions, "; Text Expansion file - Format: shortcut expansion")
        LoadTextExpansions()
        RefreshExpansionTab(lv, {Value:""}, countCtrl)
    }
    TrayTip("Deleted", "'" . shortcut . "' removed", "Iconi")
}

TestSelectedRow(lv, dataType) {
    row := lv.GetNext(0, "Focused")
    if (!row)
        row := lv.GetNext()
    if (!row) {
        MsgBox("Please select a row to test.", "Nothing Selected", "Iconi")
        return
    }
    shortcut := lv.GetText(row, 1)
    target   := lv.GetText(row, 2)
    if (dataType = "launchers") {
        if (MsgBox("Launch:`n" . target . "`n`nProceed?", "Test: " . shortcut, "YesNo Iconi") = "Yes")
            LaunchTarget(target, shortcut)
    } else {
        MsgBox("This expansion would type:`n`n" . target, "Preview: " . shortcut, "Iconi")
    }
}

;------------------------------------------------
; HELP WINDOW
;------------------------------------------------
ShowHelp() {
    global appMode
    if (appMode = "starter") {
        ShowStarterHelp()
        return
    }
    ShowFullHelp()
}

; Help screens describe the user's actual shortcuts, not the factory
; defaults - people change these (and existing entries are never
; overwritten by the built-in seeds).

; Rows for the ` family: every launcher that is the trigger plus one character
AppLaunchHelpRows() {
    global loadedLaunchers, config
    al   := config["Triggers"]["AppLaunch"]
    rows := []
    for sc, target in loadedLaunchers {      ; Map order: digits, A-Z, a-z
        if (StrLen(sc) = StrLen(al) + 1 && SubStr(sc, 1, StrLen(al)) = al)
            rows.Push([sc, LauncherLabel(target)])
    }
    if (rows.Length = 0)
        rows.Push([al . "?", "No quick launchers set up"])
    return rows
}

; Short, readable name for a launcher target
LauncherLabel(target) {
    static known := Map("calc.exe", "Calculator", "ms-screenclip:", "Snip Tool")
    t := Trim(target)
    if (known.Has(StrLower(t)))
        return known[StrLower(t)]
    if (RegExMatch(t, "i)^https?://(?:www\.)?([^/?#]+)", &m))
        return m[1]                               ; e.g. claude.ai
    if (RegExMatch(t, "i)^mailto:(.+)$", &m))
        return "Email " . m[1]
    SplitTarget(t, &path, &args)
    SplitPath(path, &name, , , &nameNoExt)
    return (nameNoExt != "") ? nameNoExt : t
}

; What an expansion produces today. Only date/time placeholders are filled
; in - anything else ({clip}, {prompt}, {key}...) is shown as written, so
; opening Help never reads the clipboard or pops up a question.
ExpansionPreview(sc) {
    global loadedExpansions
    if (!loadedExpansions.Has(sc))
        return "(not set)"
    val := loadedExpansions[sc]
    if (RegExMatch(val, "\{(?!(?:date|time|day|month|year)\b)[^}]*\}"))
        return val
    return ResolvePlaceholders(val)
}

ShowStarterHelp() {
    global config, holdKeysOn, capsKeyOn, mouseKeyOn, mouseKeyMode
    wc := config["Triggers"]["WinCmd"]
    al := config["Triggers"]["AppLaunch"]

    gHelp := Gui("+ToolWindow", "MultiShortcuts (Starter) - Built-in Shortcuts")
    gHelp.SetFont("s10", "Segoe UI")
    gHelp.BackColor := "FFFFFF"
    title := gHelp.Add("Text", "x0 y0 w560 h40 +0x200 Background1A1A2E cWhite Center",
                        "  MultiShortcuts v2.0.0 - Starter Mode  ")
    title.SetFont("s12 Bold", "Segoe UI")

    sections := [
        [holdKeysOn ? "HOLD KEYS  (on)" : "HOLD KEYS  (off - turn on in the tray menu)", [
            ["hold `;",  "Ctrl + next key   (hold `; + C = copy)"],
            ["hold ``",  "Alt + next key"],
            ["Caps Lock", capsKeyOn  ? "tap = ``,  hold = Alt" : "normal   (option in tray menu)"],
            ["Middle btn", !mouseKeyOn ? "normal   (change in tray menu)"
                         : mouseKeyMode = "alt" ? "click = ``  hold = Alt  Shift = normal" : "click = `;  hold = Ctrl  Shift = normal"]
        ]],
        ["; WINDOWS COMMANDS", [
            [wc . "c",  "Copy"],
            [wc . "x",  "Cut"],
            [wc . "v",  "Paste"],
            [wc . "z",  "Undo  /  " . wc . "y  Redo"],
            [wc . "a",  "Select All  /  " . wc . "A  Select All and Copy"],
            [wc . "f",  "Find  /  " . wc . "h  Find & Replace"],
            [wc . "s",  "Save  /  " . wc . "S  Save As"],
            [wc . "o",  "Open  /  " . wc . "n  New"],
            [wc . "p",  "Print  /  " . wc . "w  Close tab"],
            [wc . "r",  "Refresh (F5)"],
            [wc . "8",  "Emoji picker (Win+.)"],
            [wc . "k",  "Task Manager  /  " . wc . "L  Lock PC  /  " . wc . "m  Minimize"],
            [wc . "g",  "Go to line"]
        ]],
        ["; DOCUMENT NAVIGATION", [
            [wc . "t",  "Top of page"],
            [wc . "b",  "Bottom of page"],
            [wc . "u",  "Page Up  /  " . wc . "d  Page Down"],
            [wc . "l",  "Line start  /  " . wc . "e  Line end"],
            [wc . "<",  "Snap window left  /  " . wc . ">  Snap window right"]
        ]],
        ["`` APP LAUNCH (case-sensitive)", AppLaunchHelpRows()],
        ["= DATES & UTILITY", [
            ["-=",   "Today:  " . ExpansionPreview("-=")],
            ["=-",   "Today (short):  " . ExpansionPreview("=-")],
            ["1-=",  "1 week  /  2-=  2 weeks  /  1m=  1 month  /  1y=  1 year"],
            ["r=",   "F5 Refresh  /  f=  F11 Fullscreen  /  d=  F12 Dev tools"],
            ["s=",   "Ctrl+S Save  /  t=  Ctrl+T New tab"]
        ]]
    ]

    y := 50
    for si, section in sections {
        heading := gHelp.Add("Text", "x10 y" . y . " w540 h22 c1A1A2E", section[1])
        heading.SetFont("s10 Bold", "Segoe UI")
        y += 24
        gHelp.Add("Text", "x10 y" . y . " w540 h1 Background808080")
        y += 6
        for , row in section[2] {
            keyCtrl := gHelp.Add("Text",
                "x14 y" . y . " w80 h20 BackgroundE8EAF6 c1A1A2E Center", row[1])
            keyCtrl.SetFont("s9 Bold", "Consolas")
            gHelp.Add("Text", "x102 y" . (y+1) . " w440 h20 c444444", row[2])
            y += 24
        }
        y += 10
    }

    y += 4
    unlockBg := gHelp.Add("Text", "x10 y" . y . " w540 h60 BackgroundFFFDE7")
    unlockText := gHelp.Add("Text", "x18 y" . (y+8) . " w524 h50 BackgroundFFFDE7 c555500",
        "Ready for more? * Unlock Full Features from the tray menu - `n" .
        "add your own shortcuts, customize anything, full editor GUI.")
    y += 68
    gHelp.Add("Text", "x10 y" . y . " w540 h18 cAAAAAA Center",
        "(c) GnuKey LLC  -  Built-in shortcuts always work in Starter and Full modes")
    y += 22
    gHelp.Add("Button", "x230 y" . y . " w100 h30", "Close")
        .OnEvent("Click", (*) => gHelp.Destroy())
    gHelp.OnEvent("Close",  (*) => gHelp.Destroy())
    gHelp.OnEvent("Escape", (*) => gHelp.Destroy())
    gHelp.Show("w560 h" . (y + 44))
}

ShowFullHelp() {
    global config, holdKeysOn, capsKeyOn, mouseKeyOn, mouseKeyMode
    hk := config["Hotkeys"]
    gHelp := Gui("+ToolWindow", "Help - MultiShortcuts v2.0.0")
    gHelp.SetFont("s10", "Segoe UI")
    gHelp.BackColor := "FFFFFF"
    title := gHelp.Add("Text", "x0 y0 w500 h40 +0x200 Background1A1A2E cWhite Center",
                        "  MultiShortcuts v2.0.0  ")
    title.SetFont("s12 Bold", "Segoe UI")
    sections := [
        [holdKeysOn ? "HOLD KEYS  (on)" : "HOLD KEYS  (off - turn on in the tray menu)", [
            ["hold `;",  "Ctrl + next key   (hold `; + C = copy)"],
            ["hold ``",  "Alt + next key"],
            ["Caps Lock", capsKeyOn  ? "tap = ``,  hold = Alt" : "normal   (option in tray menu)"],
            ["Middle btn", !mouseKeyOn ? "normal   (change in tray menu)"
                         : mouseKeyMode = "alt" ? "click = ``  hold = Alt  Shift = normal" : "click = `;  hold = Ctrl  Shift = normal"]
        ]],
        ["ADD NEW SHORTCUTS", [
            [hk["AddExpansion"],        "Add Text Expansion"],
            [hk["AddLauncher"],         "Add App Launcher"],
            [hk["AddDocumentLauncher"], "Add Document Launcher"],
            [hk["AddWebLauncher"],      "Add Web/Email Launcher"],
            [hk["CaptureExpansion"],    "Capture Selected Text as Expansion"]
        ]],
        ["MANAGE AND VIEW", [
            [hk["ShowEditGUI"],         "Edit Shortcuts (full GUI)"],
            [hk["ManageLaunchers"],     "Manage Launchers"],
            [hk["ManageExpansions"],    "Manage Text Expansions"],
            [hk["ReloadScript"],        "Reload Script"]
        ]],
        ["FEATURES", [
            [hk["QuickTextExpansion"],  "Quick Expansion Picker"],
            [hk["UndoExpansion"],       "Undo Last Expansion"],
            [hk["ImmediateBackup"],     "Backup Both Files Now"],
            [hk["PauseResume"],         "Pause / Resume All Macros"],
            [hk["SnipTool"],            "Snip Tool (Win+Shift+S)"],
            [hk["ShowHelp"],            "This Help Screen"]
        ]],
        ["= SHORTCUT FAMILY", [
            ["-=",   "Today:  " . ExpansionPreview("-=")],
            ["=-",   "Today (short):  " . ExpansionPreview("=-")],
            ["1-=",  "One week from today"],
            ["2-=",  "Two weeks from today"],
            ["1m=",  "One month from today"],
            ["1y=",  "One year from today"],
            ["r=",   "F5 - Refresh"],
            ["f=",   "F11 - Fullscreen"],
            ["s=",   "Ctrl+S - Save"],
            ["t=",   "Ctrl+T - New tab"]
        ]],
        ["; WINDOWS COMMANDS", [
            [config["Triggers"]["WinCmd"] . "c",  "Copy  /  " . config["Triggers"]["WinCmd"] . "x  Cut  /  " . config["Triggers"]["WinCmd"] . "v  Paste"],
            [config["Triggers"]["WinCmd"] . "z",  "Undo  /  " . config["Triggers"]["WinCmd"] . "y  Redo"],
            [config["Triggers"]["WinCmd"] . "a",  "Select All  /  " . config["Triggers"]["WinCmd"] . "A  Select All + Copy"],
            [config["Triggers"]["WinCmd"] . "f",  "Find  /  " . config["Triggers"]["WinCmd"] . "h  Find & Replace"],
            [config["Triggers"]["WinCmd"] . "s",  "Save  /  " . config["Triggers"]["WinCmd"] . "S  Save As  /  " . config["Triggers"]["WinCmd"] . "o  Open  /  " . config["Triggers"]["WinCmd"] . "n  New"],
            [config["Triggers"]["WinCmd"] . "p",  "Print  /  " . config["Triggers"]["WinCmd"] . "w  Close tab"],
            [config["Triggers"]["WinCmd"] . "r",  "Refresh (F5)"],
            [config["Triggers"]["WinCmd"] . "8",  "Emoji picker  /  " . config["Triggers"]["WinCmd"] . "g  Go to line"],
            [config["Triggers"]["WinCmd"] . "k",  "Task Manager  /  " . config["Triggers"]["WinCmd"] . "L  Lock PC  /  " . config["Triggers"]["WinCmd"] . "m  Minimize"]
        ]],
        ["; DOCUMENT NAVIGATION", [
            [config["Triggers"]["WinCmd"] . "t",  "Top of page"],
            [config["Triggers"]["WinCmd"] . "b",  "Bottom of page"],
            [config["Triggers"]["WinCmd"] . "u",  "Page Up  /  " . config["Triggers"]["WinCmd"] . "d  Page Down"],
            [config["Triggers"]["WinCmd"] . "l",  "Line start  /  " . config["Triggers"]["WinCmd"] . "e  Line end"],
            [config["Triggers"]["WinCmd"] . "<",  "Snap left  /  " . config["Triggers"]["WinCmd"] . ">  Snap right"]
        ]],
        ["`` QUICK APP LAUNCH (case-sensitive)", AppLaunchHelpRows()]
    ]
    y := 50
    for si, section in sections {
        heading := gHelp.Add("Text", "x10 y" . y . " w480 h22 c1A1A2E", section[1])
        heading.SetFont("s10 Bold", "Segoe UI")
        y += 24
        gHelp.Add("Text", "x10 y" . y . " w480 h1 Background808080")
        y += 6
        ; Wider, plain labels for hold keys (section 1) and the =, ;, and ` family
        ; sections (section 5 onward); Alt-key hotkeys in between are formatted
        labelW := (si = 1 || si >= 5) ? 170 : 110
        descX  := (si = 1 || si >= 5) ? 192 : 132
        descW  := (si = 1 || si >= 5) ? 290 : 350
        for , row in section[2] {
            label   := (si = 1 || si >= 5) ? row[1] : HotkeyLabel(row[1])
            keyCtrl := gHelp.Add("Text",
                "x14 y" . y . " w" . labelW . " h20 BackgroundE8EAF6 c1A1A2E Center", label)
            keyCtrl.SetFont("s9 Bold", "Consolas")
            gHelp.Add("Text", "x" . descX . " y" . (y+1) . " w" . descW . " h20 c444444", row[2])
            y += 26
        }
        y += 10
    }
    gHelp.Add("Text", "x10 y" . y . " w480 h1 Background808080")
    y += 8
    extras := ["Usage Statistics", "Export/Import CSV",
               "Run on Windows Startup", "Backups auto-saved to .\backups\"]
    for item in extras {
        gHelp.Add("Text", "x20 y" . y . " w460 h18 c555555", "  " . item)
        y += 20
    }
    y += 8
    tipBg := gHelp.Add("Text", "x10 y" . y . " w480 h74 BackgroundFFFDE7")
    gHelp.Add("Text", "x18 y" . (y+5) . " w468 h86 BackgroundFFFDE7 c555500",
              "TIP: Type your shortcut anywhere - it triggers automatically.`n" .
              "     Alt+C captures selected text instantly.`n" .
              "     Use {date:dd/MM/yyyy} or {time:h:mm tt} for custom formats.`n" .
              "     = family: r= refresh  f= fullscreen  s= save  t= new tab`n" .
              "               1-= 1 week from today  2-= 2 weeks  1m= 1 month`n" .
              "     Sequences: {key:{Tab}} = Tab, {key:^s} = Ctrl+S`n" .
              "               {wait:500} = pause, {focus:Notepad} = switch window")
    y += 96
    gHelp.Add("Text", "x10 y" . y . " w480 h1 Background808080")
    y += 6
    gHelp.Add("Text", "x10 y" . y . " w480 h18 cAAAAAA Center",
              "(c) GnuKey LLC  -  Implementation: Claude (Anthropic)  -  Review: Gemini (Google)")
    y += 22
    gHelp.Add("Button", "x190 y" . y . " w120 h30", "Close")
        .OnEvent("Click", (*) => gHelp.Destroy())
    gHelp.OnEvent("Close",  (*) => gHelp.Destroy())
    gHelp.OnEvent("Escape", (*) => gHelp.Destroy())
    gHelp.Show("w500 h" . (y + 44))
}

;------------------------------------------------
; LAUNCHER LOADING - CORRECTED WITH CALLBACK FACTORY
;------------------------------------------------
MakeLaunchCallback(t, s) {
    ; Factory: Returns a fresh closure that captures THESE specific values
    return (*) => LaunchTarget(t, s)
}

LoadLaunchers() {
    global launcherPath, loadedLaunchers, registeredLaunchers
    ; This prevents leaks when a shortcut is renamed in the file
    for sc in registeredLaunchers {
        try Hotstring(GetHotstringOptions(sc) . sc, , "Off")
    }
    registeredLaunchers := []
    loadedLaunchers.Clear()

    if (!FileExist(launcherPath)) {
        TrayTip("Launchers", "No launcher file found - creating empty one.", "Iconi")
        return
    }

    try {
        content := FileRead(launcherPath, "UTF-8")
        count := 0

        for line in StrSplit(content, "`n", "`r") {
            line := Trim(line)
            if (line = "" || SubStr(line, 1, 2) = ";;" || SubStr(line, 1, 2) = "; ")
                continue

            if (InStr(line, " ")) {
                parts := StrSplit(line, " ", , 2)
                if (parts.Length >= 2) {
                    shortcut := Trim(parts[1])
                    target   := StrReplace(Trim(parts[2]), "[NEWLINE]", "`n")

                    if (shortcut != "" && target != "" && IsValidShortcut(shortcut, false)) {
                        ; Store in map
                        loadedLaunchers[shortcut] := target
                        count++

                        ; Use FACTORY to create a closure that captures THESE values only
                        callback := MakeLaunchCallback(target, shortcut)

                        try {
                            Hotstring(GetHotstringOptions(shortcut) . shortcut, callback)
                            registeredLaunchers.Push(shortcut)  ; Fix 4: track for clean reload
                        } catch Error as e {
                            MsgBox("Failed to register " . shortcut . "`nError: " . e.Message, "Hotstring Error", "Icon!")
                        }
                    }
                }
            }
        }

    } catch Error as err {
        MsgBox("Error loading launchers: " . err.Message . "`nFile preview: " . SubStr(content, 1, 200), "Load Error", "Icon!")
    }
    UpdateTrayTooltip()
}

;------------------------------------------------
; LAUNCH TARGET
;------------------------------------------------
LaunchTarget(target, shortcut := "") {
    target := Trim(target)
    ; Re-check every time a launcher fires (see IsAllowedTarget)
    if (!IsAllowedTarget(target, "launch"))
        return
    if (shortcut != "")
        TrackUsage(shortcut, "launcher")

    try {
        if (RegExMatch(target, "i)^[a-z][a-z0-9+.\-]+:")) {
            ; Web link, email or protocol handler
            Run(target)
        } else {
            SplitTarget(target, &path, &args)
            ; Fail fast on a missing file or offline drive instead of a
            ; long freeze or a vague Windows error
            if (InStr(path, "\") && !FileExist(path)) {
                PlayFeedback("ErrorSound")
                MsgBox("Target not found - it may be offline or the path has moved.`n`n" .
                       path, "Launch Error", "Icon!")
                return
            }
            Run('"' . path . '"' . (args != "" ? " " . args : ""))
        }
        PlayFeedback("LaunchSound")
    } catch Error as err {
        PlayFeedback("ErrorSound")
        MsgBox("Could not launch: " . target . "`n`nError: " . err.Message,
               "Launch Error", "Icon!")
    }
}

;------------------------------------------------
; TEXT EXPANSION LOADING
;------------------------------------------------
MakeExpansionCallback(text, sc) {
    return (*) => DoExpand(text, sc)
}

DoExpand(text, sc) {
    global config

    ; ── Step 1: protect sequence tokens before running ResolvePlaceholders ───
    ; Scan character-by-character to correctly handle nested braces like
    ; {key:{Tab}} without confusing the placeholder resolver.
    seqTokens := []
    protected := ""
    i := 1
    textLen := StrLen(text)
    loop {
        if (i > textLen)
            break
        ch := SubStr(text, i, 1)
        if (ch = "{") {
            rest := SubStr(text, i)
            if (RegExMatch(rest, "^\{(key|wait|focus):")) {
                depth := 0
                j := i
                loop {
                    if (j > textLen) {
                        depth := 0  ; force safe exit on malformed/unclosed brace
                        break
                    }
                    c := SubStr(text, j, 1)
                    if (c = "{")
                        depth++
                    else if (c = "}")
                        depth--
                    j++
                    if (depth = 0)
                        break
                }
                fullTok := SubStr(text, i, j - i)
                seqTokens.Push(fullTok)
                protected .= "##SEQ" . seqTokens.Length . "##"
                i := j
                continue
            }
        }
        protected .= ch
        i++
    }

    ; ── Step 2: resolve non-sequence placeholders ────────────────────────────
    resolved := ResolvePlaceholders(protected)

    ; ── Step 3: restore sequence tokens ──────────────────────────────────────
    for idx, tok in seqTokens
        resolved := StrReplace(resolved, "##SEQ" . idx . "##", tok)

    TrackUsage(sc, "expansion")
    PlayFeedback("ExpandSound")

    ; ── Step 4: type it ──────────────────────────────────────────────────────
    ;   Sequence tokens recognised:
    ;     {key:X}         – send keystroke X (any AHK Send key notation)
    ;     {wait:N}        – sleep N milliseconds
    ;     {focus:Title}   – activate window whose title contains Title
    ;
    ;   A short pause (SequenceDelay) is inserted before every {key:} and
    ;   {focus:} so the target application has time to open dialogs or move focus.
    ;
    ;   A space is typed after the text (the trigger's own ending space is
    ;   suppressed). In a sequence, the space only follows the final text.
    ; ─────────────────────────────────────────────────────────────────────────

    hasSequence := (InStr(resolved, "{key:") || InStr(resolved, "{wait:") || InStr(resolved, "{focus:"))

    if (!hasSequence) {
        ; ── Simple (no-sequence) path ───────────────────────────────────────
        cursorPos := TakeCursorMarker(&resolved)
        if (resolved = "")
            return
        SendExpandText(resolved, config, true)
        if (cursorPos > 0)
            Send("{Left " . (cursorPos + 1) . "}")   ; +1 for the trailing space
        ; Undo deletes exactly what was typed. Once the caret has moved
        ; back into the text, backspacing would delete the wrong characters.
        RecordExpansionHistory(sc, sc, cursorPos > 0 ? -1 : StrLen(resolved) + 1)
        return
    }

    ; ── Sequence path ────────────────────────────────────────────────────────
    ; Walk character-by-character through resolved, collecting text segments
    ; and sequence tokens, then execute them in order.

    si        := 1
    sLen      := StrLen(resolved)
    textAccum := ""

    loop {
        if (si > sLen)
            break
        sch := SubStr(resolved, si, 1)

        ; Check for a sequence token starting here
        if (sch = "{") {
            srest := SubStr(resolved, si)
            if (RegExMatch(srest, "^\{(key|wait|focus):")) {
                ; Consume full token using brace depth
                sdepth := 0
                sj := si
                loop {
                    sc2 := SubStr(resolved, sj, 1)
                    if (sc2 = "{")
                        sdepth++
                    else if (sc2 = "}")
                        sdepth--
                    sj++
                    if (sdepth = 0 || sj > sLen + 1)
                        break
                }
                seqTok := SubStr(resolved, si, sj - si)

                ; Flush text typed before this token - no trailing space here.
                ; ({cursor} only works in the final text of a sequence.)
                if (textAccum != "") {
                    TakeCursorMarker(&textAccum)
                    if (textAccum != "")
                        SendExpandText(textAccum, config, false)
                    textAccum := ""
                }

                ; Parse and execute the token
                ; seqTok is like {key:VALUE} or {wait:500} or {focus:Title}
                if (!RegExMatch(seqTok, "^\{(key|wait|focus):(.+)\}$", &stok)) {
                    si := sj
                    continue  ; skip malformed token silently
                }
                stokType  := stok[1]
                stokValue := Trim(stok[2])
                if (stokValue = "") {
                    si := sj
                    continue  ; skip empty value token
                }

                if (stokType = "key") {
                    Sleep(config["Performance"]["SequenceDelay"])
                    Send(stokValue)
                } else if (stokType = "wait") {
                    ms := IsInteger(stokValue) ? Integer(stokValue) : 0
                    if (ms > 0)
                        Sleep(ms)
                } else if (stokType = "focus") {
                    Sleep(config["Performance"]["SequenceDelay"])
                    try {
                        WinActivate("ahk_exe " . stokValue)
                    } catch {
                        try WinActivate(stokValue)
                    }
                    try WinWaitActive(stokValue, , 0.5)
                }

                si := sj
                continue
            }
        }

        textAccum .= sch
        si++
    }

    ; Final text gets the trailing space and may position the caret
    cursorPos := 0
    if (textAccum != "") {
        cursorPos := TakeCursorMarker(&textAccum)
        if (textAccum != "")
            SendExpandText(textAccum, config, true)
    }
    if (cursorPos > 0)
        Send("{Left " . (cursorPos + 1) . "}")

    ; Sequences send keystrokes that can't be reversed by backspacing
    RecordExpansionHistory(sc, sc, -1)
}

; Removes a {cursor} or {cursor:N} marker from text and returns how many
; characters left of the end of the text the caret should go (0 = none).
TakeCursorMarker(&text) {
    if (!RegExMatch(text, "\{cursor(?::(\d+))?\}", &m))
        return 0
    if (m[1] != "")
        pos := Integer(m[1])
    else
        pos := StrLen(text) - m.Pos + 1 - m.Len
    text := SubStr(text, 1, m.Pos - 1) . SubStr(text, m.Pos + m.Len)
    ; Any further markers are ignored
    text := RegExReplace(text, "\{cursor(?::\d+)?\}")
    return pos
}

; Puts text on the clipboard while asking Windows to keep it out of
; clipboard history (Win+V) and cloud clipboard sync - expansions may
; contain private information. Falls back to a normal copy on failure.
SetClipboardPrivate(txt) {
    opened := false
    loop 5 {
        if (DllCall("OpenClipboard", "Ptr", A_ScriptHwnd)) {
            opened := true
            break
        }
        Sleep(20)
    }
    if (!opened) {
        A_Clipboard := txt
        return
    }
    try {
        DllCall("EmptyClipboard")
        ; The text itself (CF_UNICODETEXT = 13)
        hText := DllCall("GlobalAlloc", "UInt", 0x42, "UPtr", (StrLen(txt) + 1) * 2, "Ptr")
        pText := DllCall("GlobalLock", "Ptr", hText, "Ptr")
        StrPut(txt, pText, "UTF-16")
        DllCall("GlobalUnlock", "Ptr", hText)
        if (!DllCall("SetClipboardData", "UInt", 13, "Ptr", hText, "Ptr")) {
            DllCall("GlobalFree", "Ptr", hText)
            throw Error("SetClipboardData failed")
        }
        ; Privacy markers recognised by Windows 10/11 clipboard history
        for , fmtName in ["ExcludeClipboardContentFromMonitorProcessing",
                          "CanIncludeInClipboardHistory",
                          "CanUploadToCloudClipboard"] {
            fmt  := DllCall("RegisterClipboardFormat", "Str", fmtName, "UInt")
            hVal := DllCall("GlobalAlloc", "UInt", 0x42, "UPtr", 4, "Ptr")   ; zeroed DWORD = "no"
            if (fmt && hVal && !DllCall("SetClipboardData", "UInt", fmt, "Ptr", hVal, "Ptr"))
                DllCall("GlobalFree", "Ptr", hVal)
        }
        DllCall("CloseClipboard")
    } catch {
        DllCall("CloseClipboard")
        A_Clipboard := txt
    }
}

; Types a chunk of text by pasting it, then restores the user's clipboard
SendExpandText(txt, cfg, addSpace := true) {
    tail := addSpace ? " " : ""
    savedClip := ClipboardAll()
    SetClipboardPrivate(txt)
    if (ClipWait(1)) {
        Send("^v")
        Sleep(150)          ; let the target app process the paste
        if (addSpace)
            Send(" ")       ; space as a separate keystroke - not trimmed by the app
        Sleep(100)          ; slow apps (RDP, Electron) may still be reading the clipboard
    } else {
        ; Clipboard unavailable - type the text instead ({Text} mode, so
        ; characters like ! ^ + { } are typed literally)
        if (StrLen(txt) > cfg["Performance"]["LargeTextThreshold"])
            SendEvent("{Text}" . txt . tail)
        else
            SendText(txt . tail)
    }
    A_Clipboard := savedClip
}

; Placeholder registry
global placeholderRegistry := Map(
    "clip",   (fmt) => SanitizedClip(fmt),
    "date",   (fmt) => fmt = "locale" ? FormatTime(, "ShortDate")
                     : RegExMatch(fmt, "^\+(\d+):(.+)$", &m) ? FormatTime(DateAdd(A_Now, Integer(m[1]), "Days"), m[2])
                     : RegExMatch(fmt, "^\+(\d+)$", &m)       ? FormatTime(DateAdd(A_Now, Integer(m[1]), "Days"), "MMMM d, yyyy")
                     : fmt != ""      ? SafeFormatTime(fmt)
                     :                  FormatTime(, "yyyy-MM-dd"),
    "time",   (fmt) => fmt != "" ? SafeFormatTime(fmt) : FormatTime(, "HH:mm"),
    "day",    (fmt) => FormatTime(, "dddd"),
    "month",  (fmt) => FormatTime(, "MMMM"),
    "year",   (fmt) => FormatTime(, "yyyy"),
    "user",   (fmt) => A_UserName,
    "comp",   (fmt) => A_ComputerName,
    "cursor", (fmt) => "",
    "prompt", (fmt) => PromptDuringExpansion(fmt)
)

; ── Clipboard sanitization ────────────────────────────────────────────────
; The {clip} placeholder reads from whatever happens to be on the clipboard.
; Hostile content (e.g. an attacker who got a user to copy a string from a
; malicious page) could embed shell commands or scripting URIs that, if
; pasted into the wrong target, would execute.
;
; This wrapper applies the formatter (trim/lower/upper/length) as before,
; then checks the result for known-dangerous patterns. If something looks
; risky, the user is prompted before the expansion fires. The check is
; deliberately a *warning*, not a hard block - many legitimate clipboard
; contents look unusual (URLs, file paths, code snippets), and we don't
; want false positives to silently mangle the user's text.
SanitizedClip(fmt) {
    raw := A_Clipboard
    ; Apply formatter first
    if (fmt = "trim")
        out := Trim(raw)
    else if (fmt = "lower")
        out := StrLower(raw)
    else if (fmt = "upper")
        out := StrUpper(raw)
    else if (fmt != "" && RegExMatch(fmt, "^\d+$"))
        out := SubStr(raw, 1, Integer(fmt))
    else
        out := raw

    ; Scan for command-injection patterns. Case-insensitive substring match.
    ; These are the prefixes a script would use to execute something - the
    ; user almost never wants these pasted from {clip}.
    dangerous := ["cmd.exe", "powershell", "rundll32", "mshta",
                  "javascript:", "vbscript:", "data:text/html",
                  "ms-msdt:", "file:///", "about:", "wscript", "cscript"]
    hit := ""
    low := StrLower(out)
    for , pat in dangerous {
        if (InStr(low, pat)) {
            hit := pat
            break
        }
    }
    if (hit = "")
        return out

    ; Suspicious content found - ask the user before proceeding
    preview := SubStr(out, 1, 80)
    if (StrLen(out) > 80)
        preview .= "..."
    msg := "Your clipboard contains a pattern that looks like a command:`n`n"
    msg .= "  Detected: " . hit . "`n"
    msg .= "  Preview:  " . preview . "`n`n"
    msg .= "Paste this clipboard content anyway?"
    result := MsgBox(msg, "Clipboard Safety Check", "YesNo Icon!")
    if (result = "Yes")
        return out
    return ""
}

SafeFormatTime(fmt) {
    try {
        return FormatTime(, fmt)
    } catch {
        return "{" . fmt . "}"
    }
}

PromptDuringExpansion(fmt) {
    if (fmt = "")
        return ""
    parts    := StrSplit(fmt, "|", , 2)
    question := Trim(parts[1])
    default  := parts.Length > 1 ? Trim(parts[2]) : ""
    IB := InputBox(question, "Input Required", "w360 h130", default)
    if (IB.Result = "Cancel")
        return ""
    return IB.Value
}

ResolvePlaceholders(text, depth := 0) {
    global placeholderRegistry
    ; Recursion guard: a {clip} containing {date} containing {clip}… would
    ; otherwise loop. Ten is well past anything legitimate; nested resolves
    ; in normal use bottom out within 1–2.
    if (depth > 10) {
        TrayTip("Expansion Limit",
                "Placeholder expansion exceeded 10 levels - stopping.", "Iconi")
        return "[RECURSION LIMIT]"
    }
    result := text
    for name, handler in placeholderRegistry {
        pattern := "\{" . name . ":([^}]+)\}"
        startPos := 1
        loop {
            foundPos := RegExMatch(result, pattern, &m, startPos)
            if (!foundPos)
                break
            replacement := handler.Call(m[1])
            ; If the replacement contains further placeholders, recurse
            ; with an incremented depth counter.
            if (InStr(replacement, "{") && InStr(replacement, "}"))
                replacement := ResolvePlaceholders(replacement, depth + 1)
            result := SubStr(result, 1, foundPos - 1) . replacement . SubStr(result, foundPos + StrLen(m[0]))
            startPos := foundPos + StrLen(replacement)
        }
        ; Bare {name} form (no formatter)
        if (InStr(result, "{" . name . "}")) {
            replacement := handler.Call("")
            if (InStr(replacement, "{") && InStr(replacement, "}"))
                replacement := ResolvePlaceholders(replacement, depth + 1)
            result := StrReplace(result, "{" . name . "}", replacement)
        }
    }
    return result
}

LoadTextExpansions() {
    global textExpansionPath, loadedExpansions, registeredExpansions, instantExpansions
    ; Disable previously registered hotstrings using stored options
    for sc, opts in registeredExpansions {
        try Hotstring(opts . sc, , "Off")
    }
    registeredExpansions := Map()
    instantExpansions    := Map()
    loadedExpansions.Clear()
    if (!FileExist(textExpansionPath))
        return
    try {
        content := FileRead(textExpansionPath, "UTF-8")
        for line in StrSplit(content, "`n", "`r") {
            line := Trim(line)
            if (line = "" || SubStr(line, 1, 2) = ";;" || SubStr(line, 1, 2) = "; ")
                continue
            if (InStr(line, " ")) {
                parts := StrSplit(line, " ", , 2)
                if (parts.Length >= 2) {
                    shortcut  := Trim(parts[1])
                    expansion := StrReplace(parts[2], "[NEWLINE]", "`n")
                    ; SpeedKee compatibility: $$ suffix = instant fire
                    instantForced := false
                    if (SubStr(shortcut, -1) = "$$") {
                        shortcut      := SubStr(shortcut, 1, StrLen(shortcut) - 2)
                        instantForced := true
                    }
                    if (shortcut != "" && expansion != "" && IsValidShortcut(shortcut, false)) {
                        try {
                            opts := instantForced ? ":*OC:" : GetHotstringOptions(shortcut)
                            Hotstring(opts . shortcut, MakeExpansionCallback(expansion, shortcut))
                            loadedExpansions[shortcut] := expansion
                            registeredExpansions[shortcut] := opts  ; store opts for clean unload
                            if (instantForced)
                                instantExpansions[shortcut] := true
                        } catch Error as e {
                            ; Skip invalid hotstring
                        }
                    }
                }
            }
        }
    } catch Error as err {
        MsgBox("Error loading expansions: " . err.Message, "Load Error", "Icon!")
    }
    UpdateTrayTooltip()
}

;------------------------------------------------
; FILE INITIALIZATION
;------------------------------------------------
;------------------------------------------------
; AUTO-MIGRATION
; Fixes legacy {date+N:format} -> {date:+N:format}
; Runs silently on startup - safe to run every time
;------------------------------------------------
MigrateDateSyntax() {
    global textExpansionPath
    if (!FileExist(textExpansionPath))
        return
    tmp := textExpansionPath . ".tmp"
    try {
        content := FileRead(textExpansionPath, "UTF-8")
        if (!InStr(content, "{date+"))
            return
        fixed := RegExReplace(content, "\{date\+(\d+):([^}]+)\}", "{date:+$1:$2}")
        if (fixed != content) {
            if (FileExist(tmp))
                FileDelete(tmp)
            FileAppend(fixed, tmp, "UTF-8")
            FileCopy(tmp, textExpansionPath, 1)
        }
    } catch {
        ; Migration failed silently - not critical
    } finally {
        try FileDelete(tmp)
    }
}

MigratePipeSeparators() {
    ; Converts old pipe-separated format (shortcut|expansion) to space-separated
    ; Runs silently on startup - safe to run every time
    global textExpansionPath, launcherPath
    for , filePath in [textExpansionPath, launcherPath] {
        if (!FileExist(filePath))
            continue
        tmp := filePath . ".tmp"
        try {
            content := FileRead(filePath, "UTF-8")
            if (!InStr(content, "|"))
                continue
            fixed := ""
            for line in StrSplit(content, "`n", "`r") {
                trimmed := Trim(line)
                if (trimmed = "" || SubStr(trimmed, 1, 1) = ";") {
                    fixed .= line . "`n"
                    continue
                }
                ; Only replace first | with space (old separator format)
                if (InStr(trimmed, "|") && !InStr(trimmed, " "))
                    trimmed := StrReplace(trimmed, "|", " ", , , 1)
                fixed .= trimmed . "`n"
            }
            if (fixed != content) {
                if (FileExist(tmp)) FileDelete(tmp)
                FileAppend(fixed, tmp, "UTF-8")
                FileCopy(tmp, filePath, 1)
            }
        } catch {
            ; Migration failed silently - not critical
        } finally {
            try FileDelete(tmp)
        }
    }
}

InitializeFiles() {
    global launcherPath, textExpansionPath
    try {
        if (!FileExist(launcherPath))
            FileAppend("; Launcher file - Format: shortcut target`n; Created: " .
                       FormatTime(, "yyyy-MM-dd HH:mm:ss") . "`n", launcherPath)
        if (!FileExist(textExpansionPath))
            FileAppend("; Text Expansion file - Format: shortcut expansion`n; Created: " .
                       FormatTime(, "yyyy-MM-dd HH:mm:ss") . "`n", textExpansionPath)
        SeedDefaultExpansions()
    } catch Error as err {
        MsgBox("Could not initialize files: " . err.Message, "Init Error", "Icon!")
    }
}

;------------------------------------------------
; SEED BUILT-IN SHORTCUTS
; Writes defaults on first run if not already present.
; The = family: function keys, relative dates, utilities
;------------------------------------------------
SeedDefaultExpansions() {
    global textExpansionPath, launcherPath, config
    wc := config["Triggers"]["WinCmd"]       ; default ";"

    defaults := [
        ; ── Date shortcuts ──────────────────────────────
        ["-=",   "{date:MMMM d, yyyy}"],           ; full date
        ["=-",   "{date:MM/dd/yy}"],                ; short date

        ; ── Relative date shortcuts (= family) ──────────
        ["1-=",  "{date:+7:MMMM d, yyyy}"],          ; 1 week from today
        ["2-=",  "{date:+14:MMMM d, yyyy}"],         ; 2 weeks from today
        ["3-=",  "{date:+21:MMMM d, yyyy}"],         ; 3 weeks from today
        ["4-=",  "{date:+28:MMMM d, yyyy}"],         ; 4 weeks from today
        ["1m=",  "{date:+30:MMMM d, yyyy}"],         ; ~1 month from today
        ["2m=",  "{date:+60:MMMM d, yyyy}"],         ; ~2 months from today
        ["3m=",  "{date:+90:MMMM d, yyyy}"],         ; ~3 months from today
        ["6m=",  "{date:+180:MMMM d, yyyy}"],        ; ~6 months from today
        ["1y=",  "{date:+365:MMMM d, yyyy}"],        ; 1 year from today

        ; ── Function key / utility shortcuts (= family) ─
        ["r=",   "{key:F5}"],                       ; Refresh
        ["f=",   "{key:F11}"],                      ; Fullscreen toggle
        ["d=",   "{key:F12}"],                      ; Dev tools
        ["n=",   "{key:F2}"],                       ; Rename (Explorer)
        ["t=",   "{key:^t}"],                       ; New tab
        ["w=",   "{key:^w}"],                       ; Close tab
        ["z=",   "{key:^z}"],                       ; Undo
        ["p=",   "{key:^p}"],                       ; Print
        ["a=",   "{key:^a}"],                       ; Select all
        ["s=",   "{key:^s}"],                       ; Save

        ; ── ; family - Windows commands ─────────────────
        ; Note: Ctrl+Alt+Del is not included - Windows blocks scripts from
        ; sending the Secure Attention Sequence.
        ;
        ; Design rule:
        ;   lowercase = what you use most (copy, paste, save, line start/end...)
        ;   CAPITAL    = the less frequent or riskier twin (Save As, Lock PC)
        ;   8 = emoji picker (Shift+8 is *, matching SpeedKee's long-press *)
        ;
        ; This mirrors the original WinKeys design - your hands learn it once
        ; and the same shortcuts work everywhere MultiShortcuts runs.
        ;
        ; Clipboard & editing
        [wc . "c",  "{key:^c}"],                    ; Copy
        [wc . "x",  "{key:^x}"],                    ; Cut
        [wc . "v",  "{key:^v}"],                    ; Paste
        [wc . "p",  "{key:^p}"],                    ; Print
        [wc . "z",  "{key:^z}"],                    ; Undo
        [wc . "y",  "{key:^y}"],                    ; Redo
        [wc . "a",  "{key:^a}"],                    ; Select All
        [wc . "A",  "{key:^a}{key:^c}"],            ; Select All and Copy - one step, so the
                                                    ; selection is copied before anything is typed
        [wc . "f",  "{key:^f}"],                    ; Find
        [wc . "h",  "{key:^h}"],                    ; Find & Replace

        ; File ops
        [wc . "s",  "{key:^s}"],                    ; Save
        [wc . "S",  "{key:^+s}"],                   ; Save As
        [wc . "n",  "{key:^n}"],                    ; New
        [wc . "o",  "{key:^o}"],                    ; Open
        [wc . "w",  "{key:^w}"],                    ; Close tab / window

        ; Document navigation
        [wc . "t",  "{key:^{Home}}"],               ; Top of page (Ctrl+Home)
        [wc . "b",  "{key:^{End}}"],                ; Bottom of page (Ctrl+End)
        [wc . "u",  "{key:{PgUp}}"],                ; Page Up
        [wc . "d",  "{key:{PgDn}}"],                ; Page Down
        [wc . "l",  "{key:{Home}}"],                ; Line start
        [wc . "e",  "{key:{End}}"],                 ; Line end

        ; Window snap (arrows point the way)
        [wc . "<",  "{key:#{Left}}"],               ; Snap window left (Win+Left)
        [wc . ">",  "{key:#{Right}}"],              ; Snap window right (Win+Right)

        ; Utility
        [wc . "r",  "{key:F5}"],                    ; Refresh
        [wc . "8",  "{key:#.}"],                    ; Emoji picker (Win+.)
        [wc . "k",  "{key:^+{Escape}}"],            ; Task Manager (k for "kill")
        [wc . "m",  "{key:#{Down}}"],               ; Minimize window
        [wc . "g",  "{key:^g}"],                    ; Go to line

        ; ── ; family CAPITALS - second meanings for select letters ──
        [wc . "L",  "{key:#l}"],                    ; Lock PC (capital = harder to hit by accident)
        [wc . "E",  "{key:{End}}"],                 ; Line end (same as ;e)
    ]
    ; Check BOTH files: a trigger already used by a launcher (for example
    ; an older version's ;c Calculator) must not get a second, clashing
    ; built-in - two hotstrings with one trigger fight over it.
    existing := (FileExist(textExpansionPath) ? FileRead(textExpansionPath, "UTF-8") : "")
              . "`n" . (FileExist(launcherPath) ? FileRead(launcherPath, "UTF-8") : "")
    for entry in defaults {
        sc  := entry[1]
        exp := entry[2]
        if (!RegExMatch(existing, "(?m)^\Q" . sc . "\E "))
            LockedFileAppend(textExpansionPath, sc . " " . exp . "`n")
    }

    ; Seed the ` family - these are app launchers, not text expansions,
    ; so they live in launchers.ahk
    SeedDefaultLaunchers()
}

SeedDefaultLaunchers() {
    global launcherPath, textExpansionPath, config
    al := config["Triggers"]["AppLaunch"]    ; default "`"

    defaults := [
        ; ── ` family - lowercase = web/AI, uppercase = system tools ──────────
        [al . "c",  "https://claude.ai"],           ; Claude AI
        [al . "o",  "https://chatgpt.com"],         ; ChatGPT
        [al . "p",  "https://perplexity.ai"],       ; Perplexity AI
        [al . "g",  "https://gemini.google.com"],   ; Google Gemini
        [al . "w",  "https://en.wikipedia.org/wiki/Special:Search"], ; Wikipedia
        [al . "1",  "https://voice.google.com"],    ; Google Voice
        [al . "2",  "https://mail.google.com"],     ; Gmail
        [al . "3",  "https://calendar.google.com"], ; Google Calendar
        [al . "C",  "calc.exe"],                    ; Calculator  (capital = system)
        [al . "S",  "ms-screenclip:"],              ; Snipping Tool (capital = system)
    ]
    ; Check both files, as in SeedDefaultExpansions
    existing := (FileExist(launcherPath) ? FileRead(launcherPath, "UTF-8") : "")
              . "`n" . (FileExist(textExpansionPath) ? FileRead(textExpansionPath, "UTF-8") : "")
    for entry in defaults {
        sc  := entry[1]
        exp := entry[2]
        if (!RegExMatch(existing, "(?m)^\Q" . sc . "\E "))
            LockedFileAppend(launcherPath, sc . " " . exp . "`n")
    }
}

;------------------------------------------------
; INSERT TEXT AT CURSOR IN EDIT CONTROL
;------------------------------------------------
InsertIntoEdit(ctrl, text) {
    sel      := SendMessage(0xB0, 0, 0, ctrl)
    selStart := sel & 0xFFFF
    selEnd   := (sel >> 16) & 0xFFFF
    current  := ctrl.Value
    ctrl.Value := SubStr(current, 1, selStart) . text . SubStr(current, selEnd + 1)
    newPos := selStart + StrLen(text)
    SendMessage(0xB1, newPos, newPos, ctrl)
    ctrl.Focus()
}

;------------------------------------------------
; VALIDATION AND SECURITY
;------------------------------------------------
;------------------------------------------------
; HOTSTRING OPTIONS HELPER
;------------------------------------------------
; Returns the correct hotstring option string for a given shortcut.
; Rules:
;   - Ends in an uppercase letter  → immediate, case-sensitive  (:*C:)
;   - Contains any digit           → immediate, case-sensitive  (:*C:)
;   - Contains any special char    → immediate, case-sensitive  (:*C:)
;     (anything that is not a-z, A-Z, 0-9)
;   - All lowercase letters only   → space/terminator required  (:C:)
;
; The C option is always included to preserve case as typed.
;------------------------------------------------
GetHotstringOptions(shortcut) {
    ; NOTE: $$ suffix is handled upstream (stripped before this call)
    ; and forces :*OC: directly - this function only sees the clean trigger.
    ; The O flag suppresses AHK's automatic end character so we control spacing.
    ; Contains any digit?
    if (RegExMatch(shortcut, "[0-9]"))
        return ":*OC:"
    ; Contains any special character (non-alphabetic)?
    if (RegExMatch(shortcut, "[^a-zA-Z]"))
        return ":*OC:"
    ; Ends in uppercase letter?
    lastChar := SubStr(shortcut, -1)
    if (RegExMatch(lastChar, "[A-Z]"))
        return ":*OC:"
    ; Everything else (pure lowercase) - require terminator (space/enter)
    return ":OC:"
}

IsValidShortcut(shortcut, showMessages := true) {
    ; Rules: at least 2 characters, no characters that break hotstring registration.
    ; When called from file-loading paths, pass showMessages := false so a corrupt
    ; data file silently skips bad entries instead of popping a dialog at startup.
    if (StrLen(shortcut) < 2)
        return false

    ; Block characters that break file format or hotstring registration
    blockedChars := ["|", " ", "`t", "`n", "`r"]
    for , ch in blockedChars {
        if (InStr(shortcut, ch)) {
            if (showMessages) {
                if (ch = "|")
                    MsgBox("The character '|' is not allowed in shortcuts`n(it is used as a separator in the data files).",
                           "Invalid Character", "Icon!")
                else
                    MsgBox("Shortcuts cannot contain spaces or whitespace characters.",
                           "Invalid Character", "Icon!")
            }
            return false
        }
    }

    return true
}

;------------------------------------------------
; SOUND FEEDBACK
;------------------------------------------------
PlayFeedback(soundKey) {
    global config
    if (config["Feedback"]["PlaySounds"])
        try SoundPlay(config["Feedback"][soundKey])
}

;------------------------------------------------
; RELOAD AND PAUSE
;------------------------------------------------
ReloadScript() {
    Reload()
}

ToggleMacrosPause() {
    global config
    if (!A_IsSuspended) {
        Suspend(true)
        TraySetIcon("shell32.dll", 131)
        TrayTip("PAUSED", "All macros paused - press " .
                HotkeyLabel(config["Hotkeys"]["PauseResume"]) . " to resume", "Iconi")
        PlayFeedback("ErrorSound")
    } else {
        Suspend(false)
        TraySetIcon("shell32.dll", 46)
        TrayTip("ACTIVE", "All macros are active", "Iconi")
        PlayFeedback("ExpandSound")
    }
    UpdateTrayTooltip()
}

;------------------------------------------------
; HOLD KEYS  (optional, off by default - tray menu)
;   Semicolon key:  tap = types it,  hold + another key = Ctrl + that key
;   Backtick key (or Caps Lock remapped to backtick):
;                   tap = types it,  hold + another key = Alt + that key
; Lets the pinky reach Ctrl and Alt without leaving the home row, and
; copies a partial selection (typing ;c can't - the ; replaces it).
; Works on the physical keys, whatever the trigger characters are set to.
; Caps Lock (on by default): tap = backtick, hold + key = Alt,
;   Shift + Caps Lock = the normal Caps Lock on/off.
; Middle mouse button (option): click = backtick, hold + key = Ctrl - the Ctrl
;   for when the right hand is on the mouse and can't reach the semicolon.
; Saved in prefs.ini [HoldKeys] Enabled=0|1, CapsLock=0|1, MiddleButton=0|1,
;   HoldMs=100..1000
;------------------------------------------------
; (the holdKeys* globals are declared in GLOBAL STATE near the top)

LoadHoldKeysPrefs() {
    global prefsPath, holdKeysOn, holdKeysMs, holdKeysNews, capsKeyOn, mouseKeyOn, mouseKeyMode
    ; Hold keys start ON for everyone.
    ;   New install (no prefs.ini yet): CheckFirstRun saves the setting and
    ;   the welcome message announces it.
    ;   Upgrade (prefs.ini without a [HoldKeys] section): saved here, and a
    ;   one-time What's New message announces it (ShowHoldKeysNews).
    ; Caps Lock and the middle mouse button (like the semicolon) follow the
    ; same rule: on for everyone, announced once.
    if (!FileExist(prefsPath)) {
        holdKeysOn   := true
        capsKeyOn    := true
        mouseKeyOn   := true
        mouseKeyMode := "ctrl"
        return
    }
    try {
        saved := IniRead(prefsPath, "HoldKeys", "Enabled", "unset")
        if (saved = "unset") {
            holdKeysOn   := true
            holdKeysNews := true
            IniWrite("1", prefsPath, "HoldKeys", "Enabled")
        } else {
            holdKeysOn := (saved = "1")
        }
        caps := IniRead(prefsPath, "HoldKeys", "CapsLock", "unset")
        if (caps = "unset") {
            capsKeyOn    := true
            holdKeysNews := true
            IniWrite("1", prefsPath, "HoldKeys", "CapsLock")
        } else {
            capsKeyOn := (caps = "1")
        }
        mb := IniRead(prefsPath, "HoldKeys", "MiddleButton", "unset")
        if (mb = "unset") {
            mb           := "ctrl"
            holdKeysNews := true
            IniWrite(mb, prefsPath, "HoldKeys", "MiddleButton")
        }
        mouseKeyOn   := (mb = "alt" || mb = "ctrl" || mb = "1")
        mouseKeyMode := (mb = "alt") ? "alt" : "ctrl"
        ms := IniRead(prefsPath, "HoldKeys", "HoldMs", "200")
        if (IsInteger(ms) && ms >= 100 && ms <= 1000)
            holdKeysMs := Integer(ms)
    }
}

; Turns the key and button hotkeys on or off to match the settings.
; Input level 1: the hotkeys ignore the characters this script sends for
; a tap (sent at SendLevel 1), while the script's own hotstrings - input
; level 0 - still see them, so ;c `c and the rest keep working.
ApplyHoldKeys() {
    global holdKeysOn, capsKeyOn, mouseKeyOn, mouseKeyMode
    state  := holdKeysOn ? "On" : "Off"
    cstate := capsKeyOn  ? "On" : "Off"
    mstate := mouseKeyOn ? "On" : "Off"
    try {
        Hotkey("*$vkBA", (*) => HoldKey("vkBA", 0xBA, "LCtrl"), state . " I1")
        Hotkey("*$vkC0", (*) => HoldKey("vkC0", 0xC0, "LAlt"),  state . " I1")
        ; Caps Lock types a backtick on a tap
        Hotkey("*CapsLock", CapsLockKey, cstate . " I1")
        ; The middle button copies Caps Lock (` / Alt) or the semicolon (; / Ctrl)
        Hotkey("*MButton", MiddleButtonKey, mstate . " I1")
        if (capsKeyOn && GetKeyState("CapsLock", "T"))
            SetCapsLockState("Off")      ; a tap no longer switches it off
    } catch Error as err {
        MsgBox("Could not set up hold keys: " . err.Message, "Hold Keys", "Icon!")
    }
}

; Caps Lock: Shift + Caps Lock keeps the normal Caps Lock on/off;
; otherwise tap = backtick, hold + key = Alt
CapsLockKey(*) {
    if (GetKeyState("Shift", "P")) {
        SetCapsLockState(GetKeyState("CapsLock", "T") ? "Off" : "On")
        KeyWait("CapsLock")
        return
    }
    HoldKey("CapsLock", 0x14, "LAlt", "vkC0")
}

ToggleCapsKey(*) {
    global capsKeyOn, prefsPath, capsKeyMenu
    capsKeyOn := !capsKeyOn
    try IniWrite(capsKeyOn ? "1" : "0", prefsPath, "HoldKeys", "CapsLock")
    ApplyHoldKeys()
    if (capsKeyOn) {
        A_TrayMenu.Check(capsKeyMenu)
        TrayTip("Caps Lock Changed",
                "Tap Caps Lock = `` (for your `` launchers).`n" .
                "Hold Caps Lock + a key = Alt + that key.`n" .
                "Shift + Caps Lock = normal Caps Lock.", "Iconi")
    } else {
        A_TrayMenu.Uncheck(capsKeyMenu)
        TrayTip("Caps Lock Normal", "Caps Lock works as usual again.", "Iconi")
    }
}

; Middle mouse button: Shift + middle = the normal middle click (pressed and
; released with the button, so scroll-dragging works too); otherwise it acts
; like Caps Lock or the semicolon, depending on the chosen mode
MiddleButtonKey(*) {
    global mouseKeyMode
    if (GetKeyState("Shift", "P")) {
        Send("{MButton down}")       ; plain Send releases Shift for the click
        KeyWait("MButton")
        Send("{MButton up}")
        return
    }
    if (mouseKeyMode = "alt")
        HoldKey("MButton", 0, "LAlt", "vkC0")
    else
        HoldKey("MButton", 0, "LCtrl", "vkBA")
}

; Tray sub-menu for the middle mouse button: Off / like Caps Lock / like ;

BuildMouseMenu() {
    global mouseSubMenu, mouseItemOff, mouseItemAlt, mouseItemCtrl
    mouseSubMenu := Menu()
    mouseSubMenu.Add(mouseItemOff,  (*) => SetMouseMode("off"))
    mouseSubMenu.Add(mouseItemAlt,  (*) => SetMouseMode("alt"))
    mouseSubMenu.Add(mouseItemCtrl, (*) => SetMouseMode("ctrl"))
    MarkMouseMenu()
    return mouseSubMenu
}

MarkMouseMenu() {
    global mouseSubMenu, mouseKeyOn, mouseKeyMode, mouseItemOff, mouseItemAlt, mouseItemCtrl
    if (!IsObject(mouseSubMenu))
        return
    for , item in [mouseItemOff, mouseItemAlt, mouseItemCtrl]
        mouseSubMenu.Uncheck(item)
    mouseSubMenu.Check(!mouseKeyOn ? mouseItemOff
                     : mouseKeyMode = "alt" ? mouseItemAlt : mouseItemCtrl)
}

SetMouseMode(mode) {
    global mouseKeyOn, mouseKeyMode, prefsPath
    mouseKeyOn := (mode != "off")
    if (mouseKeyOn)
        mouseKeyMode := mode
    try IniWrite(mouseKeyOn ? mode : "0", prefsPath, "HoldKeys", "MiddleButton")
    ApplyHoldKeys()
    MarkMouseMenu()
    if (!mouseKeyOn) {
        TrayTip("Middle Button Normal", "The middle button works as usual again.", "Iconi")
    } else if (mode = "alt") {
        TrayTip("Middle Button: like Caps Lock",
                "Click it, then a letter = that `` launcher.`n" .
                "Hold it + a key = Alt + that key.`n" .
                "Shift + middle click = the normal middle click.", "Iconi")
    } else {
        TrayTip("Middle Button: like the semicolon",
                "Click it, then a letter = that `; command (click then v = Paste).`n" .
                "Hold it + a key = Ctrl + that key (hold + C = Copy).`n" .
                "Shift + middle click = the normal middle click.", "Iconi")
    }
}

; One-time announcement for people upgrading from a version without hold keys

ShowHoldKeysNews() {
    MsgBox(
        "NEW - Ctrl and Alt, now on your home row:`n" .
        "the same shortcuts, without the reach.`n" .
        "`n" .
        "SEMICOLON  -  hold it for Ctrl`n" .
        "   hold `; + C = Copy,   hold `; + V = Paste`n" .
        "`n" .
        "CAPS LOCK  -  hold it for Alt, tap it for ```n" .
        "   hold Caps Lock + Tab = switch windows`n" .
        "   tap Caps Lock, then c = open Claude`n" .
        "   Shift + Caps Lock = normal Caps Lock`n" .
        "`n" .
        "MIDDLE MOUSE BUTTON  -  works like `;`n" .
        "   click it, then v = Paste`n" .
        "   highlight, hold the wheel, tap C = Copy`n" .
        "   Shift + middle click = normal middle click`n" .
        "`n" .
        "A quick tap of `; still types it, so your`n" .
        "shortcuts work as before.`n" .
        "`n" .
        "To change any of this, right-click the tray icon.",
        "What's New in MultiShortcuts Pro 2.0", "Iconi")
}

ToggleHoldKeys(*) {
    global holdKeysOn, prefsPath, holdKeysMenu
    holdKeysOn := !holdKeysOn
    try IniWrite(holdKeysOn ? "1" : "0", prefsPath, "HoldKeys", "Enabled")
    ApplyHoldKeys()
    if (holdKeysOn) {
        A_TrayMenu.Check(holdKeysMenu)
        TrayTip("Hold Keys On",
                "Hold `; and press a key for Ctrl (hold `; + C = copy).`n" .
                "Hold `` or Caps Lock and press a key for Alt.`n" .
                "A quick tap still types the character.", "Iconi")
    } else {
        A_TrayMenu.Uncheck(holdKeysMenu)
        TrayTip("Hold Keys Off", "Semicolon and backtick type normally.", "Iconi")
    }
}

SetHoldKeysTime(*) {
    global holdKeysMs, prefsPath
    IB := InputBox("How long a key must be held before it acts as Ctrl or Alt,`n" .
                   "in milliseconds (1000 = one second).`n`n" .
                   "Lower = quicker.  Higher = fewer slips when typing fast.`n" .
                   "Default 200.  Allowed 100 to 1000.",
                   "Hold Keys Timing", "w380 h190", holdKeysMs)
    if (IB.Result = "Cancel")
        return
    v := Trim(IB.Value)
    if (!IsInteger(v) || v < 100 || v > 1000) {
        MsgBox("Please enter a whole number from 100 to 1000.", "Hold Keys Timing", "Icon!")
        return
    }
    holdKeysMs := Integer(v)
    try IniWrite(holdKeysMs, prefsPath, "HoldKeys", "HoldMs")
    TrayTip("Hold Keys Timing", "Hold time set to " . holdKeysMs . " ms.", "Iconi")
}

; key = the physical key or button, tapKey = what a tap types (default: key)
HoldKey(key, vkNum, modifier, tapKey := "") {
    global holdKeysMs
    typed := (tapKey != "") ? tapKey : key

    ; Catch a key pressed while this one is still down - a fast roll like ";c"
    ih := InputHook("L1")
    ih.Start()
    t0 := A_TickCount
    result := ""
    loop {
        if (!ih.InProgress) {
            result := "rolled"      ; another key came first: normal typing
            break
        }
        if (!GetKeyState(key, "P")) {
            result := "tap"         ; let go quickly
            break
        }
        if (A_TickCount - t0 >= holdKeysMs) {
            result := "hold"        ; held long enough to act as a modifier
            break
        }
        Sleep(5)
    }
    if (ih.InProgress)
        ih.Stop()

    if (result = "tap") {
        HoldKeyType(typed)
        return
    }
    if (result = "rolled") {
        ; Put this key first, then the one that was rolled onto, in order
        HoldKeyType(typed)
        SendLevel(1)
        SendEvent("{Text}" . ih.Input)
        SendLevel(0)
        return
    }

    ; Held: act as the modifier until the key is released
    state := {pressed: false}
    watch := InputHook("V")                 ; V = keys still go through
    watch.KeyOpt("{All}", "N")
    watch.OnKeyDown := (hook, vk, sc) => (vk != vkNum ? state.pressed := true : 0)
    Send("{Blind}{" . modifier . " down}")
    watch.Start()
    KeyWait(key)
    watch.Stop()
    if (modifier = "LAlt")
        Send("{Blind}{vkE8}")               ; stops a lone Alt release opening menus
    Send("{Blind}{" . modifier . " up}")
    ; Held but used for no key: a key still types its character. Not the mouse
    ; button - its hold may have been Ctrl + scroll (zoom) or Ctrl + click.
    if (!state.pressed && key != "MButton")
        HoldKeyType(typed)
}

; Types the key's character at SendLevel 1 so this script's own hotstrings
; (the ; ` = families and custom shortcuts) still see it
HoldKeyType(key) {
    ; SendEvent, not Send: the default SendInput mode briefly removes the
    ; keyboard hook, so this script's own hotstrings would never see the key
    SendLevel(1)
    SendEvent("{Blind}{" . key . "}")
    SendLevel(0)
}

ReleaseHoldModifiers(*) {
    global holdKeysOn, capsKeyOn, mouseKeyOn
    if (holdKeysOn || capsKeyOn || mouseKeyOn)
        Send("{LCtrl up}{LAlt up}")         ; never leave a modifier stuck on exit
}

;------------------------------------------------
; Save stats on exit so nothing is lost
OnExit((*) => SaveUsageStats())
OnExit(ReleaseHoldModifiers)

;------------------------------------------------
; END OF SCRIPT
;------------------------------------------------