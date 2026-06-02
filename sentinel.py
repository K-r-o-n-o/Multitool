#!/usr/bin/env python3
"""
Behavioral Sentinel  —  multi-signal biometric screen lock (LEARNING PROJECT)
=============================================================================

Watches *how* you use the machine -- typing rhythm, mouse dynamics, and the
cadence of switching between apps -- and locks the workstation when the
behaviour stops looking like yours. Two modes:

    python sentinel.py enroll     # learn your behaviour, train the models
    python sentinel.py monitor    # watch continuously, lock on anomaly

THREE INDEPENDENT CHANNELS
--------------------------
  * keystroke : key-hold / between-key timing
  * mouse     : move speed, path straightness, click/scroll cadence
  * window    : how often and how widely you switch foreground apps
Each channel trains its own anomaly model and keeps its own running suspicion;
the screen locks when ANY channel stays anomalous long enough. A channel with
too little enrollment data is simply skipped.

PRIVACY BY DESIGN
-----------------
NEVER recorded: which keys you press, any text, mouse coordinates, window
titles, or which apps you use. Key/button identity and the pixel path exist for
a fraction of a second in memory only to measure *timing and geometry*; the
foreground app is reduced to an opaque per-session token only to count switches
and variety. Only numeric aggregates are ever modelled or saved.

HONEST LIMITATIONS
------------------
* A learning tool / mild deterrent, NOT real security. An attacker who controls
  your logged-in session can just kill this process. Real protection on Windows
  = BitLocker + Windows Hello + Dynamic Lock.
* Global input capture looks like a keylogger to antivirus; it may warn. The
  worst this does is lock your screen -- you unlock with your normal password.

Dependencies:  pip install scikit-learn numpy pynput
"""

import sys
import os
import time
import math
import platform
import threading
from collections import deque

import numpy as np

# ----------------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------------
PROFILE_VERSION = 3    # was 2: added mouse + window-switch channels

# keystroke channel
WINDOW = 30            # keystrokes per analysis window
STRIDE = 10            # emit a new feature vector every STRIDE keystrokes
IDLE_GAP_MS = 1500     # a longer pause restarts the window (don't straddle breaks)
CLAMP_MS    = 1000     # cap a single gap so one pause can't dominate a window

# mouse channel
MOUSE_WINDOW = 60      # mouse-move samples per window
MOUSE_STRIDE = 20      # emit every N moves
MOUSE_IDLE_MS = 1500   # a longer pause between moves starts a fresh segment
MOUSE_CLAMP_MS = 1000

# window-switch channel. A slow signal: switches happen seconds-to-minutes
# apart, so it only trains if enrollment sees plenty of app-switching; otherwise
# too few windows are collected and the channel is simply skipped.
WIN_WINDOW = 8         # app switches per window
WIN_STRIDE = 2
WIN_POLL_MS = 350      # how often the foreground app is polled
WIN_DWELL_CLAMP_S = 120.0

ENROLL_WINDOWS = 200   # keystroke windows that complete enrollment (~a few min)
ENROLL_CAP_SEC = 600   # ...but never run enrollment longer than this
MIN_CH_WINDOWS = 25    # keystroke/mouse: windows needed to train a channel
MIN_WINDOW_CH  = 18    # the slow window-switch channel gets a lower bar

# Anomaly decision (per channel). Counting strictly-consecutive anomalies is
# brittle -- one normal window resets it -- so we keep an exponentially-weighted
# moving average of the per-window anomaly flag. It climbs while anomalies
# dominate and decays slowly otherwise, tolerating the odd normal window during
# an attack while still needing sustained anomalies (~6 from clean) to fire.
EWMA_ALPHA   = 0.15
LOCK_EWMA    = 0.60
WARMUP       = 4       # windows after (re)arming before a channel can lock
ANOMALY_PCTL = 1       # per-window threshold = this percentile of genuine scores

COOLDOWN_SEC = 30      # after a lock, wait before arming again
MODEL_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sentinel_profile.skops")

CHANNELS = ("keystroke", "mouse", "window")


