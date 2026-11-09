#!/usr/bin/env python3
"""Render an isolated Linux export on X11 and close it through WM_DELETE_WINDOW.

Requires a working DISPLAY and libX11. Autoplay is a rendering fixture only;
the game's separate input suite verifies normal player input.
"""
import argparse
import ctypes as C
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time


class ClientData(C.Union):
    _fields_ = [("b", C.c_char * 20), ("s", C.c_short * 10), ("l", C.c_long * 5)]


class ClientMessage(C.Structure):
    _fields_ = [("type", C.c_int), ("serial", C.c_ulong), ("send_event", C.c_int),
                ("display", C.c_void_p), ("window", C.c_ulong), ("message_type", C.c_ulong),
                ("format", C.c_int), ("data", ClientData)]


class Event(C.Union):
    _fields_ = [("client", ClientMessage), ("pad", C.c_long * 24)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--project", type=Path, help="Optional source-project check with an editor executable")
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    capture = out / "combat.png"
    capture.unlink(missing_ok=True)
    x = C.CDLL("libX11.so.6")
    x.XOpenDisplay.argtypes, x.XOpenDisplay.restype = [C.c_char_p], C.c_void_p
    x.XDefaultRootWindow.argtypes, x.XDefaultRootWindow.restype = [C.c_void_p], C.c_ulong
    x.XQueryTree.argtypes = [C.c_void_p, C.c_ulong, C.POINTER(C.c_ulong), C.POINTER(C.c_ulong),
                            C.POINTER(C.POINTER(C.c_ulong)), C.POINTER(C.c_uint)]
    x.XFetchName.argtypes = [C.c_void_p, C.c_ulong, C.POINTER(C.c_char_p)]
    x.XGetWindowProperty.argtypes = [C.c_void_p, C.c_ulong, C.c_ulong, C.c_long, C.c_long,
                                     C.c_int, C.c_ulong, C.POINTER(C.c_ulong), C.POINTER(C.c_int),
                                     C.POINTER(C.c_ulong), C.POINTER(C.c_ulong),
                                     C.POINTER(C.POINTER(C.c_ubyte))]
    x.XFree.argtypes = [C.c_void_p]
    x.XInternAtom.argtypes, x.XInternAtom.restype = [C.c_void_p, C.c_char_p, C.c_int], C.c_ulong
    x.XSendEvent.argtypes = [C.c_void_p, C.c_ulong, C.c_int, C.c_long, C.POINTER(Event)]
    x.XFlush.argtypes = [C.c_void_p]
    x.XCloseDisplay.argtypes = [C.c_void_p]
    display = x.XOpenDisplay(None)
    if not display:
        raise RuntimeError("A working X11 DISPLAY is required")
    executable = args.executable.resolve()
    with tempfile.TemporaryDirectory(prefix="wf2-smoke-export.") as temporary:
        env = os.environ.copy()
        env.update(XDG_CONFIG_HOME=temporary + "/config", XDG_DATA_HOME=temporary + "/data",
                   XDG_CACHE_HOME=temporary + "/cache")
        log_path = out / "linux-render.log"
        with log_path.open("w") as log:
            command = [str(executable)]
            if args.project:
                command += ["--path", str(args.project.resolve())]
            process = subprocess.Popen(command + ["--audio-driver", "Dummy", "--",
                                        "--autoplay", "--capture=" + str(capture)],
                                       stdout=log, stderr=subprocess.STDOUT, env=env)
            try:
                deadline = time.monotonic() + 90
                while not capture.is_file():
                    if process.poll() is not None or time.monotonic() > deadline:
                        raise RuntimeError("Export stopped or failed to capture within 90 seconds")
                    time.sleep(0.1)
                root = C.c_ulong()
                parent = C.c_ulong()
                children = C.POINTER(C.c_ulong)()
                count = C.c_uint()
                x.XQueryTree(display, x.XDefaultRootWindow(display), C.byref(root), C.byref(parent),
                             C.byref(children), C.byref(count))
                window = None
                for index in range(count.value):
                    name = C.c_char_p()
                    if x.XFetchName(display, children[index], C.byref(name)) and name.value:
                        title = name.value.decode("utf-8", errors="replace")
                        if "魔女" in title:
                            actual_type, items, remaining = C.c_ulong(), C.c_ulong(), C.c_ulong()
                            bits = C.c_int()
                            data = C.POINTER(C.c_ubyte)()
                            x.XGetWindowProperty(display, children[index],
                                x.XInternAtom(display, b"_NET_WM_PID", 0), 0, 1, 0, 0,
                                C.byref(actual_type), C.byref(bits), C.byref(items),
                                C.byref(remaining), C.byref(data))
                            if data:
                                if bits.value == 32 and items.value and C.cast(data, C.POINTER(C.c_ulong))[0] == process.pid:
                                    window = children[index]
                                x.XFree(data)
                        x.XFree(name)
                if children:
                    x.XFree(children)
                if window is None:
                    raise RuntimeError("Exported game window was not found")
                event = Event()
                event.client.type = 33
                event.client.send_event = 1
                event.client.display = display
                event.client.window = window
                event.client.message_type = x.XInternAtom(display, b"WM_PROTOCOLS", 0)
                event.client.format = 32
                event.client.data.l[0] = x.XInternAtom(display, b"WM_DELETE_WINDOW", 0)
                sent = x.XSendEvent(display, window, 0, 0, C.byref(event))
                print("WM_DELETE_WINDOW sent", sent, "window", window, flush=True)
                assert sent != 0
                x.XFlush(display)
                code = process.wait(timeout=15)
            finally:
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=10)
                x.XCloseDisplay(display)
        text = log_path.read_text()
        assert code == 0 and "CAPTURE_SAVED" in text, text
        assert "ERROR:" not in text and "leaked" not in text, text
        report = {"passed": True, "exit_code": code, "window_close": "WM_DELETE_WINDOW",
                  "binary_sha256": hashlib.sha256(executable.read_bytes()).hexdigest(),
                  "capture": str(capture), "audio_driver": "Dummy",
                  "limitation": "X11 software rendering and autoplay fixture; not manual play or audible audio validation."}
        (out / "linux-validation.json").write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
