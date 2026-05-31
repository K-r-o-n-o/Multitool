#Requires AutoHotkey v2.0
#SingleInstance Force

; ##################################################################
; #                          MULTITOOL                             #
; #                                                                #
; #  A small tray app bundling seven tools + a custom-hotkey slot,  #
; #  all configurable from a settings window (tray -> Settings).   #
; #                                                                #
; #    1. Selection translator    (Google free / optional DeepL)   #
; #    2. Keyboard-layout fixer    (EN <-> RU same-key remap)      #
; #    3. Typo fixer              (LanguageTool API)               #
; #    4. Rotating rainbow border  (screen-edge overlay)           #
; #    5. Git auto-push            (add/commit/push a folder)      #
; #    6. Pin-on-top               (click-through overlay window)   #
; #    7. Keystroke sentinel       (rhythm-based screen lock)       #
; #    +. Custom hotkeys           (5 user-defined Run/Paste slots) #
; #                                                                #
; #  Settings persist to "multitool.ini" beside this script.       #
; #  Every hotkey is reassignable in the settings window.          #
; #  Save blocks if two settings share the same hotkey.            #
; #  Hotkey notation:  ^ = Ctrl   ! = Alt   # = Win   + = Shift     #
; #                                                                #
; #  DEFAULT hotkeys (change them in Settings):                    #
; #    Ctrl+Alt+T       translate selection -> popup               #
; #    Ctrl+Alt+C       translate + copy to clipboard              #
; #    Ctrl+Alt+R       translate + replace selection in place     #
; #    Ctrl+Win+L / K   layout-fix convert+copy / replace          #
; #    Ctrl+Alt+F       fix typos in selection                     #
; #    Ctrl+Win+B       toggle rainbow border                      #
; #    Ctrl+Win+D       git push (add/commit/push)                 #
; #    Win+T / Win+C    pin window / unpin all                     #
; #    Ctrl+Win+S       open Settings                              #
; #    (set in Settings) toggle keystroke sentinel                 #
; #    Ctrl+Win+Q       quit MultiTool                             #
; #    Esc              close an open popup (fixed, not config.)    #
; ##################################################################


; True physical pixels under DPI scaling (used by the rainbow border)
try DllCall("SetThreadDpiAwarenessContext", "ptr", -4)   ; PER_MONITOR_AWARE_V2

INI := A_ScriptDir "\multitool.ini"

; --- bump this when you publish a new GitHub release ---
APP_VERSION := "1.2.0"
GITHUB_REPO := "K-r-o-n-o/Multitool"


; ==================================================================
; ===  SETTINGS SCHEMA  ============================================
; ==================================================================
; One entry per setting. Drives loading, saving, AND the GUI.
;   sec/key : INI section + key (also the control id "sec_key")
;   label   : shown in the settings window
;   type    : "hotkey" | "string" | "int" | "float" | "choice" | "bool"
;   def     : default value (string)
;   choices : array, only for type "choice"
Schema := [
    {sec:"Translator", key:"Provider",      label:"Provider",              type:"choice", def:"Google",
        choices:["Google","DeepL"]},
    {sec:"Translator", key:"HotkeyPopup",   label:"Translate -> popup",    type:"hotkey", def:"^!t"},
    {sec:"Translator", key:"HotkeyCopy",    label:"Translate + copy",      type:"hotkey", def:"^!c"},
    {sec:"Translator", key:"HotkeyReplace", label:"Translate in place",    type:"hotkey", def:"^!r"},
    {sec:"Translator", key:"SourceLang",   label:"Source language",      type:"choice", def:"auto",
        choices:["auto","EN","RU","DE","FR","ES","IT","PT","JA","ZH"]},
    {sec:"Translator", key:"DeepLKey",     label:"DeepL API key",        type:"string", def:""},
    {sec:"Translator", key:"PopupWidth",   label:"Popup width (px)",     type:"int",    def:"360"},
    {sec:"Translator", key:"PopupTimeout", label:"Timeout ms (0=stay)",  type:"int",    def:"3000"},
    {sec:"Translator", key:"PopupAlpha",   label:"Opacity (0-255)",      type:"int",    def:"125"},

    {sec:"LayoutFix",  key:"HotkeyConvert", label:"Convert + copy",       type:"hotkey", def:"^#l"},
    {sec:"LayoutFix",  key:"HotkeyReplace", label:"Replace in place",     type:"hotkey", def:"^#k"},
    {sec:"LayoutFix",  key:"Opacity",       label:"Opacity (0-255)",      type:"int",    def:"150"},
    {sec:"LayoutFix",  key:"DisplayTime",   label:"Display ms (0=stay)",  type:"int",    def:"3000"},
    {sec:"LayoutFix",  key:"MaxWidth",      label:"Popup width (px)",     type:"int",    def:"380"},
    {sec:"LayoutFix",  key:"FontSize",      label:"Font size",            type:"int",    def:"12"},

    {sec:"TypoFix",    key:"HotkeyFix", label:"Fix typos in selection", type:"hotkey", def:"^!f"},
    {sec:"TypoFix",    key:"Lang",      label:"Language",               type:"choice", def:"auto",
        choices:["auto","en-US","en-GB","ru-RU","de-DE","fr-FR","es","it","pt-PT"]},

    {sec:"Rainbow",    key:"Enabled",      label:"Enabled at startup",   type:"bool",   def:"1"},
    {sec:"Rainbow",    key:"HotkeyToggle", label:"Toggle border",        type:"hotkey", def:"^#b"},
    {sec:"Rainbow",    key:"Thick",        label:"Border width (px)",    type:"int",    def:"2"},
    {sec:"Rainbow",    key:"BottomGap",    label:"Bottom gap (px)",      type:"int",    def:"2"},
    {sec:"Rainbow",    key:"Speed",        label:"Rotation speed",       type:"float",  def:"0.025"},
    {sec:"Rainbow",    key:"Interval",     label:"Frame ms (~33=30fps)", type:"int",    def:"33"},
    {sec:"Rainbow",    key:"Sat",          label:"Saturation (0-1)",     type:"float",  def:"1.0"},
    {sec:"Rainbow",    key:"Val",          label:"Brightness (0-1)",     type:"float",  def:"1.0"},

    {sec:"Push",       key:"Hotkey",  label:"Push hotkey",         type:"hotkey", def:"^#d"},
    {sec:"Push",       key:"Path",    label:"Project folder",      type:"string", def:""},
    {sec:"Push",       key:"RepoUrl", label:"Repo URL (optional)", type:"string", def:""},
    {sec:"Push",       key:"Branch",  label:"Branch",              type:"string", def:""},
    {sec:"Push",       key:"Msg",     label:"Commit message",      type:"string", def:"auto-push via script"},
    {sec:"Push",       key:"Shell",   label:"Terminal",            type:"choice", def:"cmd", choices:["cmd","powershell"]},
    {sec:"Push",       key:"Token",   label:"GitHub token",        type:"string", def:""},

    {sec:"Pin",        key:"HotkeyPin",   label:"Pin (click-through)", type:"hotkey", def:"#t"},
    {sec:"Pin",        key:"HotkeyUnpin", label:"Unpin all",           type:"hotkey", def:"#c"},
    {sec:"Pin",        key:"Alpha",       label:"Pinned opacity",      type:"int",    def:"150"},

    {sec:"Security",   key:"Enabled",      label:"Enable keystroke sentinel", type:"bool",   def:"0"},
    {sec:"Security",   key:"HotkeyToggle", label:"Toggle sentinel",           type:"hotkey", def:""},
    {sec:"Security",   key:"PythonPath",   label:"Python executable",         type:"string", def:"python"},

    {sec:"Custom", key:"Hotkey1", label:"#1", type:"hotkey", def:""},
    {sec:"Custom", key:"Type1",   label:"#1", type:"choice", def:"Run", choices:["Run","Paste"]},
    {sec:"Custom", key:"Action1", label:"#1", type:"string", def:""},
    {sec:"Custom", key:"Hotkey2", label:"#2", type:"hotkey", def:""},
    {sec:"Custom", key:"Type2",   label:"#2", type:"choice", def:"Run", choices:["Run","Paste"]},
    {sec:"Custom", key:"Action2", label:"#2", type:"string", def:""},
    {sec:"Custom", key:"Hotkey3", label:"#3", type:"hotkey", def:""},
    {sec:"Custom", key:"Type3",   label:"#3", type:"choice", def:"Run", choices:["Run","Paste"]},
    {sec:"Custom", key:"Action3", label:"#3", type:"string", def:""},
    {sec:"Custom", key:"Hotkey4", label:"#4", type:"hotkey", def:""},
    {sec:"Custom", key:"Type4",   label:"#4", type:"choice", def:"Run", choices:["Run","Paste"]},
    {sec:"Custom", key:"Action4", label:"#4", type:"string", def:""},
    {sec:"Custom", key:"Hotkey5", label:"#5", type:"hotkey", def:""},
    {sec:"Custom", key:"Type5",   label:"#5", type:"choice", def:"Run", choices:["Run","Paste"]},
    {sec:"Custom", key:"Action5", label:"#5", type:"string", def:""},

    {sec:"General",    key:"Theme",          label:"App theme",      type:"choice", def:"Solarized Dark", choices:["Solarized Dark","Light","Dark","High Contrast"]},
    {sec:"General",    key:"UpdatesMode",    label:"Updates",        type:"choice", def:"Notify",        choices:["Off","Notify","Auto"]},
    {sec:"General",    key:"HotkeyQuit",     label:"Quit MultiTool", type:"hotkey", def:"^#q"},
    {sec:"General",    key:"HotkeySettings", label:"Open Settings",  type:"hotkey", def:"^#s"},
    {sec:"General",    key:"RunOnStartup",   label:"Run on Windows startup", type:"bool", def:"0"}
]

; Section -> friendly caption, used for the nested sub-tabs.
TabNames := Map("Translator","Translator", "LayoutFix","Layout Fix", "TypoFix","Typo Fix",
                "Rainbow","Rainbow", "Pin","Pin")

; Top-level settings tabs, in order. Each page lists the Schema section(s) it
; shows. A page with one section renders that section directly; a page with
; several renders them as nested sub-tabs:
;   Text   -> Translator / Layout Fix / Typo Fix   (all transform a selection)
;   Screen -> Rainbow / Pin                         (always-on-top overlays)
; INI section names are unchanged, so existing multitool.ini configs load as-is.
TabLayout := [
    {name:"Text",     subs:["Translator","LayoutFix","TypoFix"]},
    {name:"Screen",   subs:["Rainbow","Pin"]},
    {name:"For Devs", subs:["Push"]},
    {name:"Custom",   subs:["Custom"]},
    {name:"Security", subs:["Security"]},
    {name:"General",  subs:["General"]}
]