# ============================================================================
# Feature extraction  (aggregates only -- never identity, text, coords, titles)
# ============================================================================
class FeatureExtractor:
    """
    Keystroke channel. Consumes key-down / key-up events and emits a 13-dim
    vector every STRIDE keys, summarising the last WINDOW keys:
        dwell:   mean, std, median, 90th-pct, coeff-of-variation
        flight:  mean, std, median, 90th-pct, coeff-of-variation
        rhythm:  keys/sec, mean down-to-down latency, flight/dwell ratio
    """

    n_features = 13

    def __init__(self, window=WINDOW, stride=STRIDE):
        self.window = window
        self.stride = stride
        self._down_at = {}                  # transient: key_id -> press timestamp
        self.dwell = deque(maxlen=window)
        self.flight = deque(maxlen=window)
        self.down_down = deque(maxlen=window)
        self.down_times = deque(maxlen=window)
        self._last_up = None
        self._last_down = None
        self._since_emit = 0

    def on_press(self, key_id, t_ms):
        if key_id in self._down_at:
            return  # auto-repeat; ignore
        if self._last_down is not None and (t_ms - self._last_down) > IDLE_GAP_MS:
            self._reset_window()
        self._down_at[key_id] = t_ms
        if self._last_up is not None:
            self.flight.append(min(max(t_ms - self._last_up, 0.0), CLAMP_MS))
        if self._last_down is not None:
            self.down_down.append(min(max(t_ms - self._last_down, 0.0), CLAMP_MS))
        self._last_down = t_ms
        self.down_times.append(t_ms)

    def _reset_window(self):
        self._down_at.clear()
        self.dwell.clear()
        self.flight.clear()
        self.down_down.clear()
        self.down_times.clear()
        self._last_up = None
        self._last_down = None
        self._since_emit = 0

    def on_release(self, key_id, t_ms):
        start = self._down_at.pop(key_id, None)  # identity discarded right here
        if start is None:
            return None
        self.dwell.append(max(t_ms - start, 0.0))
        self._last_up = t_ms
        self._since_emit += 1
        if len(self.dwell) >= self.window and self._since_emit >= self.stride:
            self._since_emit = 0
            return self._vector()
        return None

    def _vector(self):
        d = np.fromiter(self.dwell, dtype=float)
        f = np.fromiter(self.flight, dtype=float)
        dd = np.fromiter(self.down_down, dtype=float)
        if f.size == 0:
            f = np.array([0.0])
        if dd.size == 0:
            dd = np.array([0.0])
        span = (self.down_times[-1] - self.down_times[0]) / 1000.0
        kps = (len(self.down_times) / span) if span > 0 else 0.0
        d_mean, f_mean = float(d.mean()), float(f.mean())
        return [
            d_mean, float(d.std()), float(np.median(d)),
            float(np.percentile(d, 90)), _cv(d),
            f_mean, float(f.std()), float(np.median(f)),
            float(np.percentile(f, 90)), _cv(f),
            kps, float(dd.mean()),
            (f_mean / d_mean) if d_mean > 1e-6 else 0.0,
        ]


