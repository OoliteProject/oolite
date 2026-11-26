"""Real key presses into a console-driven game, for scenarios about player input (T1).

The console drives the game through JS, and there is no JS for "the player pressed 2". A scenario
asserting that a key does what it is bound to do therefore has to press it, the way a keyboard
does, into the game's own window - and read the effect back over the console.

The recipe is the GUI tier's (tests/gui/conftest.py ``GameWindow.press_key`` / ``focus``),
restated rather than imported: that module pulls in pyautogui, its fixtures and its own desktop
lock, and two tiers sharing one helper file is a merge conflict waiting to happen. What carries
over, and why:

* SendInput by SCANCODE, not keybd_event. Oolite's SDL3 build dispatches keys by scancode
  (MyOpenGLView+Input reads ``kbd_event->scancode``), and an event with no scancode never arrives.
* Hold, then release, both long enough to be SAMPLED. The game polls key state once per frame
  rather than queueing keystrokes, so a press released between two polls is never seen; and a key
  must be seen up again before the next press or it reads as auto-repeat.
* The window must own the foreground: synthetic input goes to the focused window, not to the one
  you meant. SetForegroundWindow alone is refused from a background process, so the input queues
  are attached for the call, as G1 does.

Windows only. This takes the foreground, so the component tier runs alone on the desktop, one
scenario at a time (see the ``world`` fixture in conftest.py). Like console.py
it knows nothing of Gherkin; the vocabulary lives in steps/tutorial_steps.py.
"""

import ctypes
import os
import sys
import time

IS_WINDOWS = sys.platform == "win32" or os.name == "nt"

INPUT_KEYBOARD = 1
KEYEVENTF_EXTENDEDKEY = 0x0001
KEYEVENTF_KEYUP = 0x0002
KEYEVENTF_SCANCODE = 0x0008
MAPVK_VK_TO_VSC = 0
SW_RESTORE = 9

# The keys the tutorial walkthrough presses, by the name a step uses. The bindings they reach are
# Resources/Config/keyconfig2.plist's defaults: 1-4 the four views, v the external view, n
# activate equipment (the tutorial's "next"), b equipment mode (its "skip lesson"), w/s speed,
# f5-f8 the status, chart, system data and market screens.
VK_CODES = {
    "1": 0x31,
    "2": 0x32,
    "3": 0x33,
    "4": 0x34,
    "b": 0x42,
    "n": 0x4E,
    "s": 0x53,
    "v": 0x56,
    "w": 0x57,
    "enter": 0x0D,
    "space": 0x20,
    "f5": 0x74,
    "f6": 0x75,
    "f7": 0x76,
    "f8": 0x77,
}

# Keys whose scancode is only unambiguous with KEYEVENTF_EXTENDEDKEY set: the arrow and
# navigation cluster shares scancodes with the numeric keypad. None of VK_CODES is in it today;
# the set is here so a key added later gets the right answer without anyone remembering to ask.
EXTENDED_VK_CODES = frozenset({0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x2D, 0x2E})

# Longer than the GUI tier's 0.15 s / 0.25 s, and measured, not padded. That tier parks Mesa's
# opengl32.dll and runs on the desktop's GL; this one renders on the llvmpipe that conftest.py
# stages, and in the tutorial's flight scenes that draws 6-9 frames a second (a frame callback
# counted over a minute of lesson 1). At ~140 ms a frame a 0.15 s press can fall between two key
# polls, and did: the first T1 run lost an "n" at lesson 1 step 1. 0.4 s is about three frames
# down and three up, so each press is sampled down and then seen released before the next.
KEY_HOLD_SECONDS = float(os.environ.get("OO_COMPONENT_KEY_HOLD", "0.4"))
KEY_RELEASE_SECONDS = float(os.environ.get("OO_COMPONENT_KEY_RELEASE", "0.4"))

FOCUS_TIMEOUT_SECONDS = 15
WINDOW_TIMEOUT_SECONDS = 30


