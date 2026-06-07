 #Requires AutoHotkey v2.0
#SingleInstance Force

;================================================
; MULTISHORTCUTS PRO - 2026
; SHORTCUT FAMILIES:  ;  `  =
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
        "UndoExpansion",       "!z"
    ),
    "Security", Map(
        "ConfirmDangerousTargets", true,
        "MaxShortcutLength", 50,
        "MinShortcutLength", 2,
        "BlockedProtocols", ["cmd", "powershell", "runas", "regedit",
                             "ms-settings", "vbscript", "javascript",
                             "wscript", "cscript", "ms-msdt", "search-ms",
                             "shell", "calculator", "ms-help", "file"]
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
        ;   WinCmd    = single-char prefix for commands (e.g. ;t = Top of page)
        ;   AppLaunch = launcher prefix (e.g. `c = Claude)
        ; User-editable via tray menu → "Trigger Keys Setup…"
        ; Persisted in prefs.ini [Triggers].
        "WinCmd",    ";",
        "AppLaunch", "``"
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
global expansionHistory  := []
global usageStats        := Map()
global lvSortCol         := Map("launchers", 0, "expansions", 0)
global lvSortAsc         := Map("launchers", true, "expansions", true)

; Path to legacy megabar.ini - kept only for one-time cleanup on startup.
; The F-Key MegaBar feature was retired; this file is deleted if found.
global megaBarPath       := A_ScriptDir . "\megabar.ini"

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
    ; Don't reload if a write is in progress (lock file present)
    if (FileExist(launcherPath . ".lock") || FileExist(textExpansionPath . ".lock"))
        return
    tLauncher := 0
    tExp      := 0
    try {
        if (FileExist(launcherPath))
            tLauncher := FileGetTime(launcherPath, "M")
        if (FileExist(textExpansionPath))
            tExp := FileGetTime(textExpansionPath, "M")
    } catch {
        return  ; Drive briefly unreachable (e.g. cloud-synced folder) - skip, retry on next poll
    }
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
    global backupDir, loadedLaunchers, loadedExpansions
    global launcherPath, textExpansionPath, lastLauncherMod, lastExpMod
    global megaBarPath
    try {
        LoadSoundPrefs()
        LoadTriggerPrefs()

        ; First, check if we're running from a temporary location like Downloads.
        ; If yes and this is the first run, offer to relocate to a permanent home
        ; on the user's Desktop. If we relocate, exit immediately so the new
        ; instance (already launched at the new location) takes over.
        if (CheckRunningLocation()) {
            ExitApp
        }

        ; Clean up orphaned megabar.ini from older versions
        if (FileExist(megaBarPath)) {
            try FileDelete(megaBarPath)
        }

        ; Set up the data files - seeding the built-in ; ` = families
        if (!DirExist(backupDir))
            DirCreate(backupDir)
        InitializeFiles()
        MigrateDateSyntax()
        MigratePipeSeparators()
        LoadLaunchers()
        LoadTextExpansions()

        ; Full feature set always loads - no more starter/full split
        LoadUsageStats()
        LoadExpansionHistory()
        SetupHotkeys()
        SetTimer(SaveUsageStats, 60000)

        try {
            if (FileExist(launcherPath))
                lastLauncherMod := FileGetTime(launcherPath, "M")
            else
                lastLauncherMod := 0
            if (FileExist(textExpansionPath))
                lastExpMod := FileGetTime(textExpansionPath, "M")
            else
                lastExpMod := 0
        } catch {
            ; Drive briefly unreachable at startup - watcher will pick up real times on its first poll
            lastLauncherMod := 0
            lastExpMod := 0
        }
        SetTimer(CheckFileTimes, config["Performance"]["FileWatchInterval"])

        SetupTrayMenu()
        CheckFirstRun()
    } catch Error as err {
        MsgBox("Initialization failed: " . err.Message .
               "`n`nScript will continue in limited mode.", "Error", "Icon!")
    }
}

;------------------------------------------------
; FIRST RUN SETUP
;------------------------------------------------
CheckFirstRun() {
    global prefsPath
    if (FileExist(prefsPath))
        return

    ; First run - write the prefs file so this doesn't fire again,
    ; then show a single orienting TrayTip pointing at the tray icon.
    try FileAppend("FirstRun=done`n", prefsPath)

    TrayTip("MultiShortcuts Pro is running",
            "Try it: type  `c  anywhere and Claude opens." . "`n"
          . "Alt+H for help.  Alt+R reloads if anything stops working.",
            "Iconi")
}

;------------------------------------------------
; LOCATION CHECK - DETECT TEMP/DOWNLOADS LOCATION AND OFFER TO RELOCATE
;------------------------------------------------
; Non-technical users often run scripts directly from their Downloads folder,
; which is a fragile location - it can get cleaned automatically by Windows
; Storage Sense, and re-downloads create copies that confuse the user about
; which file holds their shortcut library.
;
; On first run, if we detect we're in such a location, we offer to copy
; ourselves to Desktop\shortcuts\ and re-launch from there. This is opt-in
; via dialog - users who know what they're doing can decline.
;
; Returns: true if we relocated (caller should exit immediately so the new
; instance takes over). false if we're staying put.
CheckRunningLocation() {
    global prefsPath

    ; Only run this check once. Use a separate flag from FirstRun because
    ; we want to ask about location even if some prefs already exist.
    if (FileExist(prefsPath)) {
        try {
            asked := IniRead(prefsPath, "Setup", "LocationChecked", "no")
            if (asked = "yes")
                return false
        } catch {
            ; If we can't read prefs, skip the check rather than block startup
            return false
        }
    }

    if (!IsInTempLocation(A_ScriptDir))
        return false

    ; We're in a temp-ish location. Ask the user.
    msg := "MultiShortcuts Pro is running from:" . "`n`n"
    msg .= "    " . A_ScriptDir . "`n`n"
    msg .= "This is a temporary location. Files here can get cleaned up by "
    msg .= "Windows automatically over time, and your shortcut library "
    msg .= "lives alongside this script — so it would get lost too." . "`n`n"
    msg .= "Move MultiShortcuts Pro to a folder on your Desktop?" . "`n`n"
    msg .= "You can move the folder anywhere later — including OneDrive, "
    msg .= "Dropbox, or Google Drive to sync your shortcuts across PCs."

    result := MsgBox(msg, "First-Time Setup - Choose a Home",
                     "YesNo Iconi 4096")

    ; Mark that we've asked, regardless of answer, so we don't ask again
    MarkLocationChecked()

    if (result = "No")
        return false

    ; User said yes. Do the relocation.
    return DoRelocate()
}