class MouseFeatureExtractor:
    """
    Mouse channel. Consumes move / click / scroll events (positions are used
    only to derive speed and turning angle, never stored) and emits a 10-dim
    vector every MOUSE_STRIDE moves over the last MOUSE_WINDOW samples:
        speed:   mean, std, median (px/ms)
        path:    mean turning angle, straightness (net/gross distance)
        timing:  mean move gap, moves/sec
        buttons: clicks/sec, mean click dwell, scrolls/sec
    """

    n_features = 10

    def __init__(self, window=MOUSE_WINDOW, stride=MOUSE_STRIDE):
        self.window = window
        self.stride = stride
        self.speed = deque(maxlen=window)
        self.angle = deque(maxlen=window)
        self.gap = deque(maxlen=window)
        self.dx = deque(maxlen=window)        # per-segment displacement components
        self.dy = deque(maxlen=window)
        self.dist = deque(maxlen=window)
        self.move_times = deque(maxlen=window)
        self.click_dwell = deque(maxlen=window)
        self.click_times = deque(maxlen=window)
        self.scroll_times = deque(maxlen=window)
        self._last = None                     # (x, y, t) of previous move
        self._last_vec = None                 # previous (dx, dy) for turning angle
        self._down_at = {}                    # button -> press time
        self._since_emit = 0

    def on_move(self, x, y, t_ms):
        if self._last is None:
            self._last = (x, y, t_ms)
            return None
        lx, ly, lt = self._last
        dt = t_ms - lt
        if dt > MOUSE_IDLE_MS or dt <= 0:
            # paused / stepped away -> start a fresh segment, no feature from gap
            self._last = (x, y, t_ms)
            self._last_vec = None
            return None
        ddx, ddy = x - lx, y - ly
        dist = math.hypot(ddx, ddy)
        self.speed.append(min(dist / dt, 50.0))      # px/ms, clamped
        self.gap.append(min(dt, MOUSE_CLAMP_MS))
        self.dist.append(dist)
        self.dx.append(ddx)
        self.dy.append(ddy)
        self.move_times.append(t_ms)
        if self._last_vec is not None and dist > 1.0:
            pvx, pvy = self._last_vec
            pmag = math.hypot(pvx, pvy)
            if pmag > 1.0:
                cosang = (ddx * pvx + ddy * pvy) / (dist * pmag)
                cosang = max(-1.0, min(1.0, cosang))
                self.angle.append(math.acos(cosang))   # radians, 0=straight
        self._last_vec = (ddx, ddy)
        self._last = (x, y, t_ms)
        self._since_emit += 1
        if len(self.speed) >= self.window and self._since_emit >= self.stride:
            self._since_emit = 0
            return self._vector()
        return None

    def on_click(self, button, pressed, t_ms):
        if pressed:
            self._down_at[button] = t_ms
            self.click_times.append(t_ms)
        else:
            start = self._down_at.pop(button, None)
            if start is not None:
                self.click_dwell.append(min(max(t_ms - start, 0.0), MOUSE_CLAMP_MS))

    def on_scroll(self, t_ms):
        self.scroll_times.append(t_ms)

    def _vector(self):
        sp = np.fromiter(self.speed, dtype=float) if self.speed else np.array([0.0])
        ang = np.fromiter(self.angle, dtype=float) if self.angle else np.array([0.0])
        gap = np.fromiter(self.gap, dtype=float) if self.gap else np.array([0.0])
        gross = float(np.sum(self.dist)) if self.dist else 0.0
        net = math.hypot(sum(self.dx), sum(self.dy)) if self.dx else 0.0
        straight = (net / gross) if gross > 1e-6 else 0.0
        span = (self.move_times[-1] - self.move_times[0]) / 1000.0 if len(self.move_times) > 1 else 0.0
        mps = (len(self.move_times) / span) if span > 0 else 0.0
        clk = _rate(self.click_times)
        scr = _rate(self.scroll_times)
        dwell = float(np.mean(self.click_dwell)) if self.click_dwell else 0.0
        return [
            float(sp.mean()), float(sp.std()), float(np.median(sp)),
            float(ang.mean()), straight,
            float(gap.mean()), mps,
            clk, dwell, scr,
        ]


class WindowFeatureExtractor:
    """
    Window-switch channel. Consumes foreground-app *changes* (an opaque token +
    timestamp) and emits a 7-dim vector every WIN_STRIDE switches over the last
    WIN_WINDOW switches:
        rate:    switches/sec
        dwell:   mean, std, median seconds spent per app
        variety: unique-app fraction, switching entropy, revisit fraction
    """

    n_features = 7

    def __init__(self, window=WIN_WINDOW, stride=WIN_STRIDE):
        self.window = window
        self.stride = stride
        self.dwell = deque(maxlen=window)
        self.apps = deque(maxlen=window)
        self.switch_times = deque(maxlen=window)
        self._last_app = None
        self._last_t = None
        self._since_emit = 0

    def on_switch(self, app_token, t_ms):
        if app_token == self._last_app:
            return None
        if self._last_t is not None:
            dwell_s = min((t_ms - self._last_t) / 1000.0, WIN_DWELL_CLAMP_S)
            self.dwell.append(max(dwell_s, 0.0))
        self.apps.append(app_token)
        self.switch_times.append(t_ms)
        self._last_app = app_token
        self._last_t = t_ms
        self._since_emit += 1
        if len(self.dwell) >= self.window and self._since_emit >= self.stride:
            self._since_emit = 0
            return self._vector()
        return None

    def _vector(self):
        dw = np.fromiter(self.dwell, dtype=float) if self.dwell else np.array([0.0])
        span = (self.switch_times[-1] - self.switch_times[0]) / 1000.0 if len(self.switch_times) > 1 else 0.0
        rate = (len(self.switch_times) / span) if span > 0 else 0.0
        apps = list(self.apps)
        n = len(apps) or 1
        counts = {}
        for a in apps:
            counts[a] = counts.get(a, 0) + 1
        uniq = len(counts) / n
        ent = 0.0
        for c in counts.values():
            p = c / n
            ent -= p * math.log(p, 2)
        max_ent = math.log(len(counts), 2) if len(counts) > 1 else 1.0
        ent_norm = ent / max_ent if max_ent > 0 else 0.0
        revisit = 1.0 - (len(counts) / n)
        return [
            rate,
            float(dw.mean()), float(dw.std()), float(np.median(dw)),
            uniq, ent_norm, revisit,
        ]


