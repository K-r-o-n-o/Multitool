#!/usr/bin/env python3
"""
Keystroke Sentinel  —  behavioral-biometric screen lock (LEARNING PROJECT)
==========================================================================

Watches *how* you type (timing only) and locks the workstation if the rhythm
stops looking like yours. Two modes:

    python sentinel.py enroll     # learn your typing rhythm, train the model
    python sentinel.py monitor    # watch continuously, lock on anomaly

PRIVACY BY DESIGN
-----------------
This program NEVER records which keys you press or any text you type.
The key identity exists only for a fraction of a second in memory, purely to
pair a key-press with its release so it can measure *duration*. Only numeric
timing aggregates are ever stored or modelled. There is no keystroke log.

HONEST LIMITATIONS
------------------
* This is a learning tool / mild deterrent, NOT real security. An attacker who
  controls your logged-in session can just kill this process in Task Manager.
  Real protection on Windows = BitLocker + Windows Hello + Dynamic Lock.
* Global keyboard capture looks like a keylogger to antivirus software; it may
  warn about this program. That is expected for this kind of code.
* The worst it can do is lock your screen — you unlock with your normal password.

Dependencies:  pip install scikit-learn numpy pynput
"""

import sys
import os
import time
import pickle
import platform
import statistics
from collections import deque

import numpy as np

# ----------------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------------
WINDOW = 30           # keystrokes per analysis window
STRIDE = 10           # emit a new feature vector every STRIDE keystrokes
ENROLL_WINDOWS = 200  # how many windows to collect during enrollment (~a few min of typing)
CONSEC_TO_LOCK = 6    # consecutive anomalous windows required before locking
                      # (sliding windows overlap and are autocorrelated, so this
                      #  needs to be fairly high to avoid false locks)
COOLDOWN_SEC = 30     # after a lock, wait before arming again
MODEL_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sentinel_profile.pkl")


# ----------------------------------------------------------------------------
# Feature extraction  (timing only — never stores key identity or text)
# ----------------------------------------------------------------------------
class FeatureExtractor:
    """
    Consumes key-down / key-up events and emits a fixed-length feature vector
    every STRIDE keystrokes, summarising the timing of the last WINDOW keys.

    Feature vector (8 dims), all derived purely from timestamps:
        0 mean dwell        1 std dwell        2 median dwell
        3 mean flight       4 std flight       5 median flight
        6 keys per second   7 mean down-to-down latency
    """

    def __init__(self, window=WINDOW, stride=STRIDE):
        self.window = window
        self.stride = stride
        self._down_at = {}                  # transient: key_id -> press timestamp
        self.dwell = deque(maxlen=window)   # hold durations (ms)
        self.flight = deque(maxlen=window)  # gaps between keys (ms)
        self.down_down = deque(maxlen=window)
        self.down_times = deque(maxlen=window)
        self._last_up = None
        self._last_down = None
        self._since_emit = 0

    def on_press(self, key_id, t_ms):
        # Record press time keyed by identity ONLY to match the later release.
        if key_id in self._down_at:
            return  # auto-repeat; ignore
        self._down_at[key_id] = t_ms
        if self._last_up is not None:
            self.flight.append(max(t_ms - self._last_up, 0.0))
        if self._last_down is not None:
            self.down_down.append(max(t_ms - self._last_down, 0.0))
        self._last_down = t_ms
        self.down_times.append(t_ms)

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
        d = list(self.dwell)
        f = list(self.flight) or [0.0]
        dd = list(self.down_down) or [0.0]
        span = (self.down_times[-1] - self.down_times[0]) / 1000.0
        kps = (len(self.down_times) / span) if span > 0 else 0.0
        return [
            statistics.fmean(d), _std(d), statistics.median(d),
            statistics.fmean(f), _std(f), statistics.median(f),
            kps, statistics.fmean(dd),
        ]


def _std(xs):
    return statistics.pstdev(xs) if len(xs) > 1 else 0.0


# ----------------------------------------------------------------------------
# Locking the workstation
# ----------------------------------------------------------------------------
def lock_workstation():
    """Programmatic equivalent of Win+L on Windows; safe no-op message elsewhere."""
    sysname = platform.system()
    if sysname == "Windows":
        import ctypes
        ctypes.windll.user32.LockWorkStation()
    elif sysname == "Darwin":
        os.system("pmset displaysleepnow")  # macOS: sleep display (then it locks)
    elif sysname == "Linux":
        # try common screen lockers; ignore failures
        for cmd in ("loginctl lock-session", "xdg-screensaver lock",
                    "gnome-screensaver-command -l"):
            if os.system(cmd + " 2>/dev/null") == 0:
                break
    else:
        print("[lock] (no locker for this OS — would lock here)")


