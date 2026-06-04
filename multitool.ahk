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
APP_VERSION := "1.4.2"
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
    {sec:"Rainbow",    key:"Glow",         label:"Glow (soft inner halo)",  type:"bool",  def:"0"},
    {sec:"Rainbow",    key:"GlowSize",     label:"Glow reach inward (px)",  type:"int",   def:"12"},
    {sec:"Rainbow",    key:"GlowStrength", label:"Glow strength (0-1)",     type:"float", def:"0.6"},

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
    {sec:"Hello",      key:"Settings",    label:"Opening MultiTool Settings", type:"bool", def:"0"},
    {sec:"Hello",      key:"SentinelOff", label:"Turning the sentinel off",   type:"bool", def:"0"},
    {sec:"Hello",      key:"Release",     label:"Publishing a release / using the GitHub token", type:"bool", def:"0"},
    {sec:"Hello",      key:"Quit",        label:"Quitting MultiTool",         type:"bool", def:"0"},
    {sec:"Hello",      key:"WinSettings", label:"Opening Windows Settings",   type:"bool", def:"1"},
    {sec:"Access",     key:"AntiKill",     label:"Resist being killed / deleted / tampered (non-admin) + watchdog & self-heal", type:"bool", def:"0"},
    {sec:"Access",     key:"PossessMode",  label:"Lock when away", type:"choice", def:"Off",
        choices:["Off","USB","Bluetooth","Both"]},
    {sec:"Access",     key:"PossessUsb",   label:"USB key id",        type:"string", def:""},
    {sec:"Access",     key:"PossessBt",    label:"Bluetooth device",  type:"string", def:""},
    {sec:"Access",     key:"PossessGrace", label:"Lock after absent (s)", type:"int", def:"15"},

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
    {sec:"General",    key:"RunOnStartup",   label:"Run on Windows startup", type:"bool", def:"0"},
    {sec:"General",    key:"ClipClearSec",   label:"Clear clipboard after (s, 0=off)", type:"int", def:"60"},
    {sec:"General",    key:"AuditLog",       label:"Log security events", type:"bool", def:"1"}
]

; Section -> friendly caption, used for the nested sub-tabs.
TabNames := Map("Translator","Translator", "LayoutFix","Layout Fix", "TypoFix","Typo Fix",
                "Rainbow","Rainbow", "Pin","Pin", "Security","Sentinel",
                "Hello","Hello", "Access","Lock away")

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
    {name:"Security", subs:["Security","Hello","Access"]},
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
g_ClipGuard := ""       ; last text we auto-copied; cleared on timeout if unchanged

; rainbow-border module state (b* prefix)
bBuilt := false, bActive := false
bGui := "", bMemDC := 0, bHbm := 0, bOldBmp := 0, bPBits := 0
bW := 0, bH := 0, bInvP := 0.0, bThick := 2, bSpeed := 0.025
bInterval := 33, bOffset := 0.0, bPalette := []
bGlowG := 0, bRing := 2, bStripL := "", bStripR := ""   ; soft halo: depth, total ring, per-hue inward strips
bPtDst := "", bSzWin := "", bPtSrc := "", bBlend := ""

; keystroke-sentinel module state -- must be assigned before Sec_Apply runs
; in STARTUP below, so we keep it up here rather than next to the helpers.
SentinelPID := 0

; WinGuard + process-protection state -- assigned here (before STARTUP) so the
; timers and *_Apply calls below never read them before they exist.
WinGuardOkHwnd := 0
WinGuardBusy := false
WinGuardHelloOk := -1
WinGuardSuppressUntil := 0
WatchdogPID := 0
FilesProtected := false   ; whether the deny-delete ACLs are currently applied


; ==================================================================
; ===  STARTUP  ====================================================
; ==================================================================
Heal_PreRestore()   ; if the INI was wiped while protected, restore it before reading
LoadConfig()
BuildMaps()
BuildBorder()
RegisterHotkeys()
SetupTray()
OnExit(OnExitHandler)
Sec_Apply(false)   ; resume the keystroke sentinel if it was left enabled
Possess_Apply()    ; arm the possession-factor poll if configured
WinGuard_Apply()   ; arm the Windows-Settings Hello guard if enabled
Protect_Apply()    ; deny-terminate/delete + watchdog + self-heal if "Resist being killed" is on
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
    MigrateHelloGate()
    for item in Schema {
        k := item.sec "_" item.key
        v := IniRead(INI, item.sec, item.key, item.def)
        ; Secrets are stored encrypted ("dpapi:<base64>"); decrypt into the live
        ; config so the rest of the app sees plain text transparently. A blob we
        ; can't decrypt (copied from another user/PC) collapses to "".
        if (IsSecretKey(k) && SubStr(v, 1, 6) = "dpapi:")
            v := Dpapi_Unprotect(SubStr(v, 7))
        C[k] := v
    }
}