; --- the layout map: Latin key char -> Cyrillic char on the same key ---
; (this is fixed, not exposed in the settings window)
gFwd := Map(
    "q","й", "w","ц", "e","у", "r","к", "t","е", "y","н", "u","г", "i","ш",
    "o","щ", "p","з", "[","х", "]","ъ",
    "a","ф", "s","ы", "d","в", "f","а", "g","п", "h","р", "j","о", "k","л",
    "l","д", ";","ж", "'","э",
    "z","я", "x","ч", "c","с", "v","м", "b","и", "n","т", "m","ь", ",","б",
    ".","ю", "/",".", "``","ё",
    "{","Х", "}","Ъ", ":","Ж", '"',"Э", "<","Б", ">","Ю", "?",",", "~","Ё"
)


; ==================================================================
; ===  GLOBAL STATE  ===============================================
; ==================================================================
C       := Map()        ; live config: "Sec_Key" -> string value
Ctrls   := Map()        ; settings-window controls: "Sec_Key" -> Gui control
Labels  := Map()        ; "Sec_Key" -> label text control (when present)
g_Set   := ""           ; the settings Gui (when open)
ActiveHotkeys := []     ; hotkey strings currently registered

Popup    := ""          ; translator popup
popupGui := 0           ; layout-fix popup
popupGen := 0
PinnedWindows := Map()  ; hwnd -> true (currently click-through)

; rainbow-border module state (b* prefix)
bBuilt := false, bActive := false
bGui := "", bMemDC := 0, bHbm := 0, bOldBmp := 0, bPBits := 0
bW := 0, bH := 0, bInvP := 0.0, bThick := 2, bSpeed := 0.025
bInterval := 33, bOffset := 0.0, bPalette := []
bPtDst := "", bSzWin := "", bPtSrc := "", bBlend := ""

; keystroke-sentinel module state -- must be assigned before Sec_Apply runs
; in STARTUP below, so we keep it up here rather than next to the helpers.
SentinelPID := 0


; ==================================================================
; ===  STARTUP  ====================================================
; ==================================================================
LoadConfig()
BuildMaps()
BuildBorder()
RegisterHotkeys()
SetupTray()
OnExit(OnExitHandler)
Sec_Apply(false)   ; resume the keystroke sentinel if it was left enabled
TrayTip("Right-click the tray icon -> Settings to configure.", "MultiTool loaded")

; Background update check 5 s after startup so it doesn't slow boot.
if (CfgS("General_UpdatesMode") != "Off")
    SetTimer((*) => CheckForUpdates(false), -5000)


; --- Esc closes whichever popup is showing (fixed, context-sensitive) ---
#HotIf IsObject(Popup)
Esc:: Tr_ClosePopup()
#HotIf

#HotIf popupGui
Esc:: Lf_ClosePopup()
#HotIf


; ==================================================================
; ===  CONFIG LOAD / SAVE  =========================================
; ==================================================================
LoadConfig() {
    global C, Schema, INI
    MigrateIni()
    for item in Schema {
        k := item.sec "_" item.key
        C[k] := IniRead(INI, item.sec, item.key, item.def)
    }
}

; v1.0.x stored the git auto-push settings under [Deploy]. v1.1 renamed the
; section to [Push]. If we still see a [Deploy] section in the user's INI
; and [Push] isn't populated yet, copy the keys across and drop the old one.
MigrateIni() {
    global INI
    deploySection := ""
    try deploySection := IniRead(INI, "Deploy")
    if (deploySection = "")
        return
    pushSection := ""
    try pushSection := IniRead(INI, "Push")
    if (pushSection != "")
        return
    for line in StrSplit(deploySection, "`n", "`r") {
        if (line = "" || !InStr(line, "="))
            continue
        eq := InStr(line, "=")
        IniWrite(SubStr(line, eq + 1), INI, "Push", SubStr(line, 1, eq - 1))
    }
    try IniDelete(INI, "Deploy")
}

SaveConfig() {
    global C, Schema, INI
    for item in Schema {
        k := item.sec "_" item.key
        IniWrite(C[k], INI, item.sec, item.key)
    }
}

CfgS(k) {
    global C
    return C.Has(k) ? C[k] : ""
}
CfgI(k) {
    v := CfgS(k)
    return (v = "") ? 0 : Integer(Round(Number(v)))
}
CfgN(k) {
    v := CfgS(k)
    return (v = "") ? 0 : Number(v)
}


; ==================================================================
; ===  AUTO-UPDATE  ================================================
; ==================================================================
; Queries the latest GitHub release for GITHUB_REPO, compares its tag
; to APP_VERSION, and either notifies the user or self-installs (per
; the General -> Updates setting). The script's own .exe is replaced
; via a tiny helper batch file that waits for this process to exit
; before swapping the file in place.
CheckForUpdates(interactive) {
    global APP_VERSION, GITHUB_REPO

    try {
        url := "https://api.github.com/repos/" GITHUB_REPO "/releases/latest"
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.Open("GET", url, false)
        req.SetRequestHeader("User-Agent", "MultiTool-Updater")
        req.SetRequestHeader("Accept", "application/vnd.github+json")
        req.Send()
        if (req.Status = 404)
            throw Error("no releases published yet")
        if (req.Status != 200)
            throw Error("HTTP " req.Status)
        json := ReadUtf8Body(req)
    } catch as e {
        if interactive
            MsgBox("Update check failed:`n`n" e.Message, "MultiTool", "Icon!")
        return
    }

    if !RegExMatch(json, '"tag_name"\s*:\s*"v?([^"]+)"', &tm) {
        if interactive
            MsgBox("Could not read release tag from GitHub.", "MultiTool", "Icon!")
        return
    }
    latest := tm[1]

    if (CompareVersions(latest, APP_VERSION) <= 0) {
        if interactive
            MsgBox("You're up to date.`n`nCurrent: v" APP_VERSION "`nLatest:  v" latest,
                "MultiTool", "Iconi")
        return
    }

    ; Look only inside the release's "assets" array -- never the free-text
    ; release notes -- so a crafted notes body can't smuggle in a download URL.
    assetsBlock := json
    if (ap := InStr(json, '"assets":[')) {
        endA := InStr(json, '"tarball_url"', , ap)
        assetsBlock := endA ? SubStr(json, ap, endA - ap) : SubStr(json, ap)
    }

    ; Pick the first .exe asset and, if GitHub recorded one, its SHA-256 digest.
    assetUrl := "", assetSha := ""
    if RegExMatch(assetsBlock, '"browser_download_url"\s*:\s*"([^"]+\.exe)"', &am)
        assetUrl := am[1]
    if RegExMatch(assetsBlock, 'i)"digest"\s*:\s*"sha256:([0-9a-f]{64})"', &dm)
        assetSha := dm[1]
    if (assetUrl = "") {
        if interactive
            MsgBox("Release v" latest " is missing a .exe asset.", "MultiTool", "Icon!")
        return
    }
    ; The installer must come from GitHub's own HTTPS hosts. This stops a
    ; malformed or partly attacker-influenced response from pointing the
    ; download at an arbitrary server.
    if !IsGitHubDownload(assetUrl) {
        if interactive
            MsgBox("Refusing to download the update: the asset URL is not on a "
                "trusted GitHub host.`n`n" assetUrl, "MultiTool", "Icon!")
        return
    }

    mode := CfgS("General_UpdatesMode")
    if (mode = "Auto") {
        DoSelfUpdate(assetUrl, assetSha, latest, interactive)
        return
    }
    if interactive {
        r := MsgBox("Update available.`n`nCurrent: v" APP_VERSION "`nLatest:  v" latest
            "`n`nDownload and install now? MultiTool will restart.",
            "MultiTool Update", "YesNo Iconi")
        if (r = "Yes")
            DoSelfUpdate(assetUrl, assetSha, latest, true)
        return
    }
    ; Notify mode + automatic check on startup
    TrayTip("v" latest " is available (you have v" APP_VERSION ").`n"
        . "Right-click tray -> Check for updates to install.",
        "MultiTool Update")
}

CompareVersions(a, b) {
    aParts := StrSplit(a, ".")
    bParts := StrSplit(b, ".")
    n := Max(aParts.Length, bParts.Length)
    Loop n {
        i := A_Index
        ai := (i <= aParts.Length && IsNumber(aParts[i])) ? Integer(aParts[i]) : 0
        bi := (i <= bParts.Length && IsNumber(bParts[i])) ? Integer(bParts[i]) : 0
        if (ai > bi)
            return 1
        if (ai < bi)
            return -1
    }
    return 0
}

DoSelfUpdate(assetUrl, expectedSha, newVersion, interactive) {
    if !A_IsCompiled {
        if interactive
            MsgBox("Auto-update only works for the compiled .exe build.",
                "MultiTool", "Icon!")
        return
    }
    ; Defense in depth: never fetch the binary from anywhere but GitHub.
    if !IsGitHubDownload(assetUrl) {
        if interactive
            MsgBox("Refusing to download the update from an untrusted host.",
                "MultiTool", "Icon!")
        return
    }
    target  := A_ScriptFullPath
    ; Randomized temp names so another local process can't pre-create or swap
    ; the staged installer / batch at a predictable path between write and run.
    rnd     := Format("{:08x}{:08x}", Random(0, 0xFFFFFFFF), Random(0, 0xFFFFFFFF))
    tempExe := A_Temp "\MultiTool.update." rnd ".exe"
    tempBat := A_Temp "\MultiTool.update." rnd ".bat"

    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.Open("GET", assetUrl, false)
        req.SetRequestHeader("User-Agent", "MultiTool-Updater")
        req.Send()
        if (req.Status != 200)
            throw Error("HTTP " req.Status)
        stream := ComObject("ADODB.Stream")
        stream.Type := 1
        stream.Open()
        stream.Write(req.ResponseBody)
        stream.SaveToFile(tempExe, 2)
        stream.Close()
    } catch as e {
        if interactive
            MsgBox("Download failed:`n`n" e.Message, "MultiTool", "Icon!")
        return
    }

    ; Verify the download against the SHA-256 GitHub recorded for the asset,
    ; so a corrupted or swapped file is rejected before we run it. This is an
    ; integrity check, not a publisher signature -- if you start signing your
    ; releases, add an Authenticode (WinVerifyTrust) check here as well.
    if (expectedSha != "") {
        actualSha := FileSHA256(tempExe)
        if (actualSha = "" || actualSha != StrLower(expectedSha)) {
            try FileDelete(tempExe)
            if interactive
                MsgBox("Update integrity check failed -- the downloaded file's "
                    "hash does not match the release. Aborting update.",
                    "MultiTool", "Icon!")
            return
        }
    }

    ; A tiny batch waits for the current .exe to release the file, swaps
    ; in the new build, relaunches it, then deletes itself.
    batLines := [
        "@echo off",
        "timeout /t 2 /nobreak >nul",
        ":retry",
        'move /Y "' tempExe '" "' target '" >nul 2>&1',
        "if errorlevel 1 (timeout /t 1 /nobreak >nul & goto retry)",
        'start "" "' target '"',
        'del /Q "%~f0"'
    ]
    bat := ""
    for line in batLines
        bat .= line "`r`n"
    try FileDelete(tempBat)
    FileAppend(bat, tempBat)

    Run('"' tempBat '"', , "Hide")
    ExitApp()
}

