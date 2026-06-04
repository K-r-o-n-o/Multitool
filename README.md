# MultiTool

A small Windows tray app that bundles a handful of everyday tools behind
reassignable hotkeys, all configured from one settings window (tray → Settings).
Settings persist to `multitool.ini` beside the executable.

- **Translator** — translate the selected text (Google free, or DeepL with a key)
- **Layout Fix** — fix text typed in the wrong keyboard layout (EN ⇄ RU same-key)
- **Typo Fix** — correct the selection via LanguageTool
- **Rainbow border** — rotating screen-edge overlay, with an optional soft inner **glow** (configurable reach + strength)
- **For Devs** — git add/commit/push a folder, and **publish GitHub releases**
  from the app (tag, notes, file attachments — via the GitHub CLI or a token)
- **Pin-on-top** — make any window click-through and always-on-top
- **Behavioral sentinel** — *optional* screen lock from keystroke + mouse + window-switch biometrics (see below)
- **Access hardening** — Windows Hello gate for sensitive actions, possession-factor auto-lock (USB / Bluetooth), encrypted secrets, clipboard auto-clear, audit log
- **Custom hotkeys** — 5 user-defined Run/Paste slots

## Install & run

Download `multitool.exe` from the [latest release][releases] and run it. It lives
in the tray; right-click → **Settings** to configure, or **Exit** to quit.

**Everything above works with no dependencies** — except the keystroke sentinel,
which is an optional Python-based extra.

Hotkey notation: `^` Ctrl · `!` Alt · `#` Win · `+` Shift.

| Default | Action |
|---------|--------|
| `Ctrl+Alt+T` / `C` / `R` | translate selection → popup / copy / replace in place |
| `Ctrl+Win+L` / `K` | layout-fix → copy / replace |
| `Ctrl+Alt+F` | fix typos in selection |
| `Ctrl+Win+B` | toggle rainbow border |
| `Ctrl+Win+D` | git add/commit/push |
| `Win+T` / `Win+C` | pin window / unpin all |
| `Ctrl+Win+S` | open Settings |
| `Ctrl+Win+Q` | quit MultiTool |

Every hotkey is reassignable in Settings; Save is blocked if two share a key.

## Behavioral sentinel (optional)

A multi-signal biometric screen lock. It learns *how you use the machine* across
three independent channels — **keystroke** timing, **mouse** dynamics (speed, path
straightness, click/scroll cadence), and **window-switching** rhythm — and locks
the workstation when any channel stops looking like you. It records only numeric
aggregates: never which keys or text, never mouse coordinates, never window titles
or which apps. It is a **learning project / mild deterrent, not real security** —
for that, use BitLocker + Windows Hello + Dynamic Lock.

This is the **only** feature that needs Python. If you don't set it up, the
Security tab simply shows "sentinel.py not found / needs Python" and the rest of
MultiTool is unaffected.

**Setup**

1. Put `sentinel.py` and `requirements.txt` in the **same folder** as
   `multitool.exe` (they ship as assets on each release).
2. Install [Python] 3.11–3.13 (3.14 has no prebuilt scientific wheels yet).
3. Install the dependencies — either is fine:
   - **Global:** `pip install -r requirements.txt`
   - **Virtual env beside the app (auto-detected):**
     ```
     python -m venv .venv
     .venv\Scripts\pip install -r requirements.txt
     ```
     MultiTool automatically uses a `.venv` (or `venv`) sitting next to it; no
     path to configure. Otherwise set **Settings → Security → Python executable**
     to your interpreter.
4. **Settings → Security (Sentinel) → Enroll typing profile…**, then use the PC
   normally — type, move the mouse, switch between apps — for a few minutes. This
   trains a `sentinel_profile.skops` with whichever channels saw enough activity.
5. Tick **Enable** (and optionally bind a toggle hotkey).

Dependencies: `numpy`, `scikit-learn`, `skops`, `pynput` (mouse capture is part of
pynput; window-switching uses stdlib `ctypes`). The profile is stored with skops
(not pickle), so loading it never executes code. Global input capture can look
like a keylogger to antivirus — that's expected for this kind of tool; the worst
it does is lock your screen, which you unlock with your password.