; Decides if a script directory looks like a temporary or fragile location.
; Conservative: only flags well-known patterns. Avoids false positives on
; folders the user picked intentionally.
IsInTempLocation(dir) {
    ; Normalize for comparison
    d := StrLower(dir)

    ; Common temporary or fragile locations
    downloads := StrLower(A_MyDocuments . "\..\Downloads")
    tmp       := StrLower(A_Temp)

    if (InStr(d, "\downloads"))           ; e.g., C:\Users\X\Downloads
        return true
    if (InStr(d, A_Temp))                  ; Windows temp folder
        return true
    if (InStr(d, "\appdata\local\temp"))   ; alternate temp paths
        return true
    if (RegExMatch(d, "^[a-z]:\\?$"))      ; root of a drive, like C:\
        return true

    return false
}

MarkLocationChecked() {
    global prefsPath
    try {
        ; Ensure the file exists first
        if (!FileExist(prefsPath))
            FileAppend("", prefsPath)
        IniWrite("yes", prefsPath, "Setup", "LocationChecked")
    }
}

; Performs the relocation: creates Desktop\shortcuts\, copies this script,
; launches the new copy, and signals caller to exit. Returns true on success,
; false if anything went wrong (in which case we keep running where we are).
DoRelocate() {
    ; Build destination path
    targetDir := A_Desktop . "\MultiShortcuts Pro"

    ; Handle the case where the folder already exists. Three scenarios:
    ;   1. Folder exists and has a MultiShortcutsPro.ahk in it -> user
    ;      already did this. Just launch the existing one and exit.
    ;   2. Folder exists but is empty/different -> use a numbered variant
    ;      so we don't trample.
    ;   3. Folder doesn't exist -> create it fresh.
    chosenDir := ""
    if (DirExist(targetDir)) {
        existingScript := targetDir . "\" . A_ScriptName
        if (FileExist(existingScript)) {
            ; Already relocated previously. Just launch it and bail.
            try {
                Run(existingScript)
                MsgBox("MultiShortcuts Pro is already installed at:" . "`n`n"
                       . targetDir . "`n`n"
                       . "Launching that copy. You can delete the one in your "
                       . "Downloads folder.",
                       "Already Installed", "Iconi")
                return true
            } catch {
                return false
            }
        }
        ; Folder exists but doesn't have our script. Find a free name.
        n := 2
        while (DirExist(targetDir . " (" . n . ")") && n < 20)
            n++
        chosenDir := targetDir . " (" . n . ")"
    } else {
        chosenDir := targetDir
    }

    ; Try to create the destination directory
    try DirCreate(chosenDir)
    catch Error as err {
        MsgBox("Couldn't create the folder:" . "`n`n"
               . chosenDir . "`n`n"
               . "Reason: " . err.Message . "`n`n"
               . "MultiShortcuts Pro will keep running from its current location. "
               . "You can move the file manually anytime.",
               "Couldn't Move", "Icon!")
        return false
    }

    ; Copy this script to the new location
    sourceFile := A_ScriptFullPath
    targetFile := chosenDir . "\" . A_ScriptName
    try FileCopy(sourceFile, targetFile, false)
    catch Error as err {
        MsgBox("Couldn't copy the script file." . "`n`n"
               . "Reason: " . err.Message . "`n`n"
               . "MultiShortcuts Pro will keep running from its current location.",
               "Couldn't Move", "Icon!")
        return false
    }

    ; Launch the new copy
    try Run(targetFile)
    catch Error as err {
        MsgBox("The script was moved to:" . "`n`n"
               . chosenDir . "`n`n"
               . "But it couldn't auto-launch. Please go to that folder and "
               . "double-click MultiShortcutsPro.ahk to start.",
               "Move Complete", "Iconi")
        return true  ; Still consider it a successful relocate
    }

    ; Notify user, then signal caller to exit so the new copy takes over
    MsgBox("MultiShortcuts Pro is now installed at:" . "`n`n"
           . chosenDir . "`n`n"
           . "Tip: drag this whole folder to OneDrive, Dropbox, or Google Drive "
           . "if you want your shortcuts to sync across PCs." . "`n`n"
           . "You can also delete the original file in your Downloads folder.",
           "Welcome to MultiShortcuts Pro", "Iconi")
    return true
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
    global config
    A_TrayMenu.Delete()
    A_TrayMenu.Add("Show Help",               (*) => ShowHelp())
    A_TrayMenu.Add("Edit Shortcuts (Alt+E)",  (*) => ShowEditGUI("launchers"))
    A_TrayMenu.Add()
    A_TrayMenu.Add("Add Text Expansion (Alt+T)",    (*) => AddNewExpansion())
    A_TrayMenu.Add("Add App Launcher (Alt+A)",      (*) => AddNewLauncher())
    A_TrayMenu.Add("Add Document (Alt+D)",          (*) => AddDocumentLauncher())
    A_TrayMenu.Add("Add Web/Email (Alt+W)",         (*) => AddWebLauncher())
    A_TrayMenu.Add("Capture Selection (Alt+C)",     (*) => CaptureSelectedText())
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
    A_TrayMenu.Add("Pause/Resume (Alt+P)",    (*) => ToggleMacrosPause())
    A_TrayMenu.Add("Reload Script",           (*) => Reload())
    A_TrayMenu.Add("Exit",                    (*) => ExitApp())
    A_TrayMenu.Default := "Edit Shortcuts (Alt+E)"
    if (FileExist(GetStartupLinkPath()))
        A_TrayMenu.Check("Run on Windows Startup")
    if (config["Feedback"]["PlaySounds"])
        A_TrayMenu.Check("Sound Feedback")
    UpdateTrayTooltip()
}