; True only if `url` is an HTTPS download whose host is exactly github.com or a
; *.githubusercontent.com host (where GitHub serves release assets). Rejecting
; everything else -- including userinfo tricks like https://github.com@evil/ --
; keeps the updater from being redirected to an attacker-controlled server.
IsGitHubDownload(url) {
    if !RegExMatch(url, 'i)^https://([^/?#@]+)(?:[/?#]|$)', &m)
        return false
    host := StrLower(m[1])
    return (host = "github.com") || RegExMatch(host, 'i)(^|\.)githubusercontent\.com$')
}

; SHA-256 of a file as lowercase hex (via certutil, present on every Windows),
; or "" on failure. Whitespace is stripped so both the spaced (legacy) and the
; contiguous certutil hash layouts parse.
FileSHA256(path) {
    tmp := A_Temp "\multitool_hash_" Format("{:08x}", Random(0, 0xFFFFFFFF)) ".txt"
    try FileDelete(tmp)
    try RunWait(A_ComSpec ' /c "certutil -hashfile "' path '" SHA256 > "' tmp '" 2>nul"', , "Hide")
    out := ""
    try out := FileRead(tmp)
    try FileDelete(tmp)
    for line in StrSplit(out, "`n", "`r") {
        h := RegExReplace(Trim(line), "\s")
        if RegExMatch(h, "i)^[0-9a-f]{64}$")
            return StrLower(h)
    }
    return ""
}


; ==================================================================
; ===  HOTKEY REGISTRATION  ========================================
; ==================================================================
RegisterHotkeys() {
    global ActiveHotkeys
    for k in ActiveHotkeys
        try Hotkey(k, , "Off")
    ActiveHotkeys := []

    pairs := [
        [CfgS("Translator_HotkeyPopup"),  (*) => DoTranslate("popup")],
        [CfgS("Translator_HotkeyCopy"),   (*) => DoTranslate("copy")],
        [CfgS("Translator_HotkeyReplace"),(*) => DoTranslate("replace")],
        [CfgS("LayoutFix_HotkeyConvert"),(*) => FixLayout(false)],
        [CfgS("LayoutFix_HotkeyReplace"),(*) => FixLayout(true)],
        [CfgS("TypoFix_HotkeyFix"),      (*) => FixTypos()],
        [CfgS("Rainbow_HotkeyToggle"),   (*) => ToggleBorder()],
        [CfgS("Push_Hotkey"),            (*) => DoPush()],
        [CfgS("Pin_HotkeyPin"),          (*) => PinWindow()],
        [CfgS("Pin_HotkeyUnpin"),        (*) => UnpinAll()],
        [CfgS("Security_HotkeyToggle"),  (*) => Sec_Toggle()],
        [CfgS("General_HotkeyQuit"),     (*) => ExitApp()],
        [CfgS("General_HotkeySettings"), (*) => ShowSettings()]
    ]

    Loop 5 {
        i := A_Index
        hk := CfgS("Custom_Hotkey" i)
        ac := CfgS("Custom_Action" i)
        if (hk = "" || ac = "")
            continue
        ty := CfgS("Custom_Type" i)
        if (ty = "")
            ty := "Run"
        pairs.Push([hk, MakeCustomHandler(ty, ac)])
    }

    errs := ""
    for pair in pairs {
        key := pair[1], cb := pair[2]
        if (key = "")
            continue
        try {
            Hotkey(key, cb, "On")
            ActiveHotkeys.Push(key)
        } catch as e {
            errs .= "  " key "  -  " e.Message "`n"
        }
    }
    return errs
}

; Factory for custom-hotkey closures. A top-level function so each call
; gets its own scope and captures `action` correctly (loop iterations
; in AHK share a scope, so closing over loop variables directly would
; make all five handlers fire the last action).
MakeCustomHandler(type, action) {
    if (type = "Paste")
        return (*) => PasteText(action)
    return (*) => CustomRun(action)
}

CustomRun(action) {
    try Run(action)
    catch as e
        TrayTip("Custom hotkey failed: " e.Message, "MultiTool")
}


; ==================================================================
; ===  THEME  ======================================================
; ==================================================================
; Returns the palette for the currently selected theme.
;   bg/fg            : settings window background / default text color
;   editBg/editFg    : edit + dropdown background / text
;   hintFg           : muted hint line at the bottom of settings
;   popupBg/popupFg  : translator + layout-fix popup colors
;   popupAccent      : small tag text in the layout-fix popup
Theme_Palette(name) {
    switch name {
        case "Light":
            return {bg:"FFFFFF", fg:"000000", editBg:"FFFFFF", editFg:"000000", hintFg:"808080",
                    popupBg:"F5F5F5", popupFg:"202020", popupAccent:"2E7D32"}
        case "Dark":
            return {bg:"1E1E1E", fg:"E0E0E0", editBg:"2D2D2D", editFg:"F0F0F0", hintFg:"A0A0A0",
                    popupBg:"202124", popupFg:"E8EAED", popupAccent:"8AC691"}
        case "High Contrast":
            return {bg:"000000", fg:"FFFFFF", editBg:"000000", editFg:"FFFFFF", hintFg:"FFFF00",
                    popupBg:"000000", popupFg:"FFFFFF", popupAccent:"FFFF00"}
        default: ; Solarized Dark
            return {bg:"002B36", fg:"93A1A1", editBg:"073642", editFg:"EEE8D5", hintFg:"586E75",
                    popupBg:"002B36", popupFg:"EEE8D5", popupAccent:"859900"}
    }
}


; ==================================================================
; ===  SETTINGS WINDOW  ============================================
; ==================================================================
ShowSettings(*) {
    global g_Set, Ctrls, Labels, Schema, TabLayout, TabNames, C

    if IsObject(g_Set) {
        try {
            g_Set.Show()
            return
        }
    }

    t := Theme_Palette(CfgS("General_Theme"))

    Ctrls := Map()
    Labels := Map()
    g := Gui("+OwnDialogs -Resize -MaximizeBox", "MultiTool Settings")
    g.BackColor := t.bg
    g.SetFont("s10 c" t.fg, "Segoe UI")
    g_Set := g

    names := []
    for page in TabLayout
        names.Push(page.name)
    tab := g.AddTab3("x10 y10 w600 h378", names)

    ; Merged pages (Text, Screen) carry several tools. AHK can't nest Tab
    ; controls reliably -- a nested tab's controls don't hide when the OUTER
    ; tab changes, so they bleed onto every page. Instead we fake sub-tabs:
    ; a selector-button row plus manual show/hide of each tool's controls.
    ; Those controls all belong to the single outer page, which AHK *does*
    ; hide correctly when you switch top-level tabs.
    merged := Map()                ; outer tab index -> sub-tab state
    tabIdx := 0
    for page in TabLayout {
        tabIdx++
        tab.UseTab(tabIdx)
        if (page.subs.Length = 1)
            RenderSection(g, t, page.subs[1], 48)
        else
            merged[tabIdx] := BuildMergedTab(g, t, page.subs)
    }
    tab.UseTab(0)

    ; Switching back to a merged tab makes AHK re-show all of its controls
    ; (every sub-view at once), so reassert the active sub-view afterwards.
    tab.OnEvent("Change", ReassertSub)
    ReassertSub(*) {
        if merged.Has(tab.Value)
            ShowSub(merged[tab.Value], merged[tab.Value].cur)
    }

    g.SetFont("s9 c" t.hintFg, "Segoe UI")
    g.AddText("x16 y396 w380", "Hotkeys:   ^ Ctrl    ! Alt    # Win    + Shift")
    g.SetFont("s10 c" t.fg, "Segoe UI")

    g.AddButton("x380 y422 w72 h28", "Cancel").OnEvent("Click", (*) => g.Destroy())
    g.AddButton("x458 y422 w72 h28", "Apply").OnEvent("Click", ApplyAndRefresh)
    g.AddButton("x536 y422 w72 h28 +Default", "Save").OnEvent("Click", SaveAndClose)

    ApplyAndRefresh(*) {
        prevTheme := CfgS("General_Theme")
        if !ApplyFromControls()
            return
        if (CfgS("General_Theme") != prevTheme) {
            g.Destroy()
            ShowSettings()
        }
    }

    SaveAndClose(*) {
        if ApplyFromControls()
            g.Destroy()
    }

    g.OnEvent("Close", (*) => g.Destroy())
    g.OnEvent("Escape", (*) => g.Destroy())
    g.Show("w620 h468")
    ReassertSub()   ; the default tab is merged (Text) -- collapse it to sub 1
}

; Build one merged top-level tab (Text / Screen): a row of selector buttons
; plus each tool's controls rendered into the same area, then collapsed to
; the first tool. Returns the sub-tab state {subs, buttons, cur} that
; ShowSub uses to flip between tools.
BuildMergedTab(g, t, subs) {
    global TabNames
    state := {subs: [], buttons: [], cur: 1}

    ; Selector buttons across the top of the page act as the sub-tabs.
    bx := 16
    for i, sec in subs {
        btn := g.AddButton("x" bx " y40 w120 h26", TabNames[sec])
        btn.OnEvent("Click", SubBtnHandler(state, i))
        state.buttons.Push(btn)
        bx += 124
    }

    ; Render each tool below the buttons, capturing exactly the controls it
    ; created (including the Translator / Security extras) by diffing the
    ; GUI's control set before and after, so we can show/hide them as a group.
    ; Note: enumerate with TWO variables everywhere -- `for hwnd in g` binds
    ; the control OBJECT (1-var enum yields the value), so the hwnd keys would
    ; never match and every sub would capture every control.
    for i, sec in subs {
        seen := Map()
        for hwnd, ctrl in g
            seen[hwnd] := true
        refresh := RenderSection(g, t, sec, 78)
        ctrls := []
        for hwnd, ctrl in g
            if !seen.Has(hwnd)
                ctrls.Push(ctrl)
        state.subs.Push({ctrls: ctrls, refresh: refresh})
    }

    ShowSub(state, 1)
    return state
}

; Closure factory so each selector button captures its own index (AHK loop
; iterations share a scope, so closing over `i` directly would misbind).
SubBtnHandler(state, idx) {
    return (*) => ShowSub(state, idx)
}