def _cv(xs):
    """Coefficient of variation (std / mean); 0 when the mean is ~0."""
    m = float(xs.mean())
    return float(xs.std() / m) if m > 1e-6 else 0.0


def _rate(times):
    """Events per second across a deque of timestamps (ms)."""
    if len(times) < 2:
        return 0.0
    span = (times[-1] - times[0]) / 1000.0
    return (len(times) / span) if span > 0 else 0.0


# ----------------------------------------------------------------------------
# Locking the workstation
# ----------------------------------------------------------------------------
def lock_workstation():
    """Programmatic equivalent of Win+L on Windows; best-effort elsewhere."""
    sysname = platform.system()
    if sysname == "Windows":
        import ctypes
        ctypes.windll.user32.LockWorkStation()
    elif sysname == "Darwin":
        os.system("pmset displaysleepnow")
    elif sysname == "Linux":
        for cmd in ("loginctl lock-session", "xdg-screensaver lock",
                    "gnome-screensaver-command -l"):
            if os.system(cmd + " 2>/dev/null") == 0:
                break
    else:
        print("[lock] (no locker for this OS — would lock here)")


# ----------------------------------------------------------------------------
# Listeners / watchers (pynput keyboard+mouse, ctypes foreground-window poll)
# ----------------------------------------------------------------------------
def run_keyboard_listener(extractor, on_vector):
    from pynput import keyboard

    def key_token(key):
        return getattr(key, "vk", None) or str(key)   # transient id, never stored

    def on_press(key):
        extractor.on_press(key_token(key), time.perf_counter() * 1000.0)

    def on_release(key):
        vec = extractor.on_release(key_token(key), time.perf_counter() * 1000.0)
        if vec is not None:
            on_vector(vec)

    listener = keyboard.Listener(on_press=on_press, on_release=on_release)
    listener.start()
    return listener


def run_mouse_listener(extractor, on_vector):
    from pynput import mouse

    def on_move(x, y, *_):
        vec = extractor.on_move(x, y, time.perf_counter() * 1000.0)
        if vec is not None:
            on_vector(vec)

    def on_click(x, y, button, pressed):
        extractor.on_click(button, pressed, time.perf_counter() * 1000.0)

    def on_scroll(x, y, dx, dy):
        extractor.on_scroll(time.perf_counter() * 1000.0)

    listener = mouse.Listener(on_move=on_move, on_click=on_click, on_scroll=on_scroll)
    listener.start()
    return listener


def _foreground_app_token():
    """Opaque, per-session token for the foreground app's executable name. Returns
    None off-Windows or on failure. Never returns or stores the name itself."""
    if platform.system() != "Windows":
        return None
    import ctypes
    from ctypes import wintypes
    user32, kernel32 = ctypes.windll.user32, ctypes.windll.kernel32
    hwnd = user32.GetForegroundWindow()
    if not hwnd:
        return None
    pid = wintypes.DWORD()
    user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
    if not pid.value:
        return None
    h = kernel32.OpenProcess(0x1000, False, pid.value)   # QUERY_LIMITED_INFORMATION
    if not h:
        return None
    try:
        buf = ctypes.create_unicode_buffer(260)
        size = wintypes.DWORD(260)
        if kernel32.QueryFullProcessImageNameW(h, 0, buf, ctypes.byref(size)):
            return hash(os.path.basename(buf.value).lower()) & 0xffffffff
    finally:
        kernel32.CloseHandle(h)
    return None