UpdateTrayTooltip() {
    global loadedLaunchers, loadedExpansions
    status   := A_IsSuspended ? "PAUSED" : "Active"
    A_IconTip := "MultiShortcuts Pro (" . status . ")"
              . "`nLaunchers: "  . loadedLaunchers.Count
              . "   Expansions: " . loadedExpansions.Count
}

;------------------------------------------------
; SHARED HELPERS
;------------------------------------------------
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
            LockedFileAppend(filePath, shortcut . " " . StrReplace(target, "`n", "[NEWLINE]") . "`n")
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
    global config
    lockPath := filePath . ".lock"
    tempPath := filePath . ".tmp"
    backPath := filePath . ".bak"
    try {
        if (config["TextExpander"]["BackupOnSave"])
            BackupFile(filePath)
        content := headerComment . "`n"
        for shortcut, target in dataMap
            content .= shortcut . " " . StrReplace(target, "`n", "[NEWLINE]") . "`n"
        retries := 10
        while (FileExist(lockPath) && retries > 0) {
            Sleep(100)
            retries--
        }
        FileAppend("", lockPath, "UTF-8")
        try {
            ; Write to temp first
            if (FileExist(tempPath))
                FileDelete(tempPath)
            FileAppend(content, tempPath, "UTF-8")
            ; Keep backup of original in case copy fails
            if (FileExist(filePath))
                FileCopy(filePath, backPath, 1)
            ; Overwrite original with temp (FileCopy is safer than delete+move)
            ; Atomic OS-level file replacement - safe against power loss/crash
            if (!DllCall("ReplaceFile",
                    "Str", filePath, "Str", tempPath, "Ptr", 0,
                    "UInt", 1, "Ptr", 0, "Ptr", 0)) {
                ; Fallback to FileCopy if ReplaceFile fails (e.g. file doesn't exist yet)
                FileCopy(tempPath, filePath, 1)
            }
            ; Clean up
            try FileDelete(tempPath)
            try FileDelete(backPath)
        } finally {
            try FileDelete(lockPath)
        }
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
    retries := 10
    while (FileExist(lockPath) && retries > 0) {
        Sleep(100)
        retries--
    }
    ; Fix 6: if lock file still exists after retries, alert user instead of silent fail
    if (FileExist(lockPath)) {
        MsgBox("Could not save - the file is locked:`n" . filePath .
               "`n`nIf this keeps happening, delete the file:`n" . lockPath,
               "Save Failed", "Icon!")
        return
    }
    try FileAppend("", lockPath, "UTF-8")
    try {
        FileAppend(content, filePath, "UTF-8")
    } finally {
        try FileDelete(lockPath)
    }
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
    ; Resolve .lnk shortcut files to their real target before validation
    ; A .lnk could point to cmd.exe or powershell.exe with arguments
    targetToValidate := selectedFile
    if (StrLower(SubStr(selectedFile, -4)) = ".lnk") {
        try {
            FileGetShortcut(selectedFile, &lnkTarget)
            if (lnkTarget != "")
                targetToValidate := lnkTarget
        }
    }
    if (!IsAllowedTarget(targetToValidate))
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
; Is Allowed
;---------------------------------------------
IsAllowedTarget(target) {
    global config
    ; Normalise: strip leading/trailing whitespace and quotes, lowercase for comparison
    cleaned := StrLower(Trim(target, " `t`"'"))

    ; Block environment variable injection patterns like %comspec%
    if (RegExMatch(cleaned, "%\w+%")) {
        MsgBox("Environment variable references (e.g. %comspec%) are not permitted.`n" .
               "Use a full path instead.",
               "Security Block", "Icon!")
        return false
    }

    ; Block shell metacharacters that could enable command injection
    ; BUT only for file/executable targets - URLs legitimately contain & ? # ( ) etc.
    isUrl := (SubStr(cleaned, 1, 7) = "http://" || SubStr(cleaned, 1, 8) = "https://"
           || SubStr(cleaned, 1, 7) = "mailto:" || SubStr(cleaned, 1, 6) = "ftp://")
    if (!isUrl && (RegExMatch(cleaned, "[&;``><|$()#?*]"))) {
        MsgBox("Shell metacharacters are not permitted in launcher targets.`nUse a direct file path without command chaining.",
               "Security Block", "Icon!")
        return false
    }

    ; Block dangerous protocols
    ; Strip interior whitespace from the leading portion before checking, so
    ; tricks like "ms-msdt :foo" or "cmd  :bar" can't slip past the regex.
    for , proto in config["Security"]["BlockedProtocols"] {
        normalized := RegExReplace(cleaned, "\s+", "")
        if (RegExMatch(normalized, "^" . proto . ":")) {
            MsgBox("Blocked protocol: '" . proto . "'.`n" .
                   "Only http/https/mailto and normal file paths are permitted.",
                   "Security Block", "Icon!")
            return false
        }
    }

    ; Block dangerous script file extensions including AHK itself
    blockedExts := [".bat", ".cmd", ".ps1", ".vbs", ".wsf", ".hta", ".ahk", ".ah2"]
    for , ext in blockedExts {
        if (RegExMatch(cleaned, "\Q" . ext . "\E(\s|$)")) {
            MsgBox("File type '" . ext . "' is not permitted as a launcher target.`n" .
                   "Use a .exe or a folder path instead.",
                   "Security Block", "Icon!")
            return false
        }
    }

    ; Warn on dangerous system executables if ConfirmDangerousTargets is enabled
    if (config["Security"]["ConfirmDangerousTargets"]) {
        ; Use SplitPath to extract just the executable filename
        ; This catches "C:\Windows\System32\cmd.exe /c del *.*" style bypasses
        exeTarget := cleaned
        if (SubStr(cleaned, 1, 1) = '"') {
            ; Quoted path - extract content between first pair of quotes
            if (RegExMatch(cleaned, '^"([^"]+)"', &m))
                exeTarget := m[1]
        } else {
            ; Unquoted - take everything before first space (the exe path)
            exeTarget := StrSplit(cleaned, " ")[1]
        }
        SplitPath(exeTarget, &outFileName)
        cleanedExe := StrLower(outFileName)

        dangerousExes := ["cmd.exe", "powershell.exe", "pwsh.exe", "wscript.exe",
                          "cscript.exe", "mshta.exe", "regsvr32.exe", "rundll32.exe",
                          "msiexec.exe", "wmic.exe", "forfiles.exe", "regedit.exe"]
        dangerousDirs := ["system32", "syswow64", "sysnative"]
        isDangerous := false

        ; Check by exact executable filename
        for , exe in dangerousExes {
            if (cleanedExe = exe) {
                isDangerous := true
                break
            }
        }
        ; Also check by directory path
        if (!isDangerous) {
            for , dir in dangerousDirs {
                if (InStr(StrLower(exeTarget), "\" . dir . "\")) {
                    isDangerous := true
                    break
                }
            }
        }
        if (isDangerous) {
            result := MsgBox("Warning: This target appears to be a sensitive system executable.`n`n" .
                             target . "`n`nAre you sure you want to add this launcher?",
                             "Security Warning", "YesNo Icon!")
            if (result != "Yes")
                return false
        }
    }

    return true
}

;---------------------------------------------
AddWebLauncher() {
    global launcherPath, loadedLaunchers

    ; Try to auto-capture a URL from whatever's currently focused.
    ; This works best when the user has clicked into a browser's address bar
    ; before pressing Alt+W. We do this BEFORE any dialog opens, because once
    ; the dialog opens it steals focus away from the browser.
    capturedUrl := TryCaptureUrl()

    shortcut := PromptShortcut(
        "Enter trigger name:`n`nExample: 'gmail' or 'news'",
        "Web/Email Launcher")
    if (shortcut = "")
        return
    if (!CheckGlobalConflict(shortcut))
        return

    ; Pre-fill the URL field with the captured URL if it looks valid,
    ; otherwise use the default "https://" placeholder.
    ; The prompt text changes too — explicit feedback when capture succeeded
    ; makes the "magic" moment understandable instead of mysterious.
    if (capturedUrl != "") {
        promptText := "Captured this URL from your browser:`n`n"
                    . "Press OK to add it as a launcher, or edit first "
                    . "if you want a different URL."
        defaultUrl := capturedUrl
    } else {
        promptText := "Enter URL or Email address:`n`nExamples:`n"
                    . "https://gmail.com`njohn@example.com"
        defaultUrl := "https://"
    }
    I2 := InputBox(promptText, "Target Address", "w400 h160", defaultUrl)
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

;------------------------------------------------
; URL CAPTURE FROM ACTIVE WINDOW
;------------------------------------------------
; Attempts to capture a URL from whatever text field currently has focus.
; The intended use is: user clicks into a browser's address bar, then presses
; Alt+W. We fire Ctrl+A to select all the address-bar content, then Ctrl+C
; to copy it to the clipboard, then read the clipboard.
;
; To be polite, we save and restore the user's original clipboard content
; so they don't lose something they had in there.
;
; Returns the captured URL if it looks valid (starts with http://, https://,
; or contains :// or @). Returns empty string otherwise.
TryCaptureUrl() {
    ; Save existing clipboard so we can restore it
    originalClip := A_Clipboard
    A_Clipboard := ""

    ; Try to grab the contents of the focused field
    try {
        Send("^a")
        Sleep(50)
        Send("^c")
    }

    ; Wait briefly for the clipboard to update (up to 300ms)
    captured := ""
    if (ClipWait(0.3, 0)) {
        captured := Trim(A_Clipboard)
    }

    ; Restore the user's original clipboard content
    A_Clipboard := originalClip

    ; Validate that what we captured looks like a URL or email
    if (captured = "")
        return ""
    if (RegExMatch(captured, "^https?://"))
        return captured
    if (RegExMatch(captured, "i)^[a-z]+://"))     ; other schemes like ftp:// mailto:
        return captured
    if (InStr(captured, "@") && !InStr(captured, " "))     ; looks like an email
        return captured

    ; Doesn't look like a URL - might be a Word doc selection, etc.
    ; Don't pre-fill, let user type from scratch.
    return ""
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
            RecordExpansionHistory(sc, sc, expansion)
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
    ; Use stored length + 1 for trailing space added by SendExpandText
    delCount := last.Has("length") ? last["length"] + 1 : StrLen(original) + 1
    Send("{BS " . delCount . "}")
    Sleep(30)
    SendText(original)
    expansionHistory.Pop()
    SaveExpansionHistory()
    TrayTip("Undone", "Restored '" . original . "'", "Iconi")
}

RecordExpansionHistory(shortcut, original, expanded) {
    global expansionHistory, config
    maxSize := config["TextExpander"]["MaxHistorySize"]
    ; Store only shortcut + timestamp + length - NOT the expanded text
    ; This protects patient data, private messages, and sensitive content
    expansionHistory.Push(Map(
        "shortcut", shortcut,
        "original", original,
        "length",   StrLen(expanded),
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

    ; ── Pre-scan pass: count expansions that contain risky sequence tokens
    ; before importing anything. {key:...} sends raw keystrokes - an
    ; imported expansion with {key:#r} would open Run, {key:^w} would close
    ; the active window, etc. We don't block, but we make the user aware.
    riskyCount := 0
    riskySamples := []
    try {
        for line in StrSplit(FileRead(filePath, "UTF-8"), "`n", "`r") {
            line := Trim(line)
            if (line = "" || SubStr(line, 1, 4) = "Type")
                continue
            parts := StrSplit(line, ",", , 3)
            if (parts.Length < 3)
                continue
            if (Trim(parts[1]) = "Expansion") {
                val := StrReplace(parts[3], '"', "")
                if (InStr(val, "{key:") || InStr(val, "{focus:")) {
                    riskyCount++
                    if (riskySamples.Length < 3)
                        riskySamples.Push(Trim(StrReplace(parts[2], '"', "")))
                }
            }
        }
    }
    if (riskyCount > 0) {
        sampleList := ""
        for , s in riskySamples
            sampleList .= "  * " . s . "`n"
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

    try {
        content  := FileRead(filePath, "UTF-8")
        lines    := StrSplit(content, "`n", "`r")
        imported := 0
        skipped  := 0
        for i, line in lines {
            if (i = 1 && InStr(line, "Type,Shortcut"))
                continue
            line := Trim(line)
            if (line = "")
                continue
            parts := StrSplit(line, ",", , 3)
            if (parts.Length < 3) {
                skipped++
                continue
            }
            type := Trim(parts[1])
            sc   := Trim(StrReplace(parts[2], '"', ""))
            val  := Trim(StrReplace(parts[3], '"', ""))
            ; Reverse EscapeCSV's formula-injection guard: it prefixes ' before
            ; cells starting with = @ + -. Strip that ' back off on import so
            ; shortcuts like =- (short date) round-trip through CSV cleanly.
            if (SubStr(sc,  1, 1) = "'" && RegExMatch(SubStr(sc,  2, 1), "[=@+\-]"))
                sc  := SubStr(sc,  2)
            if (SubStr(val, 1, 1) = "'" && RegExMatch(SubStr(val, 2, 1), "[=@+\-]"))
                val := SubStr(val, 2)
            ; Restore [NEWLINE] tokens to actual newlines (written by EscapeCSV)
            val  := StrReplace(val, "[NEWLINE]", "`n")
            if (!IsValidShortcut(sc, false)) {
                skipped++
                continue
            }
            if (type = "Launcher" && !loadedLaunchers.Has(sc)) {
                if (!IsAllowedTarget(val)) {
                    skipped++
                } else {
                    FileAppend(sc . " " . StrReplace(val, "`n", "[NEWLINE]") . "`n", launcherPath)
                    imported++
                }
            } else if (type = "Expansion" && !loadedExpansions.Has(sc)) {
                FileAppend(sc . " " . StrReplace(val, "`n", "[NEWLINE]") . "`n", textExpansionPath)
                imported++
            } else {
                skipped++
            }
        }
        LoadLaunchers()
        LoadTextExpansions()
        MsgBox("Import complete.`n`nImported: " . imported .
               "`nSkipped: " . skipped, "Import Results", "Iconi")
    } catch Error as err {
        MsgBox("Import failed: " . err.Message, "Error", "Icon!")
    }
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
    reserved := ["=", "|", '"', "/", '\']
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

; Module-level state used by ShowTriggerSetup / DoSaveTriggers
global _triggerSetupGui      := ""
global _triggerSetupEditCmd  := ""
global _triggerSetupEditApp  := ""
global _triggerSetupOldCmd   := ""
global _triggerSetupOldApp   := ""

ShowTriggerSetup() {
    global config, _triggerSetupGui, _triggerSetupEditCmd, _triggerSetupEditApp
    global _triggerSetupOldCmd, _triggerSetupOldApp
    _triggerSetupOldCmd := config["Triggers"]["WinCmd"]
    _triggerSetupOldApp := config["Triggers"]["AppLaunch"]

    g := Gui("+ToolWindow", "Trigger Keys Setup")
    g.SetFont("s10", "Segoe UI")
    g.BackColor := "FFFFFF"

    g.Add("Text", "x15 y15 w470 h40", "Customize the prefix characters for the built-in shortcut families. Existing shortcuts using the old prefixes will be migrated.")

    g.Add("Text", "x15 y75 w200", "Commands prefix (default semicolon):")
    edCmd := g.Add("Edit", "x270 y72 w40 Limit1 Center", _triggerSetupOldCmd)

    g.Add("Text", "x15 y110 w200", "Launchers prefix (default backtick):")
    edApp := g.Add("Edit", "x270 y107 w40 Limit1 Center", _triggerSetupOldApp)

    g.Add("Text", "x15 y150 w470 h40 cGray", "Tip: avoid letters and digits - they would fire in the middle of words. The two prefixes must be different.")
    g.Add("Button", "x230 y210 w90 Default", "Save").OnEvent("Click", DoSaveTriggers)
    g.Add("Button", "x330 y210 w90", "Cancel").OnEvent("Click", CancelTriggerSetup)
    g.OnEvent("Escape", CancelTriggerSetup)

    _triggerSetupGui     := g
    _triggerSetupEditCmd := edCmd
    _triggerSetupEditApp := edApp
    g.Show("w500 h255")
}

CancelTriggerSetup(*) {
    global _triggerSetupGui
    if (_triggerSetupGui != "")
        _triggerSetupGui.Destroy()
    _triggerSetupGui := ""
}

DoSaveTriggers(*) {
    global config, _triggerSetupGui, _triggerSetupEditCmd, _triggerSetupEditApp
    global _triggerSetupOldCmd, _triggerSetupOldApp
    newCmd := _triggerSetupEditCmd.Value
    newApp := _triggerSetupEditApp.Value
    oldCmd := _triggerSetupOldCmd
    oldApp := _triggerSetupOldApp

    err := IsValidTriggerChar(newCmd, newApp)
    if (err != "") {
        MsgBox("Commands prefix:" . "`n`n" . err, "Invalid Trigger", "Icon!")
        return
    }
    err := IsValidTriggerChar(newApp, newCmd)
    if (err != "") {
        MsgBox("Launchers prefix:" . "`n`n" . err, "Invalid Trigger", "Icon!")
        return
    }
    if (newCmd = oldCmd && newApp = oldApp) {
        CancelTriggerSetup()
        return
    }

    migrated := MigrateTriggerPrefix(oldCmd, newCmd)
              + MigrateTriggerPrefix(oldApp, newApp)

    config["Triggers"]["WinCmd"]    := newCmd
    config["Triggers"]["AppLaunch"] := newApp
    SaveTriggerPrefs()
    SeedDefaultExpansions()

    CancelTriggerSetup()
    msg := "Prefixes updated:"
    msg .= "`n  Commands: " . newCmd
    msg .= "`n  Launchers: " . newApp
    if (migrated > 0)
        msg .= "`n`n" . migrated . " shortcut(s) migrated."
    msg .= "`n`nReloading..."
    TrayTip("Trigger Keys Updated", msg, "Iconi")
    SetTimer(ReloadScriptSilent, -800)
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
    gEdit := Gui("+Resize +MinSize640x460", "MultiShortcuts Pro - Manage Shortcuts")
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
        type := InStr(target, "://") || InStr(target, "mailto:") ? "Web/Email"
              : RegExMatch(StrLower(target), '\.(exe|lnk)("|\s|$)') ? "App"
              : "Document"
        lv.Add("", shortcut, target, type)
        count++
    }
    return count
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
    oldTarget   := lv.GetText(row, 2)

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
        newTarget   := Trim(editVal.Value)
        if (newShortcut = "" || newTarget = "") {
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
    global config
    hk := config["Hotkeys"]
    gHelp := Gui("+ToolWindow", "Help - MultiShortcuts Pro")
    gHelp.SetFont("s10", "Segoe UI")
    gHelp.BackColor := "FFFFFF"
    title := gHelp.Add("Text", "x0 y0 w500 h40 +0x200 Background1A1A2E cWhite Center",
                        "  MultiShortcuts Pro  ")
    title.SetFont("s12 Bold", "Segoe UI")
    sections := [
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
            [hk["ShowHelp"],            "This Help Screen"]
        ]]
    ]
    y := 50
    for si, section in sections {
        heading := gHelp.Add("Text", "x10 y" . y . " w480 h22 c1A1A2E", section[1])
        heading.SetFont("s10 Bold", "Segoe UI")
        y += 24
        gHelp.Add("Text", "x10 y" . y . " w480 h1 Background808080")
        y += 6
        for , row in section[2] {
            label   := HotkeyLabel(row[1])
            keyCtrl := gHelp.Add("Text",
                "x14 y" . y . " w110 h20 BackgroundE8EAF6 c1A1A2E Center", label)
            keyCtrl.SetFont("s9 Bold", "Consolas")
            gHelp.Add("Text", "x132 y" . (y+1) . " w350 h20 c444444", row[2])
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
    gHelp.Add("Text", "x10 y" . y . " w480 h54 BackgroundFFFDE7")
    tipText := "TIP: Type your shortcut anywhere - it triggers automatically." . "`n"
    tipText .= "     Alt+C captures selected text instantly." . "`n"
    tipText .= "     Click the 'Pre-loaded Shortcuts' button below to see all" . "`n"
    tipText .= "     built-in shortcut families that ship with MultiShortcuts Pro."
    gHelp.Add("Text", "x18 y" . (y+5) . " w468 h66 BackgroundFFFDE7 c555500", tipText)
    y += 76
    gHelp.Add("Text", "x10 y" . y . " w480 h1 Background808080")
    y += 6
    gHelp.Add("Text", "x10 y" . y . " w480 h18 cAAAAAA Center",
              "(c) GnuKey LLC  -  Implementation: Claude (Anthropic)  -  Review: Gemini (Google)")
    y += 22
    gHelp.Add("Button", "x100 y" . y . " w200 h30", "Pre-loaded Shortcuts")
        .OnEvent("Click", (*) => ShowPreloadedShortcuts())
    gHelp.Add("Button", "x320 y" . y . " w80 h30 Default", "Close")
        .OnEvent("Click", (*) => gHelp.Destroy())
    gHelp.OnEvent("Close",  (*) => gHelp.Destroy())
    gHelp.OnEvent("Escape", (*) => gHelp.Destroy())
    gHelp.Show("w500 h" . (y + 44))
}

;------------------------------------------------
; PRE-LOADED SHORTCUTS POPUP
;------------------------------------------------
; Shows all the built-in shortcut families that ship with MultiShortcuts Pro.
; Organized by family for easy scanning. Users may have customized these, but
; this popup shows the defaults — useful for new users and for remembering
; what's available after time away.
ShowPreloadedShortcuts() {
    global config
    wc := config["Triggers"]["WinCmd"]
    al := config["Triggers"]["AppLaunch"]

    gPre := Gui("+ToolWindow", "Pre-loaded Shortcuts - MultiShortcuts Pro")
    gPre.SetFont("s10", "Segoe UI")
    gPre.BackColor := "FFFFFF"

    title := gPre.Add("Text", "x0 y0 w560 h40 +0x200 Background1A1A2E cWhite Center",
                       "  Pre-loaded Shortcuts  ")
    title.SetFont("s12 Bold", "Segoe UI")

    sections := [
        ["WINDOWS APPS (" . wc . " family)", [
            [wc . "c",  "Calculator"],
            [wc . "q",  "Snipping Tool"],
            [wc . "f",  "File Explorer"],
            [wc . "T",  "Task Manager"]
        ]],
        ["WINDOWS COMMANDS (" . wc . " family)", [
            [wc . "s",  "Save (Ctrl+S)"],
            [wc . "S",  "Save As (Ctrl+Shift+S)"],
            [wc . "n",  "New (Ctrl+N)"],
            [wc . "o",  "Open (Ctrl+O)"],
            [wc . "p",  "Print (Ctrl+P)"],
            [wc . "w",  "Close tab (Ctrl+W)"],
            [wc . "r",  "Refresh (F5)"],
            [wc . "a",  "Switch app (Alt+Tab)"],
            [wc . "A",  "Select All and Copy"],
            [wc . "L",  "Lock PC"],
            [wc . "E",  "Emoji picker"]
        ]],
        ["DOCUMENT NAVIGATION (" . wc . " family)", [
            [wc . "t",  "Top of page (Ctrl+Home)"],
            [wc . "b",  "Bottom of page (Ctrl+End)"],
            [wc . "u",  "Page Up"],
            [wc . "d",  "Page Down"],
            [wc . "l",  "Line start (Home)"],
            [wc . "e",  "Line end (End)"],
            [wc . "<",  "Snap window left"],
            [wc . ">",  "Snap window right"],
            [wc . "m",  "Minimize window"]
        ]],
        ["LAUNCHERS (" . al . " family)", [
            [al . "a",  "ChatGPT"],
            [al . "c",  "Claude"],
            [al . "g",  "Gemini"],
            [al . "p",  "Perplexity"],
            [al . "1",  "Google Voice"],
            [al . "2",  "Gmail"],
            [al . "3",  "Google Calendar"]
        ]],
        ["DATES (= family)", [
            ["-=",   "Today's date (e.g. May 25, 2026)"],
            ["=-",   "Today's date, short form (05/25/26)"],
            ["1-=",  "One week from today"],
            ["2-=",  "Two weeks from today"],
            ["1m=",  "One month from today"],
            ["1y=",  "One year from today"]
        ]]
    ]

    y := 50
    for si, section in sections {
        heading := gPre.Add("Text", "x10 y" . y . " w540 h22 c1A1A2E", section[1])
        heading.SetFont("s10 Bold", "Segoe UI")
        y += 24
        gPre.Add("Text", "x10 y" . y . " w540 h1 Background808080")
        y += 6
        for , row in section[2] {
            trgCtrl := gPre.Add("Text",
                "x14 y" . y . " w110 h20 BackgroundE8EAF6 c1A1A2E Center", row[1])
            trgCtrl.SetFont("s9 Bold", "Consolas")
            gPre.Add("Text", "x132 y" . (y+1) . " w410 h20 c444444", row[2])
            y += 24
        }
        y += 12
    }

    gPre.Add("Text", "x10 y" . y . " w540 h54 BackgroundFFFDE7")
    noteText := "These ship with MultiShortcuts Pro. Every one is yours to" . "`n"
    noteText .= "edit or delete — press Alt+E to open the editor. Build your own" . "`n"
    noteText .= "shortcuts with Alt+T, Alt+A, Alt+D, Alt+W, or Alt+C."
    gPre.Add("Text", "x18 y" . (y+5) . " w524 h48 BackgroundFFFDE7 c555500", noteText)
    y += 64

    gPre.Add("Button", "x230 y" . y . " w100 h30 Default", "Close")
        .OnEvent("Click", (*) => gPre.Destroy())
    gPre.OnEvent("Close",  (*) => gPre.Destroy())
    gPre.OnEvent("Escape", (*) => gPre.Destroy())
    gPre.Show("w560 h" . (y + 44))
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
        
        TrayTip("Launchers Loaded", count . " launchers ready (backtick + number works!)", "Iconi")
        
    } catch Error as err {
        MsgBox("Error loading launchers: " . err.Message . "`n`nCheck that launchers.ahk follows the 'shortcut target' format.", "Load Error", "Icon!")
    }
    UpdateTrayTooltip()
}

;------------------------------------------------
; LAUNCH TARGET - SILENT VERSION
;------------------------------------------------
LaunchTarget(target, shortcut := "") {
    target := Trim(target)
    if (shortcut != "")
        TrackUsage(shortcut, "launcher")

    cleanTarget := Trim(target, ' "')

    try {
        if (InStr(cleanTarget, "://") || InStr(cleanTarget, "mailto:")) {
            Run(cleanTarget)
        } else if (FileExist(cleanTarget)) {
            ; Full path exists (handles paths with spaces, e.g. Program Files)
            Run('"' . cleanTarget . '"')
        } else {
            ; Extract base path (strip trailing arguments)
            testPath := (SubStr(target, 1, 1) = '"')
                      ? RegExReplace(target, '^"([^"]+)".*', "$1")
                      : StrSplit(cleanTarget, " ")[1]

            ; Warn if path looks like a file/folder that doesn't exist
            ; (avoids 10-30 second freeze on missing network shares)
            if (InStr(testPath, "\") && !FileExist(testPath)) {
                PlayFeedback("ErrorSound")
                MsgBox("Target not found - it may be offline or the path has moved.`n`n" .
                       testPath, "Launch Error", "Icon!")
                return
            }
            Run(cleanTarget)
        }
        PlayFeedback("LaunchSound")
    } catch Error as err {
        PlayFeedback("ErrorSound")
        MsgBox("Could not launch: " . cleanTarget . "`n`nError: " . err.Message,
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

    ; ── Step 4: record history using the fully-resolved string ───────────────
    RecordExpansionHistory(sc, sc, resolved)
    TrackUsage(sc, "expansion")
    PlayFeedback("ExpandSound")

    ; ── Step 3: split into segments on sequence tokens ───────────────────────
    ;   Tokens recognised:
    ;     {key:X}         – send keystroke X (any AHK Send key notation)
    ;     {wait:N}        – sleep N milliseconds
    ;     {focus:Title}   – activate window whose title contains Title
    ;
    ;   A 150 ms pause is inserted automatically before every {key:} so the
    ;   target application has time to open dialogs or move focus.
    ;
    ;   {cursor} / {cursor:N} still work and are processed at the very end.
    ; ─────────────────────────────────────────────────────────────────────────

    ; Check whether any sequence tokens are present at all
    ; Simple check: just look for {key: or {wait: or {focus: anywhere in the string
    hasSequence := (InStr(resolved, "{key:") || InStr(resolved, "{wait:") || InStr(resolved, "{focus:"))

    if (!hasSequence) {
        ; ── Simple (no-sequence) path – original behaviour ──────────────────
        cursorPos := 0
        if (RegExMatch(resolved, "\{cursor(?::(\d+))?\}", &m)) {
            if (m[1] != "")
                cursorPos := Integer(m[1])
            else
                cursorPos := StrLen(resolved) - InStr(resolved, "{cursor}") + 1 - StrLen(m[0])
            resolved := StrReplace(resolved, m[0], "")
        }
        SendExpandText(resolved, config)
        if (cursorPos > 0)
            Send("{Left " . cursorPos . "}")
        return
    }

    ; ── Sequence path ────────────────────────────────────────────────────────
    ; Walk character-by-character through resolved, collecting text segments
    ; and sequence tokens, then execute them in order.

    cursorPos := 0
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

                ; Flush any accumulated text first
                if (textAccum != "") {
                    ; Handle {cursor} in accumulated text
                    if (RegExMatch(textAccum, "\{cursor(?::(\d+))?\}", &cm)) {
                        if (cm[1] != "")
                            cursorPos := Integer(cm[1])
                        else
                            cursorPos := StrLen(textAccum) - InStr(textAccum, "{cursor}") + 1 - StrLen(cm[0])
                        textAccum := StrReplace(textAccum, cm[0], "")
                    }
                    SendExpandText(textAccum, config)
                    textAccum := ""
                }

                ; Parse and execute the token
                ; seqTok is like {key:VALUE} or {wait:500} or {focus:Title}
                ; Fix 5: guard against malformed tokens like {key:} with empty value
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
                    ms := Integer(stokValue)
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

    ; Flush remaining text
    if (textAccum != "") {
        if (RegExMatch(textAccum, "\{cursor(?::(\d+))?\}", &cm)) {
            if (cm[1] != "")
                cursorPos := Integer(cm[1])
            else
                cursorPos := StrLen(textAccum) - InStr(textAccum, "{cursor}") + 1 - StrLen(cm[0])
            textAccum := StrReplace(textAccum, cm[0], "")
        }
        SendExpandText(textAccum, config)
    }

    if (cursorPos > 0)
        Send("{Left " . cursorPos . "}")
}

; Helper – sends a text chunk, choosing SendEvent for large blocks
SendExpandText(txt, cfg) {
    ; Use clipboard paste for all expansions - works in browsers and all apps
    savedClip := ClipboardAll()
    A_Clipboard := txt
    if (ClipWait(1)) {
        Send("^v")
        Sleep(150)  ; wait for target app to process paste before sending space
        Send(" ")   ; send space as separate keystroke - not clipped, not trimmed
    } else {
        if (StrLen(txt) > cfg["Performance"]["LargeTextThreshold"])
            SendEvent(txt . " ")
        else
            SendText(txt . " ")
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
    global textExpansionPath, loadedExpansions, registeredExpansions
    ; Disable previously registered hotstrings using stored options
    for sc, opts in registeredExpansions {
        try Hotstring(opts . sc, , "Off")
    }
    registeredExpansions := Map()
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
    global textExpansionPath, config
    wc := config["Triggers"]["WinCmd"]       ; default ";"

    defaults := [
        ; ── Date shortcuts (= family) ──────────────────
        ["-=",   "{date:MMMM d, yyyy}"],            ; full date
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

        ; ── ; family - the curated built-in command set ─
        ; All entries here work cleanly as typed triggers - no selection
        ; or clipboard dependencies that the trigger characters would disrupt.
        ;
        ; File ops (typing the trigger doesn't disrupt these)
        [wc . "s",  "{key:^s}"],                    ; Save (Ctrl+S)
        [wc . "S",  "{key:^+s}"],                   ; Save As (Ctrl+Shift+S)
        [wc . "n",  "{key:^n}"],                    ; New
        [wc . "o",  "{key:^o}"],                    ; Open
        [wc . "p",  "{key:^p}"],                    ; Print
        [wc . "w",  "{key:^w}"],                    ; Close tab / window
        [wc . "r",  "{key:F5}"],                    ; Refresh

        ; Editing - the safe ones
        [wc . "A",  "{key:^a}{wait:50}{key:^c}"],   ; Select All AND Copy (capital)

        ; App switching
        [wc . "a",  "{key:!{Tab}}"],                ; Switch app - Alt+Tab

        ; Document navigation (cursor moves, no content risk)
        [wc . "t",  "{key:^{Home}}"],               ; Top of page (Ctrl+Home)
        [wc . "b",  "{key:^{End}}"],                ; Bottom of page (Ctrl+End)
        [wc . "u",  "{key:{PgUp}}"],                ; Page Up
        [wc . "d",  "{key:{PgDn}}"],                ; Page Down
        [wc . "l",  "{key:{Home}}"],                ; Line start
        [wc . "e",  "{key:{End}}"],                 ; Line end

        ; Window management
        [wc . "<",  "{key:#{Left}}"],               ; Snap window left (Win+Left)
        [wc . ">",  "{key:#{Right}}"],              ; Snap window right (Win+Right)
        [wc . "m",  "{key:#{Down}}"],               ; Minimize window

        ; CAPITALS - paired actions
        [wc . "L",  "{key:#l}"],                    ; Lock PC (Win+L)
        [wc . "E",  "{key:#.}"],                    ; Emoji picker (Win+.)
        [wc . "T",  "{key:^+{Escape}}"],            ; Task Manager (Ctrl+Shift+Esc)
    ]
    existing := FileExist(textExpansionPath) ? FileRead(textExpansionPath, "UTF-8") : ""
    for entry in defaults {
        sc  := entry[1]
        exp := entry[2]
        if (!RegExMatch(existing, "(?m)^\Q" . sc . "\E "))
            LockedFileAppend(textExpansionPath, sc . " " . exp . "`n")
    }

    ; Seed the ` launcher family - lives in launchers.ahk
    SeedDefaultLaunchers()
}

SeedDefaultLaunchers() {
    global launcherPath, config
    wc := config["Triggers"]["WinCmd"]       ; default ";"   - for built-in Windows apps
    al := config["Triggers"]["AppLaunch"]    ; default "`"  - for user-facing launchers

    defaults := [
        ; ── ; family - Windows built-in apps (single prefix) ──
        ; These live in launchers.ahk (not text_expansion.ahk) because
        ; they execute programs/URIs, not type text.
        [wc . "c",  "calc.exe"],                    ; Calculator
        [wc . "q",  "ms-screenclip:"],              ; Snipping Tool
        [wc . "f",  "explorer.exe"],                ; File Explorer

        ; ── ` family - AI launchers ─────────────────────
        ; Backtick prefix is collision-free in normal typing.
        ; For motivated users, the setup guide explains how to remap
        ; CapsLock and middle-click to backtick for one-touch access.
        [al . "a",  "https://chatgpt.com"],         ; ChatGPT
        [al . "c",  "https://claude.ai"],           ; Claude
        [al . "g",  "https://gemini.google.com"],   ; Gemini
        [al . "p",  "https://perplexity.ai"],       ; Perplexity

        ; ── ` family - Google quick-access (number row) ─
        ; Backtick is right next to the 1 key, so `1 / `2 / `3 are
        ; a tiny finger movement even without remapping CapsLock.
        [al . "1",  "https://voice.google.com"],    ; Google Voice
        [al . "2",  "https://mail.google.com"],     ; Gmail
        [al . "3",  "https://calendar.google.com"], ; Google Calendar
    ]
    existing := FileExist(launcherPath) ? FileRead(launcherPath, "UTF-8") : ""
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
    global config, activeInputHook
    if (!A_IsSuspended) {
        ; Kill any active combo InputHook before suspending
        if (activeInputHook != "") {
            try activeInputHook.Stop()
            activeInputHook := ""
        }
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
; Save stats on exit so nothing is lost
OnExit((*) => SaveUsageStats())

;------------------------------------------------
; END OF SCRIPT
;------------------------------------------------