class KeyboardError(RuntimeError):
    """A key could not be delivered: no window, no foreground, or SendInput refused it."""


def _win32():
    from ctypes import wintypes

    user32 = ctypes.WinDLL("user32", use_last_error=True)
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

    # Undeclared, ctypes passes an HWND as a 32-bit int and truncates it on win64.
    enum_proc = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    user32.EnumWindows.argtypes = [enum_proc, wintypes.LPARAM]
    user32.EnumWindows.restype = wintypes.BOOL
    user32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
    user32.GetWindowThreadProcessId.restype = wintypes.DWORD
    for name in ("IsWindowVisible", "IsWindow", "BringWindowToTop", "SetForegroundWindow"):
        getattr(user32, name).argtypes = [wintypes.HWND]
        getattr(user32, name).restype = wintypes.BOOL
    user32.SetActiveWindow.argtypes = [wintypes.HWND]
    user32.SetActiveWindow.restype = wintypes.HWND
    user32.ShowWindow.argtypes = [wintypes.HWND, ctypes.c_int]
    user32.ShowWindow.restype = wintypes.BOOL
    user32.GetForegroundWindow.argtypes = []
    user32.GetForegroundWindow.restype = wintypes.HWND
    user32.AttachThreadInput.argtypes = [wintypes.DWORD, wintypes.DWORD, wintypes.BOOL]
    user32.AttachThreadInput.restype = wintypes.BOOL
    user32.MapVirtualKeyW.argtypes = [wintypes.UINT, wintypes.UINT]
    user32.MapVirtualKeyW.restype = wintypes.UINT
    kernel32.GetCurrentThreadId.argtypes = []
    kernel32.GetCurrentThreadId.restype = wintypes.DWORD

    class KEYBDINPUT(ctypes.Structure):
        # dwExtraInfo is a ULONG_PTR: 8 bytes on win64, and declaring it DWORD shifts the layout
        # so SendInput rejects or silently drops the event.
        _fields_ = [
            ("wVk", wintypes.WORD),
            ("wScan", wintypes.WORD),
            ("dwFlags", wintypes.DWORD),
            ("time", wintypes.DWORD),
            ("dwExtraInfo", ctypes.c_size_t),
        ]

    class _INPUTUNION(ctypes.Union):
        # Padded to MOUSEINPUT, the union's largest arm, so sizeof(INPUT) is what SendInput wants.
        _fields_ = [("ki", KEYBDINPUT), ("_pad", ctypes.c_byte * 32)]

    class INPUT(ctypes.Structure):
        _fields_ = [("type", wintypes.DWORD), ("u", _INPUTUNION)]

    user32.SendInput.argtypes = [wintypes.UINT, ctypes.POINTER(INPUT), ctypes.c_int]
    user32.SendInput.restype = wintypes.UINT
    return user32, kernel32, enum_proc, KEYBDINPUT, INPUT