class WindowWatcher:
    """Background thread that polls the foreground app and feeds switches to the
    window extractor. Stop with .stop()."""

    def __init__(self, extractor, on_vector):
        self.extractor = extractor
        self.on_vector = on_vector
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._run, daemon=True)

    def start(self):
        self._thread.start()
        return self

    def stop(self):
        self._stop.set()

    def _run(self):
        while not self._stop.is_set():
            tok = _foreground_app_token()
            if tok is not None:
                vec = self.extractor.on_switch(tok, time.perf_counter() * 1000.0)
                if vec is not None:
                    self.on_vector(vec)
            self._stop.wait(WIN_POLL_MS / 1000.0)


# ============================================================================
# Model core  (no I/O -- unit-testable directly)
# ============================================================================
def train_channel(X, min_windows=MIN_CH_WINDOWS):
    """Fit one channel's anomaly model + scaler on genuine windows X and
    calibrate its per-window threshold. Returns the channel-profile dict, or
    None if there isn't enough data to train a meaningful model."""
    X = np.asarray(X, dtype=float)
    if X.ndim != 2 or X.shape[0] < min_windows:
        return None
    from sklearn.ensemble import IsolationForest
    from sklearn.preprocessing import RobustScaler

    # RobustScaler centres on the median and scales by the IQR, so a few odd
    # windows during enrollment don't skew the normalisation.
    scaler = RobustScaler().fit(X)
    Xs = scaler.transform(X)
    model = IsolationForest(n_estimators=200, contamination=0.02,
                            random_state=0).fit(Xs)
    scores = model.decision_function(Xs)
    threshold = float(np.percentile(scores, ANOMALY_PCTL))
    return {"model": model, "scaler": scaler, "threshold": threshold,
            "n_features": int(X.shape[1])}


def score_channel(chan, vec):
    """Return (decision_score, is_anomalous) for one feature vector."""
    Xs = chan["scaler"].transform(np.asarray([vec], dtype=float))
    score = float(chan["model"].decision_function(Xs)[0])
    return score, (score < chan["threshold"])


class AnomalyTracker:
    """Leaky EWMA of the per-window anomaly flag. update() returns True once the
    average has stayed high long enough that a lock should fire."""

    def __init__(self, alpha=EWMA_ALPHA, lock_level=LOCK_EWMA, warmup=WARMUP):
        self.alpha = alpha
        self.lock_level = lock_level
        self.warmup = warmup
        self.ewma = 0.0
        self.seen = 0

    def update(self, anomalous):
        self.ewma = self.alpha * (1.0 if anomalous else 0.0) \
            + (1.0 - self.alpha) * self.ewma
        self.seen += 1
        return self.seen >= self.warmup and self.ewma >= self.lock_level

    def reset(self):
        self.ewma = 0.0
        self.seen = 0


def _make_extractors():
    return {"keystroke": FeatureExtractor(),
            "mouse": MouseFeatureExtractor(),
            "window": WindowFeatureExtractor()}