; Show sub-tab `idx` of a merged page and hide the rest; bold the active
; selector button. A tool may hand back a refresh callback (the Translator
; provider toggle) to re-run each time it becomes visible.
ShowSub(state, idx) {
    state.cur := idx
    for j, sub in state.subs {
        vis := (j = idx)
        for ctrl in sub.ctrls
            ctrl.Visible := vis
        if (vis && sub.refresh)
            sub.refresh.Call()
    }
    for j, btn in state.buttons
        btn.SetFont(j = idx ? "Bold" : "Norm")
}

; Render one Schema section's controls onto the current (sub-)tab page,
; starting at vertical position yStart. Shared by the single-tool tabs
; (yStart 48) and the nested sub-tabs (yStart 78, leaving room for the
; inner tab strip). The Custom grid and the Translator / Security extras
; are handled as special cases, exactly as before the tabs were merged.
RenderSection(g, t, sec, yStart) {
    global Ctrls, Labels, Schema, C

    if (sec = "Custom") {
        BuildCustomTab(g, t)
        return ""
    }

    yPos := yStart
    for item in Schema {
        if (item.sec != sec)
            continue
        k := item.sec "_" item.key
        val := C.Has(k) ? C[k] : item.def

        if (item.type = "bool") {
            cb := g.AddCheckbox("x28 y" yPos " w470", item.label)
            cb.Value := (val = "1") ? 1 : 0
            Ctrls[k] := cb
        } else {
            lbl := g.AddText("x28 y" (yPos + 3) " w175", item.label ":")
            Labels[k] := lbl
            if (item.type = "choice") {
                dd := g.AddDropDownList("x210 y" yPos " w200 Background" t.editBg, item.choices)
                dd.Text := val
                Ctrls[k] := dd
            } else {
                w := (InStr(item.key, "Path") || InStr(item.key, "Url")) ? 300 : (item.type = "hotkey" ? 150 : 200)
                eOpt := "x210 y" yPos " w" w " Background" t.editBg
                if InStr(item.key, "Token")            ; mask secrets on screen
                    eOpt .= " Password"
                ed := g.AddEdit(eOpt, val)
                Ctrls[k] := ed
            }
        }
        yPos += 31
    }
    refresh := ""
    if (sec = "Translator")
        refresh := ExtendTranslatorTab(g, t, &yPos)
    if (sec = "Security")
        ExtendSecurityTab(g, t, &yPos)
    if (sec = "Push")
        ExtendPushTab(g, t, &yPos)
    return refresh
}

; After the Translator section renders, drop a help link below the API
; key field and wire the Provider dropdown so the key row is hidden
; unless the user picks DeepL (Google needs no key).
ExtendTranslatorTab(g, t, &yPos) {
    global Ctrls, Labels
    if (!Ctrls.Has("Translator_Provider") || !Ctrls.Has("Translator_DeepLKey"))
        return ""
    provDD := Ctrls["Translator_Provider"]
    keyEd  := Ctrls["Translator_DeepLKey"]
    keyLbl := Labels.Has("Translator_DeepLKey") ? Labels["Translator_DeepLKey"] : ""

    keyEd.GetPos(, &kY, , &kH)
    g.SetFont("s9 c" t.hintFg, "Segoe UI")
    keyLink := g.AddLink("x210 y" (kY + kH + 4) " w300",
        'Get a free key (500k chars/month): <a href="https://www.deepl.com/pro-api">deepl.com/pro-api</a>')
    g.SetFont("s10 c" t.fg, "Segoe UI")
    yPos += 22

    toggle(*) {
        show := (provDD.Text = "DeepL")
        keyEd.Visible := show
        keyLink.Visible := show
        if keyLbl
            keyLbl.Visible := show
    }
    provDD.OnEvent("Change", toggle)
    toggle()
    return toggle
}

; After the Security section renders its checkbox / hotkey / python rows,
; add an "Enroll" button, a live profile-status line, and the honest
; warning that this is a deterrent -- real protection lives in Windows.
ExtendSecurityTab(g, t, &yPos) {
    g.SetFont("s10 c" t.fg, "Segoe UI")
    g.AddButton("x28 y" yPos " w200 h28", "Enroll typing profile...")
        .OnEvent("Click", (*) => Sec_Enroll())

    g.SetFont("s9 c" t.hintFg, "Segoe UI")
    g.AddText("x240 y" (yPos + 6) " w300", Sec_StatusLine())
    yPos += 42

    g.SetFont("s10 bold c" t.popupAccent, "Segoe UI")
    g.AddText("x28 y" yPos " w540",
        "For much better security you have to use Real protection on Windows "
        "(BitLocker + Windows Hello + Dynamic Lock).")
    yPos += 50

    g.SetFont("s9 c" t.hintFg, "Segoe UI")
    g.AddText("x28 y" yPos " w540",
        "The sentinel watches only your typing rhythm (timing aggregates -- never "
        "the keys or text you type) and locks the screen if the rhythm stops "
        "matching your profile. Enroll once, then tick Enable. Anyone with access "
        "to your unlocked session can still close it, so treat it as a deterrent.")
    yPos += 56

    g.AddText("x28 y" yPos " w540",
        "Needs Python on this PC with: scikit-learn, numpy, pynput  "
        "(pip install -r requirements.txt).")
    g.SetFont("s10 c" t.fg, "Segoe UI")
}

; After the For Devs (git push) rows render, add a "Create a release" button.
; The release is published from the app -- via the GitHub CLI if it's logged
; in, else the GitHub token above -- with the browser only as a fallback.
ExtendPushTab(g, t, &yPos) {
    yPos += 10
    g.SetFont("s10 c" t.fg, "Segoe UI")
    g.AddButton("x28 y" yPos " w200 h28", "Create a release...")
        .OnEvent("Click", (*) => DoRelease())

    g.SetFont("s9 c" t.hintFg, "Segoe UI")
    g.AddText("x240 y" (yPos + 4) " w344",
        "Publishes a GitHub release (tag, notes, files) on the Branch above, via "
        "GitHub CLI or your token -- no browser needed. The token is stored in "
        "multitool.ini in plain text.")
    yPos += 50
    g.SetFont("s10 c" t.fg, "Segoe UI")
}

; Renders the Custom tab as five rows of {Hotkey, Type, Action} so the
; user can bind arbitrary commands or text snippets.
BuildCustomTab(g, t) {
    global Ctrls, C, Schema

    g.SetFont("s10 bold c" t.fg, "Segoe UI")
    g.AddText("x48 y42 w110",  "Hotkey")
    g.AddText("x162 y42 w90",  "Type")
    g.AddText("x258 y42 w240", "Action")
    g.SetFont("s10 norm c" t.fg, "Segoe UI")

    yPos := 70
    Loop 5 {
        i := A_Index
        hkKey  := "Custom_Hotkey" i
        tyKey  := "Custom_Type"   i
        acKey  := "Custom_Action" i
        valHk  := C.Has(hkKey) ? C[hkKey] : ""
        valTy  := C.Has(tyKey) ? C[tyKey] : "Run"
        valAc  := C.Has(acKey) ? C[acKey] : ""
        if (valTy = "")
            valTy := "Run"

        g.AddText("x28 y" (yPos + 3) " w20", "#" i)
        edH := g.AddEdit("x48 y" yPos " w110 Background" t.editBg, valHk)
        ddT := g.AddDropDownList("x162 y" yPos " w90 Background" t.editBg, ["Run","Paste"])
        ddT.Text := valTy
        edA := g.AddEdit("x258 y" yPos " w240 Background" t.editBg, valAc)

        Ctrls[hkKey] := edH
        Ctrls[tyKey] := ddT
        Ctrls[acKey] := edA
        yPos += 36
    }

    g.SetFont("s9 c" t.hintFg, "Segoe UI")
    g.AddText("x28 y" (yPos + 6) " w470",
        "Run: a program, file, URL, or shell command (e.g. notepad.exe, https://google.com, C:\path\file.bat).")
    g.AddText("x28 y" (yPos + 24) " w470",
        "Paste: types the text into the active window via clipboard.")
    g.AddText("x28 y" (yPos + 42) " w470",
        "Leave a row blank to disable it.")
    g.SetFont("s10 c" t.fg, "Segoe UI")
}

; Scan the live settings-window controls for two settings sharing the same
; hotkey. Returns a multi-line description of conflicts, or "" if none.
CheckCollisions() {
    global Ctrls, Schema
    seen := Map()    ; hotkey string -> array of labels
    for item in Schema {
        if (item.type != "hotkey")
            continue
        k := item.sec "_" item.key
        if !Ctrls.Has(k)
            continue
        val := Trim(Ctrls[k].Value)
        if (val = "")
            continue
        label := (item.sec = "Custom") ? "Custom " item.label : item.sec ": " item.label
        if !seen.Has(val)
            seen[val] := []
        seen[val].Push(label)
    }
    msg := ""
    for hk, labels in seen {
        if (labels.Length > 1) {
            joined := ""
            for l in labels
                joined .= (joined = "" ? "" : ", ") l
            msg .= "  " hk "   <-   " joined "`n"
        }
    }
    return msg
}

ApplyFromControls() {
    global Ctrls, Schema, C

    conflicts := CheckCollisions()
    if (conflicts != "") {
        MsgBox("Hotkey conflicts (same key bound to multiple actions):`n`n"
            conflicts "`nClear or change one of each pair, then try again.",
            "MultiTool", "Icon!")
        return false
    }

    for item in Schema {
        k := item.sec "_" item.key
        if !Ctrls.Has(k)
            continue
        ctrl := Ctrls[k]
        switch item.type {
            case "bool":   C[k] := ctrl.Value ? "1" : "0"
            case "choice": C[k] := ctrl.Text
            default:       C[k] := ctrl.Value
        }
    }

    SaveConfig()
    errs := RegisterHotkeys()
    BuildBorder()
    SetStartup(C["General_RunOnStartup"] = "1")
    Sec_Apply()

    if (errs != "") {
        MsgBox("Some hotkeys could not be set:`n`n" errs "`nThe rest were applied.",
            "MultiTool", "Icon!")
        return false
    }
    TrayTip("Settings applied.", "MultiTool")
    return true
}


; ==================================================================
; ===  RUN ON STARTUP  =============================================
; ==================================================================
SetStartup(enable) {
    link := A_Startup "\MultiTool.lnk"
    try {
        if (enable) {
            if A_IsCompiled
                FileCreateShortcut(A_ScriptFullPath, link, A_ScriptDir)
            else
                FileCreateShortcut(A_AhkPath, link, A_ScriptDir, '"' A_ScriptFullPath '"')
        } else if FileExist(link) {
            FileDelete(link)
        }
    }
}