class GameKeyboard:
    """The keyboard of one running game, found by its process id."""

    def __init__(self, pid):
        if not IS_WINDOWS:
            raise KeyboardError("real key presses are implemented for Windows only")
        self.pid = int(pid)
        (self._user32, self._kernel32, self._enum_proc,
         self._KEYBDINPUT, self._INPUT) = _win32()
        self.hwnd = None

    def _find_window(self):
        """The game's visible top-level window, waiting for it if it is not up yet.

        Looked up again whenever the handle it had dies: the game re-creates its surface during
        startup, and a handle taken before that is a window nothing draws into.
        """
        from ctypes import wintypes

        deadline = time.time() + WINDOW_TIMEOUT_SECONDS
        while time.time() < deadline:
            found = []

            def visit(hwnd, _lparam):
                owner = wintypes.DWORD()
                self._user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
                if owner.value == self.pid and self._user32.IsWindowVisible(hwnd):
                    found.append(hwnd)
                return True

            self._user32.EnumWindows(self._enum_proc(visit), 0)
            if found:
                return found[0]
            time.sleep(0.5)
        raise KeyboardError(f"no visible window for game pid {self.pid} within "
                            f"{WINDOW_TIMEOUT_SECONDS}s")

    def focus(self):
        """Give the game window the foreground, and verify it, as G1's GameWindow.focus does."""
        if self.hwnd is None or not self._user32.IsWindow(self.hwnd):
            self.hwnd = self._find_window()
        if self._user32.GetForegroundWindow() == self.hwnd:
            return
        self._user32.ShowWindow(self.hwnd, SW_RESTORE)
        target_thread = self._user32.GetWindowThreadProcessId(self.hwnd, None)
        deadline = time.time() + FOCUS_TIMEOUT_SECONDS
        while time.time() < deadline:
            foreground = self._user32.GetForegroundWindow()
            if foreground == self.hwnd:
                time.sleep(0.2)
                return
            our_thread = self._kernel32.GetCurrentThreadId()
            fg_thread = (self._user32.GetWindowThreadProcessId(foreground, None)
                         if foreground else 0)
            attached = []
            for thread in (fg_thread, target_thread):
                if (thread and thread != our_thread
                        and self._user32.AttachThreadInput(our_thread, thread, True)):
                    attached.append(thread)
            try:
                self._user32.BringWindowToTop(self.hwnd)
                self._user32.SetForegroundWindow(self.hwnd)
                self._user32.SetActiveWindow(self.hwnd)
            finally:
                for thread in attached:
                    self._user32.AttachThreadInput(our_thread, thread, False)
            time.sleep(0.3)
        raise KeyboardError(
            f"could not give the game window (hwnd {self.hwnd}) the foreground within "
            f"{FOCUS_TIMEOUT_SECONDS}s; synthetic keys would go to another window"
        )

    def _scan(self, key):
        vk = VK_CODES.get(key.lower())
        if vk is None:
            raise KeyError(f"{key!r} is not in VK_CODES; add it there rather than passing a raw "
                           "code, so the extended-key question is answered in one place")
        scan = self._user32.MapVirtualKeyW(vk, MAPVK_VK_TO_VSC)
        if not scan:
            raise KeyboardError(f"MapVirtualKeyW(vk 0x{vk:02X}) has no scancode")
        flags = KEYEVENTF_SCANCODE
        if vk in EXTENDED_VK_CODES:
            flags |= KEYEVENTF_EXTENDEDKEY
        return scan, flags

    def _send(self, scan, flags):
        # SendInput returns how many events it inserted; 0 is a refusal (UIPI, a hook, a bad
        # structure) that is otherwise silent and would look exactly like a game bug.
        item = self._INPUT()
        item.type = INPUT_KEYBOARD
        item.u.ki = self._KEYBDINPUT(wVk=0, wScan=scan, dwFlags=flags, time=0, dwExtraInfo=0)
        if self._user32.SendInput(1, ctypes.byref(item), ctypes.sizeof(self._INPUT)) != 1:
            raise KeyboardError(f"SendInput refused scancode 0x{scan:02X} "
                                f"(error {ctypes.get_last_error()})")

    def press(self, key, hold=None, release=None):
        """Press and release one key, held long enough for a frame to sample it."""
        scan, flags = self._scan(key)
        self.focus()
        self._send(scan, flags)
        time.sleep(KEY_HOLD_SECONDS if hold is None else hold)
        self._send(scan, flags | KEYEVENTF_KEYUP)
        time.sleep(KEY_RELEASE_SECONDS if release is None else release)

    def hold_until(self, key, condition, timeout):
        """Hold a key down until ``condition()`` is true (e.g. "s" until the ship has stopped).

        Returns whether the condition was met. The key is always released.
        """
        scan, flags = self._scan(key)
        self.focus()
        self._send(scan, flags)
        try:
            deadline = time.time() + timeout
            while time.time() < deadline:
                if condition():
                    return True
                time.sleep(0.25)
            return condition()
        finally:
            self._send(scan, flags | KEYEVENTF_KEYUP)
            time.sleep(KEY_RELEASE_SECONDS)