# ----------------------------------------------------------------------------
# Keyboard listener glue (pynput)
# ----------------------------------------------------------------------------
def run_listener(extractor, on_vector):
    """
    Start a global keyboard listener. For each key event we pass ONLY a stable
    identity token (so press/release can be paired) and a timestamp. The token
    is used solely inside FeatureExtractor and never stored.
    """
    from pynput import keyboard

    def key_token(key):
        # A hashable id to pair down/up. Not logged, not persisted.
        return getattr(key, "vk", None) or str(key)

    def on_press(key):
        extractor.on_press(key_token(key), time.perf_counter() * 1000.0)

    def on_release(key):
        vec = extractor.on_release(key_token(key), time.perf_counter() * 1000.0)
        if vec is not None:
            on_vector(vec)

    listener = keyboard.Listener(on_press=on_press, on_release=on_release)
    listener.start()
    return listener


# ----------------------------------------------------------------------------
# Enrollment
# ----------------------------------------------------------------------------
def enroll():
    from sklearn.ensemble import IsolationForest
    from sklearn.preprocessing import StandardScaler

    print("=" * 64)
    print(" ENROLLMENT — learning your typing rhythm")
    print("=" * 64)
    print(f"Type naturally (emails, notes, anything) until {ENROLL_WINDOWS} windows")
    print("are collected. Only timing is measured — never the text itself.\n")

    collected = []
    extractor = FeatureExtractor()

    def on_vector(vec):
        collected.append(vec)
        n = len(collected)
        bar = "#" * (n * 30 // ENROLL_WINDOWS)
        print(f"\r  [{bar:<30}] {n}/{ENROLL_WINDOWS} windows", end="", flush=True)

    listener = run_listener(extractor, on_vector)
    try:
        while len(collected) < ENROLL_WINDOWS:
            time.sleep(0.2)
    except KeyboardInterrupt:
        print("\nEnrollment cancelled.")
        listener.stop()
        return
    listener.stop()

    X = np.array(collected)
    scaler = StandardScaler().fit(X)
    Xs = scaler.transform(X)
    model = IsolationForest(n_estimators=200, contamination=0.02, random_state=0).fit(Xs)

    # Calibrate an anomaly threshold from the genuine data itself. A low
    # percentile (conservative) keeps false locks near zero on normal typing.
    scores = model.decision_function(Xs)
    threshold = float(np.percentile(scores, 1))

    with open(MODEL_PATH, "wb") as fh:
        pickle.dump({"model": model, "scaler": scaler, "threshold": threshold,
                     "window": WINDOW, "stride": STRIDE}, fh)

    print(f"\n\nProfile trained on {len(X)} windows.")
    print(f"Anomaly threshold: {threshold:.4f}")
    print(f"Saved to: {MODEL_PATH}")
    print("\nNow run:  python sentinel.py monitor")


# ----------------------------------------------------------------------------
# Monitoring
# ----------------------------------------------------------------------------
def monitor():
    if not os.path.exists(MODEL_PATH):
        print("No profile found. Run 'python sentinel.py enroll' first.")
        return
    with open(MODEL_PATH, "rb") as fh:
        data = pickle.load(fh)
    model, scaler, threshold = data["model"], data["scaler"], data["threshold"]

    print("=" * 64)
    print(" MONITORING — watching typing rhythm")
    print("=" * 64)
    print(f"Locks after {CONSEC_TO_LOCK} consecutive anomalous windows.")
    print("Press Ctrl+C to stop.\n")

    extractor = FeatureExtractor(window=data["window"], stride=data["stride"])
    state = {"consec": 0, "locked_at": 0.0}

    def on_vector(vec):
        # Respect cooldown after a lock so re-login typing doesn't instantly relock.
        if time.time() - state["locked_at"] < COOLDOWN_SEC:
            return
        Xs = scaler.transform(np.array([vec]))
        score = float(model.decision_function(Xs)[0])
        anomalous = score < threshold
        state["consec"] = state["consec"] + 1 if anomalous else 0

        flag = "ANOMALY" if anomalous else "ok"
        meter = "!" * state["consec"]
        print(f"\r  score={score:+.4f}  [{flag:^8}] {meter:<8} "
              f"({state['consec']}/{CONSEC_TO_LOCK})      ", end="", flush=True)

        if state["consec"] >= CONSEC_TO_LOCK:
            print("\n  >>> rhythm mismatch — LOCKING WORKSTATION <<<\n")
            lock_workstation()
            state["consec"] = 0
            state["locked_at"] = time.time()

    listener = run_listener(extractor, on_vector)
    try:
        while True:
            time.sleep(0.3)
    except KeyboardInterrupt:
        print("\nStopped.")
        listener.stop()


# ----------------------------------------------------------------------------
# CLI
# ----------------------------------------------------------------------------
def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode == "enroll":
        enroll()
    elif mode == "monitor":
        monitor()
    else:
        print(__doc__)
        print("Usage: python sentinel.py [enroll|monitor]")


if __name__ == "__main__":
    main()