# ----------------------------------------------------------------------------
# Enrollment
# ----------------------------------------------------------------------------
def enroll():
    print("=" * 64)
    print(" ENROLLMENT — learning your behaviour")
    print("=" * 64)
    print("Use the machine normally: type, move the mouse, switch between apps.")
    print(f"Finishes after {ENROLL_WINDOWS} typing windows (or {ENROLL_CAP_SEC//60} min).")
    print("Only numeric timing/geometry is measured — never text, keys, or apps.\n")

    collected = {c: [] for c in CHANNELS}
    extractors = _make_extractors()

    def collector(name):
        def _on(vec):
            collected[name].append(vec)
        return _on

    listeners = [
        run_keyboard_listener(extractors["keystroke"], collector("keystroke")),
        run_mouse_listener(extractors["mouse"], collector("mouse")),
    ]
    watcher = WindowWatcher(extractors["window"], collector("window")).start()

    start = time.time()
    try:
        while (len(collected["keystroke"]) < ENROLL_WINDOWS
               and time.time() - start < ENROLL_CAP_SEC):
            k, m, w = (len(collected[c]) for c in CHANNELS)
            bar = "#" * (k * 30 // ENROLL_WINDOWS)
            print(f"\r  [{bar:<30}] keys {k}/{ENROLL_WINDOWS}  mouse {m}  apps {w}   ",
                  end="", flush=True)
            time.sleep(0.2)
    except KeyboardInterrupt:
        print("\nEnrollment cancelled.")
        for ls in listeners:
            ls.stop()
        watcher.stop()
        return
    for ls in listeners:
        ls.stop()
    watcher.stop()

    profile = {"version": PROFILE_VERSION}
    trained = []
    for name in CHANNELS:
        min_w = MIN_WINDOW_CH if name == "window" else MIN_CH_WINDOWS
        chan = train_channel(collected[name], min_w)
        profile[name] = chan
        if chan is not None:
            trained.append(f"{name}({len(collected[name])}w, {chan['n_features']}f)")

    if not trained:
        print("\n\nNot enough data to train any channel. Try again and keep "
              "typing / moving the mouse for longer.")
        return

    import skops.io as sio
    sio.dump(profile, MODEL_PATH)
    print("\n\nTrained channels: " + ", ".join(trained))
    skipped = [c for c in CHANNELS if profile[c] is None]
    if skipped:
        print("Skipped (too little data): " + ", ".join(skipped))
    print(f"Saved to: {MODEL_PATH}")
    print("\nNow run:  python sentinel.py monitor")


# ----------------------------------------------------------------------------
# Monitoring
# ----------------------------------------------------------------------------
def monitor():
    if not os.path.exists(MODEL_PATH):
        print("No profile found. Run 'python sentinel.py enroll' first.")
        return
    # skops.io.load (trusted=False) instantiates only an allow-list of
    # scikit-learn / numpy types, so a tampered profile can't execute code.
    import skops.io as sio
    try:
        profile = sio.load(MODEL_PATH)
    except Exception as e:
        print(f"Could not load profile ({e}).")
        print("Re-enroll a trusted profile with 'python sentinel.py enroll'.")
        return
    if not isinstance(profile, dict) or profile.get("version") != PROFILE_VERSION:
        print("This profile was made by an older sentinel version and is no "
              "longer compatible.\nRe-enroll with 'python sentinel.py enroll'.")
        return

    active = [c for c in CHANNELS if profile.get(c) is not None]
    if not active:
        print("Profile has no usable channels. Re-enroll.")
        return

    print("=" * 64)
    print(" MONITORING — watching " + ", ".join(active))
    print("=" * 64)
    print(f"Locks when any channel's suspicion EWMA crosses {LOCK_EWMA:.2f}.")
    print("Press Ctrl+C to stop.\n")

    extractors = _make_extractors()
    trackers = {c: AnomalyTracker() for c in active}
    state = {"locked_at": 0.0}
    flags = {c: "--" for c in active}
    lock = threading.Lock()

    def handle(name):
        def _on(vec):
            with lock:
                if time.time() - state["locked_at"] < COOLDOWN_SEC:
                    return
                chan = profile[name]
                if len(vec) != chan["n_features"]:
                    return
                score, anomalous = score_channel(chan, vec)
                should_lock = trackers[name].update(anomalous)
                flags[name] = "ANOM" if anomalous else "ok"
                bar = "  ".join(f"{c}:{trackers[c].ewma:.2f}" for c in active)
                print(f"\r  [{bar}]  ({name} {flags[name]})        ",
                      end="", flush=True)
                if should_lock:
                    print(f"\n  >>> {name} mismatch — LOCKING WORKSTATION <<<\n")
                    lock_workstation()
                    for t in trackers.values():
                        t.reset()
                    state["locked_at"] = time.time()
        return _on

    listeners = []
    if "keystroke" in active:
        listeners.append(run_keyboard_listener(extractors["keystroke"], handle("keystroke")))
    if "mouse" in active:
        listeners.append(run_mouse_listener(extractors["mouse"], handle("mouse")))
    watcher = None
    if "window" in active:
        watcher = WindowWatcher(extractors["window"], handle("window")).start()

    try:
        while True:
            time.sleep(0.3)
    except KeyboardInterrupt:
        print("\nStopped.")
        for ls in listeners:
            ls.stop()
        if watcher:
            watcher.stop()


# ----------------------------------------------------------------------------
# Entry point
# ----------------------------------------------------------------------------
def main():
    mode = sys.argv[1].lower() if len(sys.argv) > 1 else ""
    if mode == "enroll":
        enroll()
    elif mode == "monitor":
        monitor()
    else:
        print(__doc__)
        print("Usage:  python sentinel.py [enroll|monitor]")


if __name__ == "__main__":
    main()