; Settings whose values are sensitive and must never sit in the INI as plain
; text. They are DPAPI-encrypted on save and decrypted on load.
IsSecretKey(k) {
    return (k = "Push_Token" || k = "Translator_DeepLKey")
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

; v1.3.0 had a single [Access] HelloGate plus [Access] HelloWinSettings. v1.3.1
; splits the gate into per-action toggles under [Hello]. Carry old values over
; so the user's choices aren't silently reset, then drop the old keys.
MigrateHelloGate() {
    global INI
    win := ""
    try win := IniRead(INI, "Access", "HelloWinSettings")
    if (win != "") {
        IniWrite(win, INI, "Hello", "WinSettings")
        try IniDelete(INI, "Access", "HelloWinSettings")
    }
    gate := ""
    try gate := IniRead(INI, "Access", "HelloGate")
    if (gate != "") {
        if (gate = "1")
            for k in ["Settings", "SentinelOff", "Release", "Quit"]
                IniWrite("1", INI, "Hello", k)
        try IniDelete(INI, "Access", "HelloGate")
    }
}

SaveConfig() {
    global C, Schema, INI
    for item in Schema {
        k := item.sec "_" item.key
        v := C[k]
        if (IsSecretKey(k) && v != "") {
            enc := Dpapi_Protect(v)
            v := (enc != "") ? "dpapi:" enc : v   ; if encryption fails, store as-is
        }
        IniWrite(v, INI, item.sec, item.key)
    }
    Ini_Sync()    ; keep the tamper-detection backup equal to what we just wrote
}

; ==================================================================
; ===  SECRETS AT REST (DPAPI)  ====================================
; ==================================================================
; Wrap/unwrap a string with Windows DPAPI (CryptProtectData), tied to the
; current Windows user account. The ciphertext is base64 for INI storage and
; is only decryptable by the same user on the same machine -- so the GitHub
; token and DeepL key never sit in multitool.ini as readable text.
Dpapi_Protect(plain) {
    if (plain = "")
        return ""
    inBuf := Buffer(StrPut(plain, "UTF-16"))
    StrPut(plain, inBuf, "UTF-16")
    inB := Dpapi_Blob(inBuf.Ptr, inBuf.Size)
    out := Buffer(2 * A_PtrSize, 0)
    if !DllCall("crypt32\CryptProtectData", "ptr", inB, "ptr", 0, "ptr", 0,
                "ptr", 0, "ptr", 0, "uint", 0, "ptr", out)
        return ""
    res := Dpapi_TakeBlob(out)
    return B64Encode(res)
}

Dpapi_Unprotect(b64) {
    if (b64 = "")
        return ""
    data := B64Decode(b64)
    if (data.Size = 0)
        return ""
    inB := Dpapi_Blob(data.Ptr, data.Size)
    out := Buffer(2 * A_PtrSize, 0)
    if !DllCall("crypt32\CryptUnprotectData", "ptr", inB, "ptr", 0, "ptr", 0,
                "ptr", 0, "ptr", 0, "uint", 0, "ptr", out)
        return ""
    res := Dpapi_TakeBlob(out)
    return StrGet(res.Ptr, "UTF-16")
}

; Build a DATA_BLOB {DWORD cbData; void* pbData} pointing at existing bytes.
Dpapi_Blob(ptr, size) {
    b := Buffer(2 * A_PtrSize, 0)
    NumPut("uint", size, b, 0)
    NumPut("ptr", ptr, b, A_PtrSize)
    return b
}

; Copy the bytes a Crypt*Data output DATA_BLOB points at into a Buffer, then
; LocalFree the OS-allocated memory.
Dpapi_TakeBlob(blob) {
    cb := NumGet(blob, 0, "uint")
    pb := NumGet(blob, A_PtrSize, "ptr")
    res := Buffer(cb)
    DllCall("RtlMoveMemory", "ptr", res, "ptr", pb, "uptr", cb)
    DllCall("kernel32\LocalFree", "ptr", pb)
    return res
}

B64Encode(buf) {
    flags := 0x1 | 0x40000000     ; CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF
    size := 0
    DllCall("crypt32\CryptBinaryToStringW", "ptr", buf, "uint", buf.Size,
            "uint", flags, "ptr", 0, "uint*", &size)
    out := Buffer(size * 2)
    DllCall("crypt32\CryptBinaryToStringW", "ptr", buf, "uint", buf.Size,
            "uint", flags, "ptr", out, "uint*", &size)
    return StrGet(out, "UTF-16")
}

B64Decode(str) {
    size := 0
    DllCall("crypt32\CryptStringToBinaryW", "str", str, "uint", 0, "uint", 0x1,
            "ptr", 0, "uint*", &size, "ptr", 0, "ptr", 0)
    out := Buffer(size, 0)
    DllCall("crypt32\CryptStringToBinaryW", "str", str, "uint", 0, "uint", 0x1,
            "ptr", out, "uint*", &size, "ptr", 0, "ptr", 0)
    return out
}


; ==================================================================
; ===  CLIPBOARD HYGIENE  ==========================================
; ==================================================================
; The translator/layout "copy" actions leave their result on the clipboard.
; Schedule it to be wiped after General -> "Clear clipboard after" seconds, but
; only if it still holds exactly what we put there -- so we never clobber what
; the user copied in the meantime. 0 seconds disables this.
Clip_ScheduleClear(text) {
    global g_ClipGuard
    secs := CfgI("General_ClipClearSec")
    if (secs <= 0 || text = "")
        return
    g_ClipGuard := text
    SetTimer(Clip_DoClear, -secs * 1000)
}

Clip_DoClear() {
    global g_ClipGuard
    if (g_ClipGuard != "" && A_Clipboard = g_ClipGuard) {
        A_Clipboard := ""
        Audit("clipboard", "auto-cleared")
    }
    g_ClipGuard := ""
}


; ==================================================================
; ===  AUDIT LOG  ==================================================
; ==================================================================
; Append a timestamped security event to multitool_audit.log beside the app
; when General -> "Log security events" is on. Best-effort -- never throws, and
; never records secrets (only what happened).
Audit(event, detail := "") {
    if (CfgS("General_AuditLog") != "1")
        return
    line := FormatTime(, "yyyy-MM-dd HH:mm:ss") "  " event
        . (detail != "" ? "  " detail : "") "`r`n"
    try FileAppend(line, A_ScriptDir "\multitool_audit.log", "UTF-8")
}


; ==================================================================
; ===  WINDOWS HELLO GATE  =========================================
; ==================================================================
; Require a Windows Hello check (fingerprint / face / PIN -- whichever the user
; has enrolled) before a sensitive action, when Security -> "Require Windows
; Hello" is on. We shell out to a tiny PowerShell helper that drives the WinRT
; UserConsentVerifier. It FAILS OPEN when Hello isn't set up on this PC or the
; check errors (so the app can never lock you out of your own machine), and
; FAILS CLOSED only on an explicit deny/cancel.
; Gate an action behind Hello only if the user ticked it on the Hello tab.
; `target` is the [Hello] key (Settings / SentinelOff / Release / Quit);
; `label` is what the prompt says.
Hello_Gate(target, label) {
    if (CfgS("Hello_" target) != "1")
        return true
    return Hello_Verify(label)
}

Hello_Verify(message) {
    ps := Hello_ScriptPath()
    if (ps = "")
        return true
    code := RunWait(Format('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "{1}" "{2}"',
        ps, StrReplace(message, '"', "")), , "Hide")
    switch code {
        case 0:
            Audit("hello", "verified -- " message)
            return true
        case 1:
            Audit("hello", "DENIED -- " message)
            return false
        default:   ; 2 = no Hello on this PC, 3 = error -> don't brick the user
            Audit("hello", "skipped(code " code ") -- " message)
            return true
    }
}

; Stage the PowerShell helper in %TEMP% (rewritten each call so it can't go
; stale across versions). All string literals use double quotes and no
; apostrophes/backticks, so each line embeds cleanly as a single-quoted AHK
; string. Returns the path, or "" if it couldn't be written.
Hello_ScriptPath() {
    p := A_Temp "\multitool_hello.ps1"
    lines := [
        '$ErrorActionPreference = "Stop"',
        '$msg = if ($args.Count -ge 1) { $args[0] } else { "Verify your identity" }',
        'try {',
        '  [void][Windows.Security.Credentials.UI.UserConsentVerifier, Windows.Security.Credentials.UI, ContentType=WindowsRuntime]',
        '  Add-Type -AssemblyName System.Runtime.WindowsRuntime',
        '  $gen = "IAsyncOperation" + [char]96 + "1"',
        '  $asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq "AsTask" -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq $gen } | Select-Object -First 1',
        '  function Await($op, $T) { $t = $asTask.MakeGenericMethod($T).Invoke($null, @($op)); $t.Wait(-1) | Out-Null; $t.Result }',
        '  $availT = [Windows.Security.Credentials.UI.UserConsentVerifierAvailability]',
        '  $avail = Await ([Windows.Security.Credentials.UI.UserConsentVerifier]::CheckAvailabilityAsync()) $availT',
        '  if ($avail -ne $availT::Available) { exit 2 }',
        '  $resT = [Windows.Security.Credentials.UI.UserConsentVerificationResult]',
        '  $res = Await ([Windows.Security.Credentials.UI.UserConsentVerifier]::RequestVerificationAsync($msg)) $resT',
        '  if ($res -eq $resT::Verified) { exit 0 } else { exit 1 }',
        '} catch { exit 3 }'
    ]
    body := ""
    for ln in lines
        body .= ln "`n"
    try {
        if FileExist(p)
            FileDelete(p)
        FileAppend(body, p, "UTF-8")
        return p
    } catch
        return ""
}

; True if Windows Hello (fingerprint / face / PIN) is set up and usable on this
; PC. Probes UserConsentVerifier.CheckAvailabilityAsync via a tiny PowerShell
; helper -- this shows NO prompt, so it's safe to poll. Used to decide whether
; the Windows-Settings guard should do anything at all.
Hello_Available() {
    ps := Hello_AvailScriptPath()
    if (ps = "")
        return false
    code := -1
    try code := RunWait(Format('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "{1}"', ps), , "Hide")
    return (code = 0)
}

; The availability-probe PowerShell (same WinRT plumbing as the verifier, minus
; the RequestVerificationAsync prompt). Exit 0 = Hello available.
Hello_AvailScriptPath() {
    p := A_Temp "\multitool_hello_avail.ps1"
    lines := [
        '$ErrorActionPreference = "Stop"',
        'try {',
        '  [void][Windows.Security.Credentials.UI.UserConsentVerifier, Windows.Security.Credentials.UI, ContentType=WindowsRuntime]',
        '  Add-Type -AssemblyName System.Runtime.WindowsRuntime',
        '  $gen = "IAsyncOperation" + [char]96 + "1"',
        '  $asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq "AsTask" -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq $gen } | Select-Object -First 1',
        '  function Await($op, $T) { $t = $asTask.MakeGenericMethod($T).Invoke($null, @($op)); $t.Wait(-1) | Out-Null; $t.Result }',
        '  $availT = [Windows.Security.Credentials.UI.UserConsentVerifierAvailability]',
        '  $avail = Await ([Windows.Security.Credentials.UI.UserConsentVerifier]::CheckAvailabilityAsync()) $availT',
        '  if ($avail -eq $availT::Available) { exit 0 } else { exit 1 }',
        '} catch { exit 1 }'
    ]
    body := ""
    for ln in lines
        body .= ln "`n"
    try {
        if FileExist(p)
            FileDelete(p)
        FileAppend(body, p, "UTF-8")
        return p
    } catch
        return ""
}

; Hello-gated entry points used by the tray menu and global hotkeys. The
; internal ShowSettings() re-show after a theme change stays ungated on purpose.
RequestSettings(*) {
    if Hello_Gate("Settings", "Open MultiTool settings")
        ShowSettings()
}
RequestQuit(*) {
    if Hello_Gate("Quit", "Quit MultiTool")
        ExitApp()
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

    ; If "Resist being killed" is on, the exe carries a deny-delete ACL that would
    ; make the installer's `move /Y` over it fail. Lift the file protection now so
    ; the swap succeeds; the relaunched build re-applies it on startup.
    if (CfgS("Access_AntiKill") = "1")
        Files_SetDeletable(true)
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
        [CfgS("General_HotkeyQuit"),     (*) => RequestQuit()],
        [CfgS("General_HotkeySettings"), (*) => RequestSettings()]
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
    tab := g.AddTab3("x10 y10 w600 h428", names)

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
    g.AddText("x16 y446 w380", "Hotkeys:   ^ Ctrl    ! Alt    # Win    + Shift")
    g.SetFont("s10 c" t.fg, "Segoe UI")

    g.AddButton("x380 y472 w72 h28", "Cancel").OnEvent("Click", (*) => g.Destroy())
    g.AddButton("x458 y472 w72 h28", "Apply").OnEvent("Click", ApplyAndRefresh)
    g.AddButton("x536 y472 w72 h28 +Default", "Save").OnEvent("Click", SaveAndClose)

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
    g.Show("w620 h518")
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
    if (sec = "Hello")
        ExtendHelloTab(g, t, &yPos)
    if (sec = "Access")
        ExtendAccessTab(g, t, &yPos)
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
    g.AddButton("x28 y" yPos " w200 h28", "Enroll profile...")
        .OnEvent("Click", (*) => Sec_Enroll())

    g.SetFont("s9 c" t.hintFg, "Segoe UI")
    g.AddText("x240 y" (yPos + 6) " w300", Sec_StatusLine())
    yPos += 40

    g.SetFont("s10 bold c" t.popupAccent, "Segoe UI")
    g.AddText("x28 y" yPos " w540",
        "Real protection on Windows = BitLocker + Windows Hello + Dynamic Lock; "
        "this sentinel is only a deterrent.")
    yPos += 46

    g.SetFont("s9 c" t.hintFg, "Segoe UI")
    g.AddText("x28 y" yPos " w540",
        "Watches your typing, mouse and app-switching rhythm (aggregates only -- "
        "never keys, text, coordinates or app names) and locks the screen when your "
        "behaviour stops matching. Enroll once, then tick Enable.")
    yPos += 50

    g.AddText("x28 y" yPos " w540",
        "Needs Python with: scikit-learn, numpy, skops, pynput (pip install -r "
        "requirements.txt). A .venv beside MultiTool is used automatically; else "
        "set the Python executable above to that interpreter.")
    yPos += 50
    g.SetFont("s10 c" t.fg, "Segoe UI")
}

; Help text for the Access sub-tab: how to identify the possession tokens, and
; what the gates / lock-when-away actually do.
; Hint for the Hello sub-tab: tick which actions demand a Windows Hello check.
ExtendHelloTab(g, t, &yPos) {
    yPos += 10
    g.SetFont("s9 c" t.hintFg, "Segoe UI")
    g.AddText("x28 y" yPos " w540",
        "Tick what should require a Windows Hello check (fingerprint / face / PIN). "
        "Windows Settings is closed and only reopened if you pass; the others just "
        "won't proceed without it. Needs Hello enrolled in Windows -- any box is "
        "skipped (allowed) if Hello isn't set up, so it can't lock you out.")
    yPos += 64
    g.SetFont("s10 c" t.fg, "Segoe UI")
}

; Hint for the Lock-away sub-tab: anti-kill + possession.
ExtendAccessTab(g, t, &yPos) {
    yPos += 10
    g.SetFont("s9 c" t.hintFg, "Segoe UI")
    g.AddText("x28 y" yPos " w540",
        "Resist being killed / deleted / tampered: denies non-elevated taskkill / "
        "Task Manager, deny-deletes the exe + ini + profile (and the folder's "
        "delete-child right), runs a watchdog that relaunches the app if killed, "
        "restores those files if deleted, and reverts out-of-band edits to the ini "
        "(so nobody disables protection by editing settings on disk). While it's "
        "on you can't casually delete files here, and hand-editing the ini is "
        "reverted -- change settings in-app, and turn it off to uninstall. An "
        "ADMIN can still take ownership / kill it; the tray Exit always works. "
        "(Self-resurrecting -- antivirus may warn.)")
    yPos += 124
    g.AddText("x28 y" yPos " w540",
        "Lock when away: locks the PC once your token's been gone for the grace "
        "period.  USB id: a VID_xxxx&PID_xxxx fragment or name.  Bluetooth: the "
        "paired device's name or MAC.")
    yPos += 50
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
    Possess_Apply()
    WinGuard_Apply()
    Protect_Apply()

    if (errs != "") {
        MsgBox("Some hotkeys could not be set:`n`n" errs "`nThe rest were applied.",
            "MultiTool", "Icon!")
        return false
    }
    Audit("settings", "saved")
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
    tray.Add("Settings", (*) => RequestSettings())
    tray.Add("Check for updates", (*) => CheckForUpdates(true))
    tray.Add("Reload", (*) => Reload())
    tray.Add()
    tray.Add("MultiTool v" APP_VERSION, (*) => 0)
    tray.Disable("MultiTool v" APP_VERSION)
    tray.Add("Exit", (*) => RequestQuit())
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
            Clip_ScheduleClear(result.text)
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
    Clip_ScheduleClear(out)
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
    global bGlowG, bRing, bStripL, bStripR
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

    ; Glow: a soft halo of the same hue fading inward from the solid border.
    ; Precompute, per hue, an "inward strip" -- a column of bRing premultiplied
    ; pixels [solid x bThick][glow 0..bGlowG-1], alpha fading quadratically. Draw()
    ; fills the border from these strips with bulk copies (memcpy / run-fill) rather
    ; than writing every pixel. bStripR is bStripL reversed (the right/bottom edges
    ; run inward the other way). NOTE: loop-index locals (gd/ri) must NOT be named
    ; like the loop *count* (bGlowG/bRing) -- AHK names are case-insensitive, and a
    ; clash would silently corrupt the count mid-loop.
    bGlowG := 0
    if (CfgS("Rainbow_Glow") = "1") {
        gMax := (Min(bW, bH) // 2) - bThick - 1     ; keep the ring off the centre
        bGlowG := Max(0, Min(CfgI("Rainbow_GlowSize"), gMax))
    }
    bRing := bThick + bGlowG
    gStr := CfgN("Rainbow_GlowStrength")
    gStr := (gStr < 0) ? 0 : (gStr > 1) ? 1 : gStr
    gAlpha := []
    Loop bGlowG {
        tf := (bGlowG - (A_Index - 1)) / bGlowG     ; 1.0 next to border -> ~0 inward
        av := Round(gStr * 255 * tf * tf)
        gAlpha.Push((av < 0) ? 0 : (av > 255) ? 255 : av)
    }
    bStripL := Buffer(360 * bRing * 4, 0)
    bStripR := Buffer(360 * bRing * 4, 0)
    Loop 360 {
        sBase := (A_Index - 1) * bRing
        full := bPalette[A_Index]
        pr := (full >> 16) & 0xFF, pg := (full >> 8) & 0xFF, pb := full & 0xFF
        Loop bThick                                  ; solid (full alpha)
            NumPut("uint", full, bStripL, (sBase + A_Index - 1) * 4)
        Loop bGlowG {                                ; glow (premultiplied at its alpha)
            gd := A_Index - 1
            av := gAlpha[gd + 1]
            NumPut("uint", (av << 24) | (((pr*av)//255) << 16) | (((pg*av)//255) << 8) | ((pb*av)//255)
                , bStripL, (sBase + bThick + gd) * 4)
        }
        Loop bRing {                                 ; reversed copy for the far edges
            ri := A_Index - 1
            NumPut("uint", NumGet(bStripL, (sBase + bRing - 1 - ri) * 4, "uint"), bStripR, (sBase + ri) * 4)
        }
    }

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

; The border is filled from the precomputed per-hue strips with bulk memory
; copies instead of a per-pixel loop (~2.4x faster with glow on, verified
; pixel-identical to the old per-pixel renderer): the left/right edges are
; contiguous per row (one memcpy each), and the top/bottom edges share a hue
; across ~P/360 adjacent columns, so each run is filled with a doubling copy.
Draw() {
    global bOffset, bSpeed, bW, bH, bThick, bInvP, bPBits
    global bRing, bStripL, bStripR
    global bGui, bMemDC, bPtDst, bSzWin, bPtSrc, bBlend

    bOffset += bSpeed
    if (bOffset >= 1.0)
        bOffset -= 1.0

    P4 := bPBits, W := bW, H := bH, T := bThick, R := bRing
    SL := bStripL.Ptr, SR := bStripR.Ptr, RB := R * 4
    off := bOffset, invP := bInvP

    Hedge(P4, SL, W, T, R, RB, off, invP, 0, W, 0, 1)                    ; top
    Hedge(P4, SL, W, T, R, RB, off, invP, (H - 1) * W, -W, 2*W + H, -1)  ; bottom
    Vedge(P4, SL, W, H, T, R, RB, off, invP, 2*W + 2*H, -1, 0)           ; left
    Vedge(P4, SR, W, H, T, R, RB, off, invP, W, 1, 1)                    ; right

    DllCall("user32\UpdateLayeredWindow", "ptr", bGui.Hwnd, "ptr", 0, "ptr", bPtDst
        , "ptr", bSzWin, "ptr", bMemDC, "ptr", bPtSrc, "uint", 0, "ptr", bBlend, "uint", 2)
}

; Fill columns [xs, xe) of a horizontal edge band for every inward depth, from
; one hue's strip. Each depth-row is a run of identical 32-bit pixels filled by
; doubling (write one, copy 1->2->4->8...): ~log2(runLen) native copies, no
; per-pixel loop. (r0/rs map depth->row: top r0=0,rs=W ; bottom r0=(H-1)W,rs=-W.)
HFillRun(P4, SL, xs, xe, hue, R, RB, r0, rs) {
    runLen := xe - xs
    sB := SL + hue * RB
    Loop R {
        d := A_Index - 1
        dest := P4 + (r0 + d*rs + xs) * 4
        NumPut("uint", NumGet(sB + d*4, "uint"), dest)
        done := 1
        Loop {
            if (done >= runLen)
                break
            n := runLen - done
            if (n > done)
                n := done
            DllCall("ntdll\RtlMoveMemory", "ptr", dest + done*4, "ptr", dest, "uptr", n*4)
            done += n
        }
    }
}

; One horizontal edge (top or bottom). Solid is full-width; glow is mitred at the
; corners. Corner columns are written per-pixel; the middle is filled in same-hue
; runs. hue(x) = ((hbase + hsign*x)*invP + off) wrapped to [0,1).
Hedge(P4, SL, W, T, R, RB, off, invP, r0, rs, hbase, hsign) {
    Loop R {                                          ; corner columns [0, R)
        x := A_Index - 1
        h := (hbase + hsign*x) * invP + off
        if (h >= 1.0)
            h -= 1.0
        sB := SL + Integer(h*360) * RB
        cnt := (x + 1 < T) ? T : x + 1                ; Max(T, dMax),  dMax = x+1
        Loop cnt {
            d := A_Index - 1
            NumPut("uint", NumGet(sB + d*4, "uint"), P4 + (r0 + d*rs + x) * 4)
        }
    }
    Loop R {                                          ; corner columns [W-R, W)
        x := W - R + A_Index - 1
        h := (hbase + hsign*x) * invP + off
        if (h >= 1.0)
            h -= 1.0
        sB := SL + Integer(h*360) * RB
        dMax := W - x
        cnt := (dMax < T) ? T : dMax
        Loop cnt {
            d := A_Index - 1
            NumPut("uint", NumGet(sB + d*4, "uint"), P4 + (r0 + d*rs + x) * 4)
        }
    }
    prevHue := -1, runStart := R                      ; middle [R, W-R): same-hue runs
    Loop (W - 2*R) {
        x := R + A_Index - 1
        h := (hbase + hsign*x) * invP + off
        if (h >= 1.0)
            h -= 1.0
        iT := Integer(h*360)
        if (iT != prevHue) {
            if (prevHue >= 0)
                HFillRun(P4, SL, runStart, x, prevHue, R, RB, r0, rs)
            runStart := x
            prevHue := iT
        }
    }
    if (prevHue >= 0)
        HFillRun(P4, SL, runStart, W - R, prevHue, R, RB, r0, rs)
}

; One vertical edge (left or right). The band is contiguous per row, so each row
; is a single memcpy of the hue's strip, clipped near the top/bottom corners by
; the miter (cnt = Max(T, Min(R, y, H-1-y))). rightSide flips it to the far
; columns using the reversed strip.
Vedge(P4, strip, W, H, T, R, RB, off, invP, hbase, hsign, rightSide) {
    Loop H {
        y := A_Index - 1
        hv := (hbase + hsign*y) * invP + off
        if (hv >= 1.0)
            hv -= 1.0
        srcRow := strip + Integer(hv*360) * RB
        m := y
        if (H - 1 - y < m)
            m := H - 1 - y
        if (R < m)
            m := R
        cnt := (m < T) ? T : m
        if (rightSide)
            DllCall("ntdll\RtlMoveMemory", "ptr", P4 + (y*W + W - cnt)*4, "ptr", srcRow + (R - cnt)*4, "uptr", cnt*4)
        else
            DllCall("ntdll\RtlMoveMemory", "ptr", P4 + (y*W)*4, "ptr", srcRow, "uptr", cnt*4)
    }
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
    if !Hello_Gate("Release", "Publish a GitHub release")
        return
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
            Audit("release", "published " repo " " pending.tag)
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
    ; An explicit, non-default setting always wins.
    p := Trim(CfgS("Security_PythonPath"))
    if (p != "" && p != "python")
        return p
    ; Otherwise prefer a virtual-env interpreter sitting beside the script: it's
    ; almost certainly the one with the sentinel's deps (numpy/scikit-learn/
    ; skops/pynput) installed, which a bare "python" on PATH often lacks.
    for venv in [A_ScriptDir "\.venv\Scripts\python.exe",
                 A_ScriptDir "\venv\Scripts\python.exe"]
        if FileExist(venv)
            return venv
    return "python"
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
            r := MsgBox("The sentinel must learn your behaviour before it can run."
                "`n`nEnroll a profile now? (Use the PC normally -- type, move the "
                "mouse, switch apps -- for a few minutes in the console that opens.)",
                "MultiTool", "YesNo Iconi")
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
        Audit("sentinel", "started")
        if interactive
            TrayTip("Sentinel is watching your typing, mouse and app-switching.", "MultiTool")
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
    turningOff := (CfgS("Security_Enabled") = "1")
    if (turningOff && !Hello_Gate("SentinelOff", "Disable the keystroke sentinel"))
        return                       ; identity check failed -- leave it running
    newVal := turningOff ? "0" : "1"
    C["Security_Enabled"] := newVal
    IniWrite(newVal, INI, "Security", "Enabled")
    Ini_Sync()                       ; this is a direct INI write -- resync the trusted backup
    if (newVal = "1") {
        Sec_Apply(true)
    } else {
        Sec_Stop()
        Audit("sentinel", "disabled")
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
; ===  POSSESSION FACTOR  ==========================================
; ==================================================================
; "Lock when away": treat a configured USB device and/or a paired Bluetooth
; device as proof you're at the keyboard. While Security -> "Lock when away" is
; on, a timer polls for them; once every configured token has been gone for the
; grace period, the workstation is locked. Detection is tolerant -- present if
; ANY configured token is present, and a detection *error* counts as present --
; so a glitch never locks you out, and you can carry just one token.
PossessAbsentSince := 0.0

Possess_Apply() {
    global PossessAbsentSince
    SetTimer(Possess_Tick, 0)
    PossessAbsentSince := 0.0
    mode := CfgS("Access_PossessMode")
    if (mode = "USB" || mode = "Bluetooth" || mode = "Both") {
        SetTimer(Possess_Tick, 3000)
        Audit("possession", "armed (" mode ")")
    }
}

Possess_Tick() {
    global PossessAbsentSince
    mode  := CfgS("Access_PossessMode")
    usbId := Trim(CfgS("Access_PossessUsb"))
    btId  := Trim(CfgS("Access_PossessBt"))
    checkUsb := (mode = "USB" || mode = "Both") && usbId != ""
    checkBt  := (mode = "Bluetooth" || mode = "Both") && btId != ""
    if (!checkUsb && !checkBt)
        return                       ; mode on but nothing configured -- never lock

    present := false
    if (checkUsb && Possess_UsbPresent(usbId))
        present := true
    if (!present && checkBt && Possess_BtConnected(btId))
        present := true

    now := A_TickCount / 1000.0
    if (present) {
        PossessAbsentSince := 0.0
        return
    }
    if (PossessAbsentSince = 0.0) {
        PossessAbsentSince := now     ; first miss -- start the grace clock
        return
    }
    if (now - PossessAbsentSince >= CfgI("Access_PossessGrace")) {
        Audit("possession", "token absent -- locking")
        PossessAbsentSince := 0.0
        DllCall("user32\LockWorkStation")
    }
}

; USB present if any Plug-and-Play device's id or name contains the configured
; fragment (e.g. "VID_1050&PID_0407" for a YubiKey, or a device name). A WMI
; error counts as present so a glitch can't lock you out.
Possess_UsbPresent(id) {
    q := StrReplace(id, "'", "")
    try {
        wmi := ComObjGet("winmgmts:\\.\root\cimv2")
        sql := "SELECT PNPDeviceID FROM Win32_PnPEntity WHERE PNPDeviceID LIKE '%"
             . q "%' OR Name LIKE '%" q "%'"
        for dev in wmi.ExecQuery(sql)
            return true
        return false
    } catch {
        return true
    }
}

; Bluetooth: present if a remembered device whose name or MAC matches the
; setting reports fConnected. Win32 Bluetooth API; any failure counts as present.
Possess_BtConnected(idOrName) {
    needle := StrLower(Trim(idOrName))
    mac := StrReplace(StrReplace(StrReplace(needle, ":", ""), "-", ""), " ", "")
    try {
        sp := Buffer(40, 0)               ; BLUETOOTH_DEVICE_SEARCH_PARAMS (x64)
        NumPut("uint", 40, sp, 0)         ; dwSize
        NumPut("int", 1, sp, 4)           ; fReturnAuthenticated
        NumPut("int", 1, sp, 8)           ; fReturnRemembered
        NumPut("int", 1, sp, 16)          ; fReturnConnected
        NumPut("uchar", 2, sp, 24)        ; cTimeoutMultiplier
        di := Buffer(560, 0)              ; BLUETOOTH_DEVICE_INFO (x64)
        NumPut("uint", 560, di, 0)        ; dwSize
        hFind := DllCall("bthprops.cpl\BluetoothFindFirstDevice", "ptr", sp, "ptr", di, "ptr")
        if !hFind
            return false                  ; queried fine, no remembered devices
        connectedMatch := false
        loop {
            name := StrLower(StrGet(di.Ptr + 64, 248, "UTF-16"))
            addr := Format("{:012x}", NumGet(di, 8, "uint64"))
            if ((InStr(name, needle) || (mac != "" && InStr(addr, mac)))
                && NumGet(di, 20, "int"))
                connectedMatch := true
            NumPut("uint", 560, di, 0)
            if !DllCall("bthprops.cpl\BluetoothFindNextDevice", "ptr", hFind, "ptr", di)
                break
        }
        DllCall("bthprops.cpl\BluetoothFindDeviceClose", "ptr", hFind)
        return connectedMatch
    } catch {
        return true                       ; API unavailable -> fail safe (present)
    }
}


; ==================================================================
; ===  WINDOWS SETTINGS HELLO GUARD  ===============================
; ==================================================================
; When Access -> "Hello to open Windows Settings" is on, a timer watches for the
; Windows Settings app coming to the foreground. The moment it does we FULLY
; CLOSE it (kill the process), then demand Windows Hello. Pass -> we reopen
; Settings ourselves and trust the new window. Fail -> it stays closed. Closing
; before the prompt means the window can't be used at all while the check is
; pending. We only act when Hello is actually available (cached, refreshed in
; the background), so machines without Hello get no prompt and no interference.
; State (WinGuardOkHwnd / Busy / HelloOk / SuppressUntil) is initialized in the
; GLOBAL STATE block near the top, before STARTUP starts these timers.

WinGuard_Apply() {
    global WinGuardOkHwnd, WinGuardHelloOk, WinGuardSuppressUntil
    SetTimer(WinGuard_Tick, 0)
    SetTimer(WinGuard_RefreshHello, 0)
    WinGuardOkHwnd := 0
    WinGuardHelloOk := -1
    WinGuardSuppressUntil := 0
    if (CfgS("Hello_WinSettings") = "1") {
        SetTimer(WinGuard_RefreshHello, -1200)   ; warm the availability cache off the startup path
        SetTimer(WinGuard_Tick, 400)
    }
}

; Refresh the cached "is Windows Hello usable" flag (a quick PowerShell probe
; that shows no prompt). Runs shortly after arming and after each settings save.
WinGuard_RefreshHello() {
    global WinGuardHelloOk
    WinGuardHelloOk := Hello_Available() ? 1 : 0
}

WinGuard_Tick() {
    global WinGuardOkHwnd, WinGuardBusy, WinGuardHelloOk, WinGuardSuppressUntil
    if (WinGuardBusy || WinGuardHelloOk != 1)
        return                             ; busy, or Hello not usable -> do nothing
    if (A_TickCount < WinGuardSuppressUntil)
        return                             ; a window we just reopened after a pass
    ; A cleared Settings window that has since closed -> re-arm.
    if (WinGuardOkHwnd && !WinExist("ahk_id " WinGuardOkHwnd))
        WinGuardOkHwnd := 0

    hwnd := WinExist("A")                  ; the foreground window
    if (!hwnd || !WinGuard_IsSettings(hwnd))
        return
    if (hwnd = WinGuardOkHwnd)
        return                             ; already cleared this Settings window

    WinGuardBusy := true
    ; Keep Settings dead for the WHOLE prompt. This timer keeps firing even while
    ; the blocking Hello check below runs (AHK runs timers during RunWait), so a
    ; second Settings window opened while you ignore the prompt is killed before
    ; it can be used. That was the bypass.
    SetTimer(WinGuard_Killer, 90)
    passed := false
    try {
        try ProcessClose("SystemSettings.exe")
        passed := Hello_Verify("Open Windows Settings")
    } finally {
        SetTimer(WinGuard_Killer, 0)       ; stop killing before we maybe reopen
    }

    if (passed) {
        ; Reopen Settings ourselves and trust the new window. The suppress
        ; window covers the gap until we capture the new hwnd.
        Audit("winsettings", "unlocked -- reopening")
        WinGuardSuppressUntil := A_TickCount + 8000
        Run("ms-settings:")
        Loop 30 {                          ; grab the reopened window (~3 s max)
            Sleep(100)
            a := WinExist("A")
            if (a && WinGuard_IsSettings(a)) {
                WinGuardOkHwnd := a
                break
            }
        }
    } else {
        Audit("winsettings", "DENIED -- Settings stays closed")
        try ProcessClose("SystemSettings.exe")
    }
    WinGuardBusy := false
}

; Runs only while a Hello check is pending (started/stopped by WinGuard_Tick).
; Ensures no Settings process exists, so Settings can't be opened or used during
; the prompt no matter how many times it's launched.
WinGuard_Killer() {
    if ProcessExist("SystemSettings.exe")
        ProcessClose("SystemSettings.exe")
}

; True if `hwnd` is the Windows Settings app. On Win11 its window belongs to
; SystemSettings.exe directly; on Win10 it's hosted by ApplicationFrameHost, so
; we look at the CoreWindow child's real process.
WinGuard_IsSettings(hwnd) {
    proc := ""
    try proc := WinGetProcessName("ahk_id " hwnd)
    if (proc = "SystemSettings.exe")
        return true
    if (proc = "ApplicationFrameHost.exe") {
        child := DllCall("FindWindowExW", "ptr", hwnd, "ptr", 0,
            "wstr", "Windows.UI.Core.CoreWindow", "ptr", 0, "ptr")
        if child {
            cproc := ""
            try cproc := WinGetProcessName("ahk_id " child)
            return (cproc = "SystemSettings.exe")
        }
    }
    return false
}


; ==================================================================
; ===  PROCESS PROTECTION (Access -> "Resist being killed")  =======
; ==================================================================
; Two honest deterrents -- a local ADMIN with an elevated Task Manager can still
; kill anything:
;   1. A deny-TERMINATE DACL on this process, so non-elevated taskkill /
;      Task Manager "End task" / Stop-Process get Access Denied (tested).
;   2. A watchdog: a hidden Windows Script Host (wscript) process that relaunches
;      MultiTool if it's killed; MultiTool relaunches the watchdog if THAT's
;      killed (mutual). A wscript helper (not a 2nd multitool.exe) avoids the
;      app's #SingleInstance. A clean Exit drops a flag the watchdog honours, so
;      quitting normally never resurrects.
;
; NOTE: a self-resurrecting process pair is exactly what antivirus heuristics
; look for -- expect AV warnings; this is opt-in and off by default.
; (WatchdogPID is initialized in the GLOBAL STATE block near the top.)

ProtectFlagPath()  => A_Temp "\multitool_quit.flag"
WatchdogVbsPath()  => A_Temp "\multitool_watchdog.vbs"

Protect_Apply() {
    global FilesProtected
    if (CfgS("Access_AntiKill") = "1") {
        Protect_SetTerminable(false)          ; ACL protection takes effect immediately
        Files_Stash()                         ; refresh backups (incl. the current INI)
        if (!FilesProtected) {
            Files_SetDeletable(false)          ; deny-delete the exe / ini / profile + folder
            FilesProtected := true
        }
        SetTimer(Heal_Tick, 4000)             ; restore anything that gets deleted
        SetTimer(Watchdog_Tick, 0)
        SetTimer(Watchdog_Arm, -3000)         ; arm the watchdog a few seconds in, so a
    } else {                                  ; crash during startup can't loop-resurrect
        SetTimer(Watchdog_Arm, 0)
        SetTimer(Watchdog_Tick, 0)
        SetTimer(Heal_Tick, 0)
        Watchdog_Stop()
        Protect_SetTerminable(true)
        if (FilesProtected) {
            Files_SetDeletable(true)           ; lift the deny-delete ACLs...
            Files_ClearStash()                 ; ...then drop the now-stale backups
            FilesProtected := false
        }
    }
}

; Spawn the watchdog and start the mutual-guard tick (deferred from Protect_Apply
; so the app is past its startup before anything can resurrect it).
Watchdog_Arm() {
    if (CfgS("Access_AntiKill") != "1")
        return
    Watchdog_Ensure()
    SetTimer(Watchdog_Tick, 2000)
}

; Add (canTerminate=false) or remove (true) a DACL that denies the TERMINATE
; right to Everyone. Admins with SeDebugPrivilege (elevated) bypass it anyway.
Protect_SetTerminable(canTerminate) {
    sddl := canTerminate ? "D:(A;;0x1FFFFF;;;WD)" : "D:(D;;0x1;;;WD)(A;;0x1FFFFF;;;WD)"
    pSD := 0
    if !DllCall("advapi32\ConvertStringSecurityDescriptorToSecurityDescriptorW",
                "wstr", sddl, "uint", 1, "ptr*", &pSD, "ptr", 0)
        return
    present := 0, pDacl := 0, defaulted := 0
    DllCall("advapi32\GetSecurityDescriptorDacl", "ptr", pSD, "int*", &present,
            "ptr*", &pDacl, "int*", &defaulted)
    DllCall("advapi32\SetSecurityInfo", "ptr", DllCall("GetCurrentProcess", "ptr"),
            "uint", 6, "uint", 4, "ptr", 0, "ptr", 0, "ptr", pDacl, "ptr", 0)
    DllCall("LocalFree", "ptr", pSD)
}

; Spawn the hidden wscript watchdog (guarding our PID), if not already running.
Watchdog_Ensure() {
    global WatchdogPID
    if (WatchdogPID && ProcessExist(WatchdogPID))
        return
    try FileDelete(ProtectFlagPath())          ; clear any stale clean-exit flag
    Watchdog_WriteVbs()
    try {
        Run(Format('wscript.exe //B //Nologo "{1}" {2} "{3}" "{4}" "{5}"',
            WatchdogVbsPath(), ProcessExist(), A_ScriptFullPath, ProtectFlagPath(),
            GuardBackup(A_ScriptFullPath)),    ; restore the exe from here if it's been deleted
            , "Hide", &pid)
        WatchdogPID := pid
    }
}

; Write the watchdog script: relaunch <path> if pid dies, unless the quit flag
; appears (clean shutdown). Plain ASCII so wscript reads it as ANSI.
Watchdog_WriteVbs() {
    p := WatchdogVbsPath()
    lines := [
        "Dim pid, path, flag, bak, fso, sh, svc",
        "pid  = CLng(WScript.Arguments(0))",
        "path = WScript.Arguments(1)",
        "flag = WScript.Arguments(2)",
        "bak  = WScript.Arguments(3)",
        "Set fso = CreateObject(" Chr(34) "Scripting.FileSystemObject" Chr(34) ")",
        "Set sh  = CreateObject(" Chr(34) "WScript.Shell" Chr(34) ")",
        "Set svc = GetObject(" Chr(34) "winmgmts:\\.\root\cimv2" Chr(34) ")",
        "Do",
        "  WScript.Sleep 1000",
        "  If fso.FileExists(flag) Then",
        "    fso.DeleteFile(flag)",
        "    WScript.Quit",
        "  End If",
        "  If svc.ExecQuery(" Chr(34) "SELECT ProcessId FROM Win32_Process WHERE ProcessId=" Chr(34) " & pid).Count = 0 Then",
        "    If (Not fso.FileExists(path)) And fso.FileExists(bak) Then fso.CopyFile bak, path, True",
        "    sh.Run " Chr(34) Chr(34) Chr(34) Chr(34) " & path & " Chr(34) Chr(34) Chr(34) Chr(34) ", 0, False",
        "    WScript.Quit",
        "  End If",
        "Loop"
    ]
    body := ""
    for ln in lines
        body .= ln "`r`n"
    try FileDelete(p)
    try FileAppend(body, p, "CP0")             ; ANSI for the script host
}

; Mutual guard: if the watchdog was killed while protection is on, respawn it.
Watchdog_Tick() {
    global WatchdogPID
    if (CfgS("Access_AntiKill") != "1")
        return
    if (!WatchdogPID || !ProcessExist(WatchdogPID))
        Watchdog_Ensure()
}

; Tell the watchdog to stand down (drop the flag; it quits within ~1 s).
Watchdog_Stop() {
    global WatchdogPID
    try FileAppend("", ProtectFlagPath())
    WatchdogPID := 0
}

; Signal a clean shutdown so the watchdog doesn't relaunch us. Runs on
; ExitApp/Reload via OnExit -- but NOT on a force-kill, which is the point.
Protect_SignalQuit() {
    try FileAppend("", ProtectFlagPath())
}


; ==================================================================
; ===  FILE GUARD (deny-delete ACL + self-heal)  ===================
; ==================================================================
; Folded into "Resist being killed". Deleting multitool.exe / multitool.ini /
; the sentinel profile neutralises every protection -- and deleting just the INI
; reverts to unprotected DEFAULTS on the next launch. So while protection is on:
;   (a) a deny-DELETE ACL on those files PLUS deny-DELETE_CHILD on the app folder
;       (both are needed -- a file-only deny is bypassed via the folder's
;       delete-child right, which is why deletion "just works" otherwise), and
;   (b) a hidden backup store + self-heal: anything deleted is restored -- at
;       runtime (timer), from the watchdog (even the exe, before it relaunches),
;       and at startup BEFORE the INI is read (so a wiped INI can't load
;       unprotected). Overwrites/creates still work, so the app keeps running.
; Honest limits (same as the process side): a casual / non-admin delete is
; blocked; the owner can strip the ACL with deliberate effort and an admin can
; take ownership -- self-heal is what covers those, until someone also wipes the
; (hidden) backup store. SID *S-1-1-0 = "Everyone" (locale-independent).

GuardDir() => A_AppData "\MultiTool\guard"
GuardBackup(path) {
    SplitPath(path, &name)
    return GuardDir() "\" name
}
GuardName(path) {
    SplitPath(path, &name)
    return name
}
; Files worth guarding. The exe only matters for a compiled build.
Files_Guarded() {
    global INI
    list := [INI, SentinelProfile()]
    if A_IsCompiled
        list.InsertAt(1, A_ScriptFullPath)
    return list
}

; Copy the current primaries into the hidden backup store (creating it if need
; be). Cheap; runs on every Protect_Apply so the INI backup tracks settings.
Files_Stash() {
    dir := GuardDir()
    if !DirExist(dir) {
        try DirCreate(dir)
        try FileSetAttrib("+H", dir)
    }
    for p in Files_Guarded()
        if FileExist(p)
            try FileCopy(p, GuardBackup(p), true)
}

; Wipe the backup store -- called when protection is turned OFF, so a later INI
; deletion can't resurrect now-stale protected settings. Denies are stripped
; first (by the caller) so the recursive delete can proceed.
Files_ClearStash() {
    try DirDelete(GuardDir(), true)
}

; Refresh just the INI backup so it always equals the last value the APP wrote.
; Called right after every legitimate INI write (SaveConfig, the sentinel toggle)
; so an out-of-band edit is the only way the live INI can differ from the backup
; -- which is exactly what Ini_Tampered() keys off. No-op unless protection is on.
Ini_Sync() {
    global INI, FilesProtected
    if (FilesProtected)
        try FileCopy(INI, GuardBackup(INI), true)
}

; True if the on-disk INI no longer byte-matches the trusted backup -- i.e. it was
; edited by something other than the app (the app keeps the two in lockstep via
; Ini_Sync). DPAPI re-encryption makes a *re-derived* compare unreliable, so we
; compare against the byte copy we actually wrote. Missing files are not "tamper".
Ini_Tampered() {
    global INI
    bak := GuardBackup(INI)
    if (!FileExist(INI) || !FileExist(bak))
        return false
    try {
        a := FileRead(INI, "RAW")
        b := FileRead(bak, "RAW")
        return !Ini_BufEqual(a, b)
    }
    return false      ; unreadable -> don't false-positive a revert
}

Ini_BufEqual(a, b) {
    if (a.Size != b.Size)
        return false
    return DllCall("msvcrt\memcmp", "ptr", a, "ptr", b, "uptr", a.Size, "cdecl int") = 0
}

; Add (canDelete=false) or remove (true) the deny-delete protection on the app
; folder, the guarded files, and the backup store. icacls merges/removes a
; single ACE without disturbing the rest of the DACL.
Files_SetDeletable(canDelete) {
    Files_Icacls(A_ScriptDir, canDelete, "folder")     ; block child-delete path
    for p in Files_Guarded()
        if FileExist(p)
            Files_Icacls(p, canDelete, "file")          ; block file-delete path
    dir := GuardDir()
    if DirExist(dir)
        Files_Icacls(dir, canDelete, "store")
}

Files_Icacls(path, canDelete, kind) {
    if (canDelete) {
        tail := (kind = "store") ? '" /remove:d *S-1-1-0 /t /c /q' : '" /remove:d *S-1-1-0'
    } else {
        switch kind {
            case "folder": tail := '" /deny "*S-1-1-0:(DC)"'                    ; delete-child only
            case "store":  tail := '" /deny "*S-1-1-0:(OI)(CI)(DE,DC)" /t /c /q' ; dir + its backups
            default:       tail := '" /deny "*S-1-1-0:(DE)"'           ; the file itself
        }
    }
    try RunWait(A_ComSpec ' /c icacls "' path tail, , "Hide")
}

; Restore-if-missing loop while protection is on. Only FileExist() probes on the
; hot path; real work happens just after a deletion. The INI is rebuilt from the
; live (protective) settings in memory rather than the on-disk backup, so the
; restored copy can never be staler than what's running.
Heal_Tick() {
    global INI
    if (CfgS("Access_AntiKill") != "1")
        return
    restored := false
    for p in Files_Guarded() {
        bak := GuardBackup(p)
        if (p = INI) {
            ; The INI is authoritative in memory; on disk it's just a cache. If it
            ; was deleted OR edited out-of-band (e.g. someone setting AntiKill=0),
            ; rewrite it from the live protective settings -- the tamper never took
            ; effect (the app runs off memory) and now can't survive to next launch.
            if (!FileExist(p)) {
                SaveConfig()
                restored := true
                Audit("files", "ini restored (was deleted)")
            } else if (FileExist(bak) && Ini_Tampered()) {
                SaveConfig()
                restored := true
                Audit("config", "ini reverted (external edit)")
            }
        } else if FileExist(p) {
            if !FileExist(bak) {
                try FileCopy(p, bak, true)      ; back up a file that appeared later (e.g. a fresh profile)
                Files_Icacls(p, false, "file")  ; ...and deny-delete it too (folder deny-DC alone isn't enough)
            }
        } else if FileExist(bak) {
            try FileCopy(bak, p, true)          ; restore exe / profile from backup
            restored := true
            Audit("files", "restored " GuardName(p))
        }
    }
    if (restored)
        Files_SetDeletable(false)               ; re-assert the deny-delete on whatever came back
}

; Runs at startup BEFORE LoadConfig: if the INI was deleted OR edited out-of-band
; while we were off, put the trusted copy back so the app can't boot with
; unprotected (or tampered) settings. No backup (= protection was never on) means
; a genuine first run -> leave it.
Heal_PreRestore() {
    global INI
    bak := GuardBackup(INI)
    if !FileExist(bak)
        return
    if (!FileExist(INI) || Ini_Tampered())
        try FileCopy(bak, INI, true)
}


; ==================================================================
; ===  EXIT  =======================================================
; ==================================================================
OnExitHandler(*) {
    Protect_SignalQuit()    ; first -- so a clean quit can't be resurrected
    Audit("app", "quit")
    UnpinAll()
    DestroyBorder()
    Sec_Stop()
}