> Upgrading from an older build re-trains the model format (profile **v3**), so
> **re-enroll once** — the old profile is refused automatically.

## Access hardening

All under **Settings → Security → Access** (no Python needed — these are native):

- **Windows Hello gate** — require fingerprint/PIN (whatever you've enrolled in
  Windows) before opening Settings, turning the sentinel off, publishing a
  release, or quitting MultiTool. If Hello isn't set up it's skipped, so it can
  never lock you out of your own app.
- **Lock when away (possession factor)** — pick **USB**, **Bluetooth**, or **Both**
  and name a token (a USB key's `VID_xxxx&PID_xxxx` or device name, and/or a paired
  Bluetooth device's name/MAC). MultiTool polls every few seconds and locks the
  workstation once your token has been gone for the grace period. Tolerant by
  design — present if *any* token is present, and a detection glitch never locks.
- **Resist being killed / deleted / tampered** — opt-in (off by default). Puts a
  deny-terminate ACL on the process so non-elevated `taskkill` / Task Manager
  "End task" / `Stop-Process` get Access Denied, and a hidden watchdog relaunches
  the app if it's killed. It also **deny-deletes** `multitool.exe`,
  `multitool.ini`, and the sentinel profile (plus the folder's delete-child
  right — both are needed, since a file-only deny is bypassed via the folder),
  keeps hidden backups, and **self-heals**: anything deleted is restored — at
  runtime, by the watchdog (even the exe, before relaunch), and at startup before
  the ini is read (so a wiped ini can't boot the app unprotected). It also
  **reverts out-of-band edits to `multitool.ini`**: settings live in memory while
  the app runs (an on-disk edit has no live effect), and any change that doesn't
  come from the app is rewritten from the trusted state within seconds and
  discarded at the next startup — so nobody disables protection by editing
  settings on disk. While it's on you can't casually delete files in the app's
  folder, and **hand-editing the ini is reverted** (change settings in-app), so
  **turn it off to uninstall** or to edit the ini by hand. Honest limits: this
  stops a casual / non-admin actor, but an **admin** can take ownership and change
  anything, a determined attacker who also edits the hidden backup wins, and a
  self-resurrecting process pair is exactly what **antivirus** flags — expect
  warnings. There is no way to require a Hello prompt *before* a file read/write
  (the filesystem doesn't ask user-mode apps); that would need a kernel driver.
  The tray **Exit** always works (and, if a Hello quit-gate is set, is itself
  gated).
- **Encrypted secrets** — the GitHub token and DeepL key are stored in
  `multitool.ini` as DPAPI ciphertext (`dpapi:…`), decryptable only by your
  Windows account on this PC, and masked on screen.
- **Clipboard auto-clear** (General tab) — wipes a translate/layout copy after
  *N* seconds, but only if you haven't copied something else since.
- **Audit log** (General tab) — appends security events (settings saved, sentinel
  on/off, release published, Hello prompts, possession locks, quit) to
  `multitool_audit.log`. No secrets are ever logged.

## For Devs: git push & releases

Set a project folder, branch, and (optionally) a repo URL in **Settings → For
Devs**. `Ctrl+Win+D` commits and pushes. **Create a release…** opens a dialog
(tag, title, notes, file attachments, draft/pre-release) and publishes via the
**GitHub CLI** if it's logged in (`gh auth login`), otherwise via a **GitHub
token** you set on that tab.

## Building from source

Requires [AutoHotkey v2]. Run `multitool.ahk` directly, or compile:

```
"C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe" ^
  /in multitool.ahk /out multitool.exe ^
  /base "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
```

## For maintainers: releasing

Attach **`sentinel.py`** and **`requirements.txt`** to every GitHub release
alongside `multitool.exe`, so users who want the sentinel can drop them next to
the app. (The in-app auto-updater only swaps `multitool.exe`; it does not update
`sentinel.py`, so ship sentinel changes as a fresh release.) Bump `APP_VERSION`
in `multitool.ahk` before tagging.

[releases]: https://github.com/K-r-o-n-o/Multitool/releases
[Python]: https://www.python.org/downloads/
[AutoHotkey v2]: https://www.autohotkey.com/