; ==================================================================
; ===  TRAY  =======================================================
; ==================================================================
SetupTray() {
    global APP_VERSION
    tray := A_TrayMenu
    tray.Delete()
    tray.Add("Settings", (*) => ShowSettings())
    tray.Add("Check for updates", (*) => CheckForUpdates(true))
    tray.Add("Reload", (*) => Reload())
    tray.Add()
    tray.Add("MultiTool v" APP_VERSION, (*) => 0)
    tray.Disable("MultiTool v" APP_VERSION)
    tray.Add("Exit", (*) => ExitApp())
    tray.Default := "Settings"
}


; ==================================================================
; ===  1. TRANSLATOR  ==============================================
; ==================================================================
; mode: "popup" shows result, "copy" copies to clipboard + shows popup,
; "replace" pastes the translation over the selection. Target language
; is auto-picked: Cyrillic selection -> English, else -> Russian.
DoTranslate(mode) {
    saved := ClipboardAll()
    A_Clipboard := ""
    Send("^c")
    if !ClipWait(1) {
        A_Clipboard := saved
        return
    }
    text := Trim(A_Clipboard)
    A_Clipboard := saved
    if (text = "")
        return

    target := RegExMatch(text, "[\x{0400}-\x{04FF}]") ? "EN-US" : "RU"
    provider := CfgS("Translator_Provider")
    if (provider = "DeepL")
        result := DeepL_Translate(text, CfgS("Translator_SourceLang"), target)
    else
        result := Google_Translate(text, CfgS("Translator_SourceLang"), target)

    if !result.ok {
        Tr_ShowPopup(result.text)
        return
    }

    switch mode {
        case "copy":
            A_Clipboard := result.text
            Tr_ShowPopup(result.text, "(copied -> " target ")")
        case "replace":
            PasteText(result.text)
            Tr_ShowPopup(result.text, "(replaced -> " target ")")
        default:
            Tr_ShowPopup(result.text, "(-> " target ")")
    }
}

DeepL_Translate(text, sourceLang, targetLang) {
    key := CfgS("Translator_DeepLKey")
    if (key = "")
        return {ok: false, text: "DeepL API key not set (Settings -> Translator -> DeepL API key)"}

    endpoint := InStr(key, ":fx")
        ? "https://api-free.deepl.com/v2/translate"
        : "https://api.deepl.com/v2/translate"

    body := "text=" UriEncode(text) "&target_lang=" targetLang
    if (sourceLang != "" && sourceLang != "auto")
        body .= "&source_lang=" sourceLang

    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.Open("POST", endpoint, false)
        req.SetRequestHeader("Authorization", "DeepL-Auth-Key " key)
        req.SetRequestHeader("Content-Type", "application/x-www-form-urlencoded; charset=utf-8")
        req.SetRequestHeader("User-Agent", "MultiTool/1.0")
        req.Send(body)
        switch req.Status {
            case 200:    return {ok: true,  text: ParseDeepL(ReadUtf8Body(req))}
            case 403:    return {ok: false, text: "DeepL: invalid API key"}
            case 429:    return {ok: false, text: "DeepL: too many requests"}
            case 456:    return {ok: false, text: "DeepL: quota exceeded for this billing period"}
            default:     return {ok: false, text: "DeepL HTTP " req.Status}
        }
    } catch as e {
        return {ok: false, text: "DeepL failed: " e.Message}
    }
}

ParseDeepL(json) {
    ; Response: {"translations":[{"detected_source_language":"EN","text":"..."}]}
    p := InStr(json, '"translations":[')
    if (p && RegExMatch(json, '"text":"((?:\\.|[^"\\])*)"', &m, p))
        return Unescape(m[1])
    return "(no translation)"
}

; Google's unofficial translate endpoint. Free, no key, lower quality
; than DeepL on long passages but fine for short selections. Accepts
; the same DeepL-style language codes as DeepL_Translate -- they get
; downcased + truncated to two letters for Google's API.
Google_Translate(text, sourceLang, targetLang) {
    sl := GoogleLang(sourceLang)
    tl := GoogleLang(targetLang)
    url := "https://translate.googleapis.com/translate_a/single"
         . "?client=gtx&sl=" sl "&tl=" tl "&dt=t&q=" UriEncode(text)
    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.Open("GET", url, false)
        req.SetRequestHeader("User-Agent", "Mozilla/5.0")
        req.Send()
        if (req.Status != 200)
            return {ok: false, text: "Google HTTP " req.Status}
        return {ok: true, text: ParseGoogle(ReadUtf8Body(req))}
    } catch as e {
        return {ok: false, text: "Google failed: " e.Message}
    }
}

ParseGoogle(json) {
    ; Response: [[["translated","source",null,null,...], ...], ...]
    ; Each translated segment is the first element of an inner array.
    block := json
    if (p := InStr(block, "]],"))
        block := SubStr(block, 1, p)
    out := "", pos := 1
    pat := '\["((?:\\.|[^"\\])*)","(?:\\.|[^"\\])*"'
    while (foundAt := RegExMatch(block, pat, &m, pos)) {
        out .= m[1]
        pos := foundAt + m.Len(0)
    }
    return out = "" ? "(no translation)" : Unescape(out)
}

; Map a DeepL-style code (auto, EN-US, RU) to Google's 2-letter code.
GoogleLang(lang) {
    if (lang = "" || lang = "auto")
        return "auto"
    parts := StrSplit(lang, "-")
    return StrLower(parts[1])
}

; Read a WinHttp response body as UTF-8 text. Used by the translator and
; the typo fixer because both APIs return UTF-8 without a charset header,
; which would otherwise be decoded as Latin-1 by ResponseText.
ReadUtf8Body(req) {
    s := ComObject("ADODB.Stream")
    s.Type := 1                  ; binary
    s.Open()
    s.Write(req.ResponseBody)
    s.Position := 0
    s.Type := 2                  ; text
    s.Charset := "utf-8"
    out := s.ReadText()
    s.Close()
    return out
}

Unescape(s) {
    while RegExMatch(s, "i)\\u([0-9a-f]{4})", &m)
        s := StrReplace(s, m[0], Chr("0x" m[1]))
    s := StrReplace(s, "\n", "`n")
    s := StrReplace(s, "\r", "`r")
    s := StrReplace(s, "\t", "`t")
    s := StrReplace(s, '\"', '"')
    s := StrReplace(s, "\/", "/")
    s := StrReplace(s, "\\", "\")
    return s
}

UriEncode(str) {
    static safe := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~"
    buf := Buffer(StrPut(str, "UTF-8"))
    StrPut(str, buf, "UTF-8")
    out := ""
    loop buf.Size - 1 {
        c  := NumGet(buf, A_Index - 1, "UChar")
        ch := Chr(c)
        out .= InStr(safe, ch, true) ? ch : Format("%{:02X}", c)
    }
    return out
}

Tr_ShowPopup(textContent, tag := "") {
    global Popup
    Tr_ClosePopup()

    t := Theme_Palette(CfgS("General_Theme"))
    Popup := Gui("+AlwaysOnTop -Caption +ToolWindow +Owner")
    Popup.BackColor := t.popupBg
    Popup.MarginX := 14, Popup.MarginY := 11
    Popup.SetFont("s11 c" t.popupFg, "Segoe UI")
    Popup.AddText("w" CfgI("Translator_PopupWidth"), textContent)
    if (tag != "") {
        Popup.SetFont("s9 c" t.popupAccent, "Segoe UI")
        Popup.AddText("xm", tag)
    }

    if CaretGetPos(&cx, &cy)
        x := cx, y := cy + 24
    else {
        MouseGetPos(&mx, &my)
        x := mx + 8, y := my + 22
    }
    Popup.Show("x" x " y" y " AutoSize NoActivate")
    WinSetTransparent(CfgI("Translator_PopupAlpha"), "ahk_id " Popup.Hwnd)

    t := CfgI("Translator_PopupTimeout")
    if (t > 0)
        SetTimer(Tr_ClosePopup, -t)
}

Tr_ClosePopup(*) {
    global Popup
    if IsObject(Popup) {
        try Popup.Destroy()
        Popup := ""
    }
}


; ==================================================================
; ===  2. LAYOUT FIXER  ============================================
; ==================================================================
FixLayout(replace) {
    global gFwd, gRev
    text := GetSelectedText()
    if (text = "") {
        Lf_ShowPopup("- no text selected -")
        return
    }
    useMap := RegExMatch(text, "[\x{0400}-\x{04FF}]") ? gRev : gFwd
    out := ""
    Loop Parse, text
        out .= useMap.Has(A_LoopField) ? useMap[A_LoopField] : A_LoopField

    if (replace) {
        PasteText(out)
        return
    }
    A_Clipboard := out
    Lf_ShowPopup(out, "  (copied)")
}

GetSelectedText() {
    Send("{LWin up}{RWin up}")
    saved := ClipboardAll()
    A_Clipboard := ""
    Send("^c")
    ok := ClipWait(1)
    text := ok ? A_Clipboard : ""
    A_Clipboard := saved
    return Trim(text, " `t`r`n")
}

PasteText(str) {
    Send("{LWin up}{RWin up}")
    saved := ClipboardAll()
    A_Clipboard := str
    if !ClipWait(1) {
        A_Clipboard := saved
        return
    }
    Send("^v")
    Sleep(120)
    A_Clipboard := saved
}

Lf_ShowPopup(msg, tag := "") {
    global popupGui, popupGen

    CoordMode("Caret", "Screen")
    CoordMode("Mouse", "Screen")

    fs := CfgI("LayoutFix_FontSize")
    mw := CfgI("LayoutFix_MaxWidth")
    t  := Theme_Palette(CfgS("General_Theme"))
    bg := t.popupBg, fg := t.popupFg

    if popupGui {
        try popupGui.Destroy()
        popupGui := 0
    }
    popupGen += 1
    gen := popupGen

    g := Gui("-Caption +AlwaysOnTop +ToolWindow +Owner")
    g.BackColor := bg
    g.MarginX := 12, g.MarginY := 9
    g.SetFont("s" fs " c" fg, "Segoe UI")
    g.SetFont("s" fs, "Consolas")
    g.AddEdit("ReadOnly -E0x200 Background" bg " c" fg " w" mw, msg)
    if (tag != "") {
        g.SetFont("s" (fs - 2) " c" t.popupAccent, "Segoe UI")
        g.AddText("xm", tag)
    }

    if CaretGetPos(&cx, &cy)
        ax := cx, ay := cy, lineH := 22
    else {
        MouseGetPos(&mx, &my)
        ax := mx, ay := my, lineH := 18
    }

    g.Show("AutoSize Hide NoActivate")
    g.GetPos(, , &gw, &gh)
    px := ax, py := ay + lineH
    if (py + gh > A_ScreenHeight - 6)
        py := ay - gh - 6
    if (px + gw > A_ScreenWidth - 6)
        px := A_ScreenWidth - gw - 6
    px := Max(px, 6), py := Max(py, 6)

    g.Show("x" px " y" py " NoActivate")
    WinSetTransparent(CfgI("LayoutFix_Opacity"), "ahk_id " g.Hwnd)

    popupGui := g
    dt := CfgI("LayoutFix_DisplayTime")
    if (dt > 0)
        SetTimer((*) => (popupGen = gen ? Lf_ClosePopup() : 0), -dt)
}

Lf_ClosePopup(*) {
    global popupGui
    if popupGui {
        try popupGui.Destroy()
        popupGui := 0
    }
}

BuildMaps() {
    global gFwd, gRev
    for k, v in gFwd.Clone() {
        if (StrLen(k) = 1 && k ~= "[a-z]") {
            uk := StrUpper(k), uv := StrUpper(v)
            if !gFwd.Has(uk)
                gFwd[uk] := uv
        }
    }
    gRev := Map()
    for k, v in gFwd
        if !gRev.Has(v)
            gRev[v] := k
}


; ==================================================================
; ===  3. TYPO FIXER  ==============================================
; ==================================================================
; Sends the selected text to LanguageTool's public API, applies the
; first replacement for each match, and pastes the corrected text
; back over the selection. Free, no API key, ~20 req/min per IP.
FixTypos() {
    text := GetSelectedText()
    if (text = "") {
        Lf_ShowPopup("- no text selected -")
        return
    }

    lang := CfgS("TypoFix_Lang")
    if (lang = "")
        lang := "auto"

    try {
        json := LT_Check(text, lang)
    } catch as e {
        Lf_ShowPopup("Typo fix failed: " e.Message)
        return
    }

    result := LT_Apply(text, json)
    if (result.count = 0 || result.text = text) {
        Lf_ShowPopup("- no typos found -")
        return
    }

    PasteText(result.text)
    Lf_ShowPopup(result.text, "  (" result.count " fix" (result.count = 1 ? "" : "es") ")")
}

LT_Check(text, lang) {
    body := "text=" UriEncode(text) "&language=" lang
    req := ComObject("WinHttp.WinHttpRequest.5.1")
    req.Open("POST", "https://api.languagetool.org/v2/check", false)
    req.SetRequestHeader("Content-Type", "application/x-www-form-urlencoded; charset=utf-8")
    req.SetRequestHeader("User-Agent", "MultiTool/1.0")
    req.SetRequestHeader("Accept", "application/json")
    req.Send(body)
    if (req.Status = 429)
        throw Error("rate-limited (try again in a minute)")
    if (req.Status != 200)
        throw Error("HTTP " req.Status)
    return ReadUtf8Body(req)
}

; Parses the LanguageTool JSON response and applies each match's first
; replacement to the original text. Offsets are in UTF-16 code units,
; which match AHK's string indexing.
LT_Apply(text, json) {
    matches := []
    pos := InStr(json, '"matches":[')
    if (!pos)
        return {text: text, count: 0}
    pos += StrLen('"matches":[')

    loop {
        repPos := RegExMatch(json, '"replacements":\[', &rm, pos)
        if !repPos
            break
        afterRep := repPos + rm.Len(0)

        replacement := ""
        if (SubStr(json, afterRep, 1) != "]") {
            valPos := RegExMatch(json, '\{"value":"((?:\\.|[^"\\])*)"', &vm, afterRep)
            if (valPos = afterRep)
                replacement := Unescape(vm[1])
        }

        omPos := RegExMatch(json, '"offset":(\d+),"length":(\d+)', &om, afterRep)
        if !omPos
            break

        if (replacement != "")
            matches.Push({offset: Integer(om[1]), length: Integer(om[2]), value: replacement})

        pos := omPos + om.Len(0)
    }

    n := matches.Length
    if (n > 1) {
        Loop n - 1 {
            i := A_Index
            Loop n - i {
                j := A_Index
                if (matches[j].offset < matches[j+1].offset) {
                    tmp := matches[j], matches[j] := matches[j+1], matches[j+1] := tmp
                }
            }
        }
    }

    out := text
    count := 0
    for m in matches {
        before := SubStr(out, 1, m.offset)
        after  := SubStr(out, m.offset + m.length + 1)
        out := before . m.value . after
        count++
    }
    return {text: out, count: count}
}


; ==================================================================
; ===  4. RAINBOW BORDER  ==========================================
; ==================================================================
BuildBorder() {
    global C, bBuilt, bActive, bGui, bMemDC, bHbm, bOldBmp, bPBits
    global bW, bH, bInvP, bThick, bSpeed, bInterval, bOffset, bPalette
    global bPtDst, bSzWin, bPtSrc, bBlend

    DestroyBorder()

    bThick    := CfgI("Rainbow_Thick")
    bSpeed    := CfgN("Rainbow_Speed")
    bInterval := CfgI("Rainbow_Interval")
    bOffset   := 0.0

    bW := A_ScreenWidth
    bH := A_ScreenHeight - CfgI("Rainbow_BottomGap")
    P  := 2 * bW + 2 * bH
    bInvP := 1.0 / P

    bPalette := []
    sat := CfgN("Rainbow_Sat"), val := CfgN("Rainbow_Val")
    Loop 360
        bPalette.Push(HsvToBGRA((A_Index - 1) / 360, sat, val))

    bGui := Gui("-Caption +AlwaysOnTop +ToolWindow +E0x08080020")  ; NOACTIVATE|LAYERED|TRANSPARENT
    bGui.Show("x0 y0 w" bW " h" bH " NoActivate")

    bi := Buffer(40, 0)
    NumPut("uint", 40, bi, 0)
    NumPut("int", bW,  bi, 4)
    NumPut("int", -bH, bi, 8)
    NumPut("ushort", 1, bi, 12)
    NumPut("ushort", 32, bi, 14)
    NumPut("uint", 0, bi, 16)

    ppvBits := 0
    sdc := DllCall("GetDC", "ptr", 0, "ptr")
    bHbm := DllCall("gdi32\CreateDIBSection", "ptr", sdc, "ptr", bi, "uint", 0
        , "ptr*", &ppvBits, "ptr", 0, "uint", 0, "ptr")
    DllCall("ReleaseDC", "ptr", 0, "ptr", sdc)
    bPBits := ppvBits

    bMemDC  := DllCall("gdi32\CreateCompatibleDC", "ptr", 0, "ptr")
    bOldBmp := DllCall("gdi32\SelectObject", "ptr", bMemDC, "ptr", bHbm, "ptr")

    bPtDst := Buffer(8, 0)
    bSzWin := Buffer(8, 0)
    NumPut("int", bW, bSzWin, 0), NumPut("int", bH, bSzWin, 4)
    bPtSrc := Buffer(8, 0)
    bBlend := Buffer(4, 0)
    NumPut("uchar", 0,   bBlend, 0)
    NumPut("uchar", 0,   bBlend, 1)
    NumPut("uchar", 255, bBlend, 2)
    NumPut("uchar", 1,   bBlend, 3)

    bBuilt := true

    if (C["Rainbow_Enabled"] = "1") {
        bActive := true
        SetTimer(Draw, bInterval)
    } else {
        bActive := false
        bGui.Hide()
    }
}

DestroyBorder() {
    global bBuilt, bActive, bGui, bMemDC, bHbm, bOldBmp
    if !bBuilt
        return
    SetTimer(Draw, 0)
    try DllCall("gdi32\SelectObject", "ptr", bMemDC, "ptr", bOldBmp)
    try DllCall("gdi32\DeleteObject", "ptr", bHbm)
    try DllCall("gdi32\DeleteDC", "ptr", bMemDC)
    try bGui.Destroy()
    bGui := "", bMemDC := 0, bHbm := 0, bOldBmp := 0
    bBuilt := false, bActive := false
}

Draw() {
    global bOffset, bSpeed, bW, bH, bThick, bInvP, bPalette, bPBits
    global bGui, bMemDC, bPtDst, bSzWin, bPtSrc, bBlend

    bOffset += bSpeed
    if (bOffset >= 1.0)
        bOffset -= 1.0
    off := bOffset, W := bW, H := bH, T := bThick, invP := bInvP

    x := 0
    while (x < W) {
        hT := x * invP + off
        if (hT >= 1.0)
            hT -= 1.0
        vT := bPalette[Integer(hT * 360) + 1]

        hB := (W + H + (W - x)) * invP + off
        if (hB >= 1.0)
            hB -= 1.0
        vB := bPalette[Integer(hB * 360) + 1]

        row := 0
        while (row < T) {
            NumPut("uint", vT, bPBits + (row * W + x) * 4)
            NumPut("uint", vB, bPBits + ((H - 1 - row) * W + x) * 4)
            row++
        }
        x++
    }

    y := 0
    while (y < H) {
        hR := (W + y) * invP + off
        if (hR >= 1.0)
            hR -= 1.0
        vR := bPalette[Integer(hR * 360) + 1]

        hL := (2 * W + H + (H - y)) * invP + off
        if (hL >= 1.0)
            hL -= 1.0
        vL := bPalette[Integer(hL * 360) + 1]

        base := y * W
        col := 0
        while (col < T) {
            NumPut("uint", vR, bPBits + (base + (W - 1 - col)) * 4)
            NumPut("uint", vL, bPBits + (base + col) * 4)
            col++
        }
        y++
    }

    DllCall("user32\UpdateLayeredWindow", "ptr", bGui.Hwnd, "ptr", 0, "ptr", bPtDst
        , "ptr", bSzWin, "ptr", bMemDC, "ptr", bPtSrc, "uint", 0, "ptr", bBlend, "uint", 2)
}

ToggleBorder() {
    global bBuilt, bActive, bGui, bInterval
    if !bBuilt
        BuildBorder()
    bActive := !bActive
    if (bActive) {
        bGui.Show("NoActivate")
        SetTimer(Draw, bInterval)
    } else {
        SetTimer(Draw, 0)
        bGui.Hide()
    }
}

; h,s,v in 0..1  ->  premultiplied BGRA DWORD (0xAARRGGBB, A=255)
HsvToBGRA(h, s, v) {
    i := Integer(h * 6)
    f := h * 6 - i
    p := v * (1 - s)
    q := v * (1 - f * s)
    t := v * (1 - (1 - f) * s)
    switch Mod(i, 6) {
        case 0: r := v, g := t, b := p
        case 1: r := q, g := v, b := p
        case 2: r := p, g := v, b := t
        case 3: r := p, g := q, b := v
        case 4: r := t, g := p, b := v
        default: r := v, g := p, b := q
    }
    R := Round(r * 255), G := Round(g * 255), B := Round(b * 255)
    return 0xFF000000 | (R << 16) | (G << 8) | B
}


; ==================================================================
; ===  5. GIT AUTO-PUSH  ===========================================
; ==================================================================
DoPush() {
    path    := CfgS("Push_Path")
    msg     := CfgS("Push_Msg")
    branch  := CfgS("Push_Branch")
    shell   := CfgS("Push_Shell")
    repoUrl := Trim(CfgS("Push_RepoUrl"))

    if (path = "" || !DirExist(path)) {
        MsgBox("Project folder is not set or doesn't exist:`n" path "`n`nSettings -> For Devs -> Project folder.",
            "MultiTool", "Icon!")
        return
    }
    if (branch = "") {
        MsgBox("Branch is not set.`n`nSettings -> For Devs -> Branch.", "MultiTool", "Icon!")
        return
    }

    ; Where is this push actually going? If RepoUrl override is empty,
    ; fall back to whatever `origin` points to in the folder.
    effectiveUrl := (repoUrl != "") ? repoUrl : GetOriginUrl(path)
    sourceLabel  := (repoUrl != "") ? "explicit URL" : "folder's origin"
    if (effectiveUrl = "") {
        effectiveUrl := "<no origin remote configured in this folder>"
        sourceLabel  := "??"
    }

    preview := "About to commit + push:`n`n"
        . "Folder:   " path "`n"
        . "Branch:   " branch "`n"
        . "Repo:     " effectiveUrl "`n"
        . "Source:   " sourceLabel "`n"
        . "Message:  " msg "`n`n"
        . "Continue?"
    r := MsgBox(preview, "MultiTool: confirm push", "OKCancel Iconi")
    if (r != "OK")
        return

    pushTarget := (repoUrl != "") ? repoUrl : "origin"

    if (shell = "powershell") {
        ps := "cd '" path "'; git add .; git commit -m '" msg "'; if ($?) { git push '" pushTarget "' " branch " }"
        cmd := 'powershell.exe -NoExit -Command "' ps '"'
    } else {
        cmd := 'cmd.exe /k "cd /d "' path '"'
             . ' && git add .'
             . ' && git commit -m "' msg '"'
             . ' && git push "' pushTarget '" ' branch '"'
    }
    Run(cmd)
}

; Reads the `origin` remote URL of a git repo at `folder`. Returns ""
; if the folder isn't a git repo, has no `origin`, or git isn't on PATH.
GetOriginUrl(folder) {
    if (folder = "" || !DirExist(folder))
        return ""
    tmp := A_Temp "\multitool_origin.txt"
    try FileDelete(tmp)
    try {
        ; Outer quotes wrap the whole cmd /c argument; cmd /S strips them
        ; so the inner quotes around path/tmp survive into git's argv.
        RunWait(A_ComSpec ' /c "git -C "' folder '" remote get-url origin > "' tmp '" 2>nul"', , "Hide")
        if !FileExist(tmp)
            return ""
        out := FileRead(tmp)
        try FileDelete(tmp)
        return Trim(out, " `t`r`n")
    } catch {
        try FileDelete(tmp)
        return ""
    }
}

; Entry point for the "Create a release" button. Resolves the GitHub repo the
; same way a push does (explicit Repo URL, else the folder's origin), makes
; sure we can authenticate, then opens the release dialog. With no auth set up
; it offers the browser release page as a fallback.
DoRelease() {
    repoUrl := Trim(CfgS("Push_RepoUrl"))
    path    := CfgS("Push_Path")
    effective := (repoUrl != "") ? repoUrl : GetOriginUrl(path)

    if (effective = "") {
        MsgBox("No repository to release.`n`nSet a Repo URL on the For Devs tab, "
            "or pick a project folder that has a GitHub 'origin' remote.",
            "MultiTool", "Icon!")
        return
    }
    repo := ParseGitHubRepo(effective)
    if (repo = "") {
        MsgBox("This doesn't look like a GitHub repository:`n`n" effective "`n`n"
            "Releases can only be created on github.com.", "MultiTool", "Icon!")
        return
    }

    if (!Gh_Available() && Trim(CfgS("Push_Token")) = "") {
        r := MsgBox("Publishing a release needs GitHub authentication.`n`n"
            "Install GitHub CLI and run `"gh auth login`", or add a GitHub token "
            "in Settings -> For Devs.`n`nOpen the release page in your browser instead?",
            "Create a release", "YesNo Icon!")
        if (r = "Yes")
            Run(ReleasesNewUrl(effective))
        return
    }

    ShowReleaseDialog(repo, Trim(CfgS("Push_Branch")))
}

; The release form: tag, title, description, file attachments, and the draft /
; pre-release flags. On OK it publishes via PublishRelease and reports back
; with a modal success or failure message.
ShowReleaseDialog(repo, target) {
    t := Theme_Palette(CfgS("General_Theme"))
    files := []
    pending := ""        ; the opts object handed from OnOk to Publish

    d := Gui("+OwnDialogs -Resize -MaximizeBox", "Create a release")
    d.BackColor := t.bg
    d.SetFont("s10 c" t.fg, "Segoe UI")

    d.AddText("x14 y12 w456", "Repository:   " repo)
    d.AddText("x14 y34 w456", "Target branch:   " (target = "" ? "(repo default)" : target))

    d.AddText("x14 y70 w90", "Tag")
    tagEd := d.AddEdit("x110 y66 w180 Background" t.editBg)
    d.SetFont("s9 c" t.hintFg, "Segoe UI")
    d.AddText("x298 y70 w172", "required, e.g. v1.2.0")
    d.SetFont("s10 c" t.fg, "Segoe UI")

    d.AddText("x14 y104 w90", "Title")
    titleEd := d.AddEdit("x110 y100 w360 Background" t.editBg)
    d.SetFont("s9 c" t.hintFg, "Segoe UI")
    d.AddText("x110 y124 w360", "optional -- defaults to the tag")
    d.SetFont("s10 c" t.fg, "Segoe UI")

    d.AddText("x14 y150 w90", "Description")
    descEd := d.AddEdit("x110 y150 w360 r6 +Multi +WantReturn Background" t.editBg)

    d.AddText("x14 y272 w90", "Files")
    filesLb := d.AddListBox("x110 y272 w360 h78 Background" t.editBg)
    d.AddButton("x110 y354 w114 h26", "Add files...").OnEvent("Click", AddFiles)
    d.AddButton("x232 y354 w114 h26", "Remove").OnEvent("Click", RemoveFile)

    draftCb := d.AddCheckbox("x110 y390 w90", "Draft")
    preCb   := d.AddCheckbox("x210 y390 w140", "Pre-release")

    statusTx := d.AddText("x14 y424 w330 c" t.hintFg, "")
    okBtn := d.AddButton("x352 y420 w56 h28 +Default", "OK")
    d.AddButton("x412 y420 w56 h28", "Cancel").OnEvent("Click", (*) => d.Destroy())

    okBtn.OnEvent("Click", OnOk)
    d.OnEvent("Close", (*) => d.Destroy())
    d.OnEvent("Escape", (*) => d.Destroy())
    d.Show("w484 h462")

    AddFiles(*) {
        sel := FileSelect("M3", , "Choose files to attach to the release")
        if (sel = "")                          ; cancelled
            return
        picks := IsObject(sel) ? sel : [sel]   ; v2 multi-select returns an array of full paths
        for f in picks {
            dup := false
            for existing in files
                if (existing = f)
                    dup := true
            if !dup {
                files.Push(f)
                SplitPath(f, &fn)
                filesLb.Add([fn])
            }
        }
    }
    RemoveFile(*) {
        i := filesLb.Value
        if (i > 0) {
            files.RemoveAt(i)
            filesLb.Delete(i)
        }
    }
    OnOk(*) {
        tag := Trim(tagEd.Value)
        if (tag = "") {
            MsgBox("A tag is required (for example v1.2.0).", "Create a release", "Icon!")
            return
        }
        pending := {tag: tag, title: Trim(titleEd.Value), body: descEd.Value,
                    files: files, draft: draftCb.Value ? true : false,
                    prerelease: preCb.Value ? true : false, target: target}
        okBtn.Enabled := false
        statusTx.Text := "Publishing release..."
        SetTimer(Publish, -50)   ; defer so the status text paints before we block
    }

    Publish() {
        res := PublishRelease(repo, pending)
        if (res.ok) {
            d.Destroy()
            msg := "Released successfully."
            if (res.url != "")
                msg .= "`n`n" res.url
            MsgBox(msg, "MultiTool", "Iconi")
        } else {
            okBtn.Enabled := true
            statusTx.Text := ""
            MsgBox("Release failed:`n`n" res.error, "Create a release", "Icon!")
        }
    }
}

; Pick an auth method (gh if it's logged in, else the saved token) and publish.
PublishRelease(repo, opts) {
    if Gh_Available()
        return Gh_CreateRelease(repo, opts)
    token := Trim(CfgS("Push_Token"))
    if (token != "")
        return Api_CreateRelease(repo, token, opts)
    return {ok: false, url: "", error: "No GitHub authentication available "
        "(GitHub CLI is not logged in and no token is set)."}
}

; True if the GitHub CLI is installed AND authenticated for github.com.
Gh_Available() {
    try return RunWait(A_ComSpec ' /c "gh auth status >nul 2>&1"', , "Hide") = 0
    catch
        return false
}

; Publish via `gh release create`: gh creates the tag on --target, uploads the
; files and prints the release URL. Returns {ok, url, error}.
Gh_CreateRelease(repo, opts) {
    notes := A_Temp "\multitool_notes.txt"
    outF  := A_Temp "\multitool_ghrel_out.txt"
    errF  := A_Temp "\multitool_ghrel_err.txt"
    try FileDelete(notes)
    FileAppend(opts.body, notes, "UTF-8-RAW")

    title := (opts.title != "") ? opts.title : opts.tag
    cmd := 'gh release create "' opts.tag '"'
    for f in opts.files
        cmd .= ' "' f '"'
    cmd .= ' --repo "' repo '" --title "' title '" --notes-file "' notes '"'
    if (opts.target != "")
        cmd .= ' --target "' opts.target '"'
    if opts.draft
        cmd .= ' --draft'
    if opts.prerelease
        cmd .= ' --prerelease'

    workDir := DirExist(CfgS("Push_Path")) ? CfgS("Push_Path") : A_ScriptDir
    try FileDelete(outF)
    try FileDelete(errF)
    code := RunWait(A_ComSpec ' /c "' cmd ' > "' outF '" 2> "' errF '""', workDir, "Hide")

    out := FileExist(outF) ? FileRead(outF) : ""
    err := FileExist(errF) ? FileRead(errF) : ""
    try FileDelete(notes)
    try FileDelete(outF)
    try FileDelete(errF)

    if (code = 0) {
        url := RegExMatch(out "`n" err, "i)https://github\.com/\S+/releases/tag/\S+", &m)
            ? Trim(m[0], "`r`n `t") : ""
        return {ok: true, url: url, error: ""}
    }
    msg := Trim((err != "") ? err : out, "`r`n `t")
    return {ok: false, url: "", error: (msg != "") ? msg : "gh exited with code " code}
}

; Publish via the GitHub REST API with a token: create the release, then upload
; each file as a release asset. Returns {ok, url, error}.
Api_CreateRelease(repo, token, opts) {
    parts := StrSplit(repo, "/")
    owner := parts[1], name := parts[2]
    title := (opts.title != "") ? opts.title : opts.tag

    body := '{"tag_name":"' JsonEsc(opts.tag) '"'
    if (opts.target != "")
        body .= ',"target_commitish":"' JsonEsc(opts.target) '"'
    body .= ',"name":"' JsonEsc(title) '"'
    body .= ',"body":"' JsonEsc(opts.body) '"'
    body .= ',"draft":' (opts.draft ? "true" : "false")
    body .= ',"prerelease":' (opts.prerelease ? "true" : "false") '}'

    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.Open("POST", "https://api.github.com/repos/" owner "/" name "/releases", false)
        Api_Headers(req, token)
        req.SetRequestHeader("Content-Type", "application/json; charset=utf-8")
        req.Send(body)
    } catch as e {
        return {ok: false, url: "", error: "Network error: " e.Message}
    }
    if (req.Status != 201)
        return {ok: false, url: "", error: Api_ErrMsg(req)}

    json := ReadUtf8Body(req)
    id  := RegExMatch(json, '"id":\s*(\d+)', &m) ? m[1] : ""
    url := RegExMatch(json, '"html_url":\s*"([^"]+/releases/tag/[^"]+)"', &m) ? m[1] : ""

    failed := ""
    for f in opts.files {
        ur := Api_UploadAsset(owner, name, token, id, f)
        if !ur.ok
            failed .= "`n  " f " -- " ur.error
    }
    if (failed != "")
        return {ok: false, url: url, error: "Release created, but some files "
            "could not be uploaded:" failed}
    return {ok: true, url: url, error: ""}
}

; Upload one file as an asset of release `id`.
Api_UploadAsset(owner, name, token, id, file) {
    if (id = "")
        return {ok: false, error: "no release id"}
    if !FileExist(file)
        return {ok: false, error: "file not found"}
    SplitPath(file, &fn)
    url := "https://uploads.github.com/repos/" owner "/" name "/releases/" id
        . "/assets?name=" UriEncode(fn)
    try {
        stream := ComObject("ADODB.Stream")
        stream.Type := 1                 ; binary
        stream.Open()
        stream.LoadFromFile(file)
        stream.Position := 0
        data := stream.Read()
        stream.Close()

        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.Open("POST", url, false)
        Api_Headers(req, token)
        req.SetRequestHeader("Content-Type", "application/octet-stream")
        req.Send(data)
    } catch as e {
        return {ok: false, error: e.Message}
    }
    return (req.Status = 201) ? {ok: true, error: ""} : {ok: false, error: Api_ErrMsg(req)}
}

Api_Headers(req, token) {
    req.SetRequestHeader("Authorization", "Bearer " token)
    req.SetRequestHeader("Accept", "application/vnd.github+json")
    req.SetRequestHeader("X-GitHub-Api-Version", "2022-11-28")
    req.SetRequestHeader("User-Agent", "MultiTool")
}

; Build a readable error string from a failed GitHub API response.
Api_ErrMsg(req) {
    body := ""
    try body := ReadUtf8Body(req)
    msg := RegExMatch(body, '"message":\s*"((?:\\.|[^"\\])*)"', &m) ? Unescape(m[1]) : ""
    return "GitHub API " req.Status (msg != "" ? " -- " msg : "")
}

; JSON-string-escape for the REST request body. Backslash first, then quotes,
; then the whitespace controls.
JsonEsc(s) {
    s := StrReplace(s, "\", "\\")
    s := StrReplace(s, '"', '\"')
    s := StrReplace(s, "`r`n", "\n")
    s := StrReplace(s, "`r", "\n")
    s := StrReplace(s, "`n", "\n")
    s := StrReplace(s, "`t", "\t")
    return s
}

; "owner/repo" from a git remote (https or SSH, optional creds / .git), or ""
; if it isn't a recognizable github.com repository.
ParseGitHubRepo(remote) {
    remote := Trim(remote)
    if RegExMatch(remote, "i)^git@github\.com:(.+)$", &m)
        repoPath := m[1]
    else if RegExMatch(remote, "i)^ssh://git@github\.com/(.+)$", &m)
        repoPath := m[1]
    else if RegExMatch(remote, "i)^https?://(?:[^/@]+@)?github\.com/(.+)$", &m)
        repoPath := m[1]
    else
        return ""
    repoPath := RegExReplace(repoPath, "i)\.git$", "")
    repoPath := RegExReplace(repoPath, "/+$", "")
    return RegExMatch(repoPath, "^[^/]+/[^/]+$") ? repoPath : ""
}

; The repo's https://github.com/<owner>/<repo>/releases/new page (browser
; fallback), or "" if `remote` isn't a recognizable GitHub remote.
ReleasesNewUrl(remote) {
    repo := ParseGitHubRepo(remote)
    return (repo = "") ? "" : "https://github.com/" repo "/releases/new"
}


; ==================================================================
; ===  6. PIN-ON-TOP  ==============================================
; ==================================================================
PinWindow() {
    global PinnedWindows
    hwnd := WinExist("A")
    if !hwnd
        return
    WinSetAlwaysOnTop(1, "ahk_id " hwnd)
    WinSetTransparent(CfgI("Pin_Alpha"), "ahk_id " hwnd)
    WinSetExStyle("+0x20", "ahk_id " hwnd)        ; WS_EX_TRANSPARENT -> click-through
    PinnedWindows[hwnd] := true
}

UnpinAll() {
    global PinnedWindows
    for hwnd in PinnedWindows {
        if WinExist("ahk_id " hwnd) {
            WinSetExStyle("-0x20", "ahk_id " hwnd)
            WinSetTransparent("Off", "ahk_id " hwnd)
            WinSetAlwaysOnTop(0, "ahk_id " hwnd)
        }
    }
    PinnedWindows := Map()
}


; ==================================================================
; ===  7. KEYSTROKE SENTINEL  ======================================
; ==================================================================
; Thin wrapper around sentinel.py (sitting beside this script): a
; behavioral-biometric locker that learns your typing rhythm and locks
; the workstation when the rhythm stops matching. MultiTool never sees
; keystrokes -- the Python helper only emits timing aggregates. While
; enabled we keep `sentinel.py monitor` running as a hidden background
; process and tear it down when disabled or on exit.
;
; State lives in SentinelPID (0 = not running). The trained profile and
; the script are both expected next to this script/exe.
; (SentinelPID is initialized in the GLOBAL STATE block at the top.)

SentinelScript() {
    return A_ScriptDir "\sentinel.py"
}
SentinelProfile() {
    ; Matches MODEL_PATH in sentinel.py (skops profile saved beside the script).
    return A_ScriptDir "\sentinel_profile.skops"
}
Sec_Python() {
    p := Trim(CfgS("Security_PythonPath"))
    return (p = "") ? "python" : p
}
Sec_StatusLine() {
    if !FileExist(SentinelScript())
        return "sentinel.py not found beside MultiTool."
    return FileExist(SentinelProfile())
        ? "Typing profile: trained and ready."
        : "Typing profile: none yet -- enroll first."
}
Sec_IsRunning() {
    global SentinelPID
    return SentinelPID && ProcessExist(SentinelPID)
}

; Reconcile the running monitor with the Enabled setting. interactive is
; false at startup so a missing profile/python doesn't pop dialogs at boot.
Sec_Apply(interactive := true) {
    if (CfgS("Security_Enabled") = "1")
        Sec_Start(interactive)
    else
        Sec_Stop()
}

Sec_Start(interactive := true) {
    global SentinelPID
    if Sec_IsRunning()
        return
    script := SentinelScript()
    if !FileExist(script) {
        if interactive
            MsgBox("sentinel.py was not found next to MultiTool:`n`n" script
                "`n`nKeep sentinel.py in the same folder as this app.",
                "MultiTool", "Icon!")
        return
    }
    if !FileExist(SentinelProfile()) {
        if interactive {
            r := MsgBox("The keystroke sentinel must learn your typing rhythm before "
                "it can run.`n`nEnroll a profile now? (Type normally for a few "
                "minutes in the console that opens.)", "MultiTool", "YesNo Iconi")
            if (r = "Yes")
                Sec_Enroll()
        } else {
            TrayTip("Sentinel is enabled but has no profile yet -- open "
                "Settings -> Security to enroll.", "MultiTool")
        }
        return
    }
    try {
        Run(Format('"{1}" "{2}" monitor', Sec_Python(), script), A_ScriptDir, "Hide", &pid)
        SentinelPID := pid
        if interactive
            TrayTip("Keystroke sentinel is watching your typing rhythm.", "MultiTool")
    } catch as e {
        SentinelPID := 0
        if interactive
            MsgBox("Couldn't start the keystroke sentinel:`n`n" e.Message
                "`n`nCheck the Python executable in Settings -> Security, and that "
                "scikit-learn, numpy and pynput are installed.", "MultiTool", "Icon!")
    }
}

Sec_Stop() {
    global SentinelPID
    if (SentinelPID && ProcessExist(SentinelPID))
        ; /T also kills children (e.g. when launched through the py launcher).
        try RunWait("taskkill /PID " SentinelPID " /T /F", , "Hide")
    SentinelPID := 0
}

; Flip the Enabled flag (used by the toggle hotkey), persist just that key
; so a later Apply/restart agrees, then reconcile the running process.
Sec_Toggle() {
    global C, INI
    newVal := (CfgS("Security_Enabled") = "1") ? "0" : "1"
    C["Security_Enabled"] := newVal
    IniWrite(newVal, INI, "Security", "Enabled")
    if (newVal = "1") {
        Sec_Apply(true)
    } else {
        Sec_Stop()
        TrayTip("Keystroke sentinel stopped.", "MultiTool")
    }
}

; Launch enrollment in a VISIBLE console so the user can watch the progress
; bar while typing. sentinel.py writes the profile and exits on its own.
Sec_Enroll() {
    script := SentinelScript()
    if !FileExist(script) {
        MsgBox("sentinel.py was not found next to MultiTool:`n`n" script,
            "MultiTool", "Icon!")
        return
    }
    try Run(Format('"{1}" "{2}" enroll', Sec_Python(), script), A_ScriptDir)
    catch as e
        MsgBox("Couldn't start enrollment:`n`n" e.Message
            "`n`nCheck the Python executable in Settings -> Security.",
            "MultiTool", "Icon!")
}


; ==================================================================
; ===  EXIT  =======================================================
; ==================================================================
OnExitHandler(*) {
    UnpinAll()
    DestroyBorder()
    Sec_Stop()
}
