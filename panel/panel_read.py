"""Read-only, bounded file cache and existing System-v7 validation adapter."""
from __future__ import annotations
import contextlib
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import threading
import time

if os.name == "nt":
    import ctypes
    from ctypes import wintypes
    class _BasicInfo(ctypes.Structure):
        _fields_ = [(n, ctypes.c_longlong) for n in ("created", "accessed", "written", "changed")] + [("attributes", wintypes.DWORD)]
    _kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    _kernel.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD, wintypes.LPVOID, wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE]
    _kernel.CreateFileW.restype = wintypes.HANDLE
    _kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    _kernel.GetFileInformationByHandleEx.argtypes = [wintypes.HANDLE, ctypes.c_int, wintypes.LPVOID, wintypes.DWORD]

def change_time(path):
    # Python 3.11 st_ctime on Windows is creation time, not NTFS ChangeTime.
    name = str(Path(path).absolute())
    if len(name) > 240 and not name.startswith("\\\\?\\"):
        name = "\\\\?\\UNC\\" + name[2:] if name.startswith("\\\\") else "\\\\?\\" + name
    handle = _kernel.CreateFileW(name, 0x80, 7, None, 3, 0x02000000, None)
    if handle == wintypes.HANDLE(-1).value:
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        info = _BasicInfo()
        if not _kernel.GetFileInformationByHandleEx(handle, 0, ctypes.byref(info), ctypes.sizeof(info)):
            raise ctypes.WinError(ctypes.get_last_error())
        return info.changed
    finally:
        _kernel.CloseHandle(handle)

SYSTEM_ROOT = Path(__file__).resolve().parent.parent / "system"
class ReadError(ValueError):
    pass

def signature(path):
    try:
        s = Path(path).stat()
        # NTFS timestamps can coalesce two rapid writes. Small control files get
        # a content guard as well; large source bytes are checked by digest cache.
        guard = None
        if s.st_size <= 65536 and Path(path).is_file():
            with shared_open(path) as f:
                guard = hashlib.blake2b(f.read(), digest_size=16).digest()
        return (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, change_time(path) if os.name == "nt" else s.st_ctime_ns, guard)
    except FileNotFoundError:
        return None

def shared_open(path):
    if os.name != "nt":
        return open(path, "rb")
    import msvcrt
    name = str(Path(path).absolute())
    if len(name) > 240 and not name.startswith("\\\\?\\"):
        name = "\\\\?\\UNC\\" + name[2:] if name.startswith("\\\\") else "\\\\?\\" + name
    handle = _kernel.CreateFileW(name, 0x80000000, 7, None, 3, 0x80, None)
    if handle == wintypes.HANDLE(-1).value:
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        fd = msvcrt.open_osfhandle(handle, os.O_RDONLY | os.O_BINARY)
    except Exception:
        _kernel.CloseHandle(handle)
        raise
    return os.fdopen(fd, "rb")

def safe_relative(root, relative):
    if not isinstance(relative, str) or not relative or relative in ("BRAK", "MISSING"):
        raise ReadError("Brak ścieżki artefaktu")
    p = Path(relative)
    if p.is_absolute() or ".." in p.parts or ":" in relative:
        raise ReadError("Ścieżka poza projektem")
    target = root / p
    for part in (target, *target.parents):
        if part == root.parent:
            break
        if part.is_symlink() or (part.exists() and getattr(part.lstat(), "st_file_attributes", 0) & 1024):
            raise ReadError("Dowiązanie w ścieżce artefaktu")
    if not target.resolve().is_relative_to(root.resolve()):
        raise ReadError("Ścieżka poza projektem")
    return target

def unique_object(pairs):
    result = {}
    seen = set()
    for key, value in pairs:
        if key.casefold() in seen:
            raise ReadError("Powtórzone pole JSON: " + key)
        result[key] = value
        seen.add(key.casefold())
    return result

def json_load(data):
    return json.loads(data, object_pairs_hook=unique_object)

class FileStore:
    """Caches only reads. Metadata changes and periodic digest checks invalidate results."""
    def __init__(self, root, opener):
        self.root, self.opener = Path(root), opener
        self.cache, self.hashes = {}, {}
        self.dependencies = {}
        self.reads = 0
        self.bytes_read = 0
        self.max_cache_bytes = 32 * 1024 * 1024

    def begin(self):
        self.dependencies = {}

    def stamp(self, path):
        key = str(path)
        sig = signature(path)
        self.dependencies[key] = sig
        return sig

    def stable(self):
        return all(signature(k) == v for k, v in self.dependencies.items())

    def read(self, path, kind="text"):
        path = Path(path)
        key = (str(path), kind)
        sig = self.stamp(path)
        if sig is None:
            self.cache.pop(key, None)
            return [] if kind == "jsonl" else None
        old = self.cache.get(key)
        now = time.monotonic()
        if old and old["sig"] == sig and now - old["at"] < 30:
            return old["value"]
        # Ledger append only optimization; verify prefix digest before trusting append.
        # This remains bounded to changed ledgers; unchanged JSONL is never re-read on a tick.
        with self.opener(path) as f:
            data = f.read()
        self.reads += 1
        self.bytes_read += len(data)
        if signature(path) != sig:
            raise ReadError("Plik zmienił się podczas odczytu: " + path.name)
        try:
            text = data.decode("utf-8-sig", "strict")
            if kind == "json":
                value = json_load(text)
                if not isinstance(value, dict):
                    raise ReadError("Oczekiwano obiektu JSON: " + path.name)
            elif kind == "jsonl":
                if text and not text.endswith(("\n", "\r")):
                    raise ReadError("Niepełny zapis JSONL: " + path.name)
                previous = old.get("data", b"") if old else b""
                if previous and data.startswith(previous):
                    value = old["value"] + [json_load(line) for line in data[len(previous):].decode("utf-8").splitlines() if line.strip()]
                else:
                    value = [json_load(line) for line in text.splitlines() if line.strip()]
                if any(not isinstance(x, dict) for x in value):
                    raise ReadError("Nieprawidłowy rekord JSONL: " + path.name)
            else:
                value = text
        except (UnicodeError, ValueError) as exc:
            raise ReadError(f"Nieczytelne dane {path.name}: {exc}") from exc
        self.cache.pop(key, None)
        # Cap retained raw payload. Parsed objects have additional Python overhead.
        while self.cache and (len(self.cache) >= 2048 or sum(x["size"] for x in self.cache.values()) + len(data) > self.max_cache_bytes):
            self.cache.pop(next(iter(self.cache)))
        if len(data) <= self.max_cache_bytes:
            self.cache[key] = {"sig": sig, "value": value, "at": now, "size": len(data), "data": data if kind == "jsonl" else b""}
        return value

    def digest(self, path):
        path = Path(path)
        sig = self.stamp(path)
        if sig is None:
            return None
        old = self.hashes.get(str(path))
        now = time.monotonic()
        if old and old[0] == sig and now - old[2] < 30:
            return old[1]
        h = hashlib.sha256()
        with self.opener(path) as f:
            for block in iter(lambda: f.read(1024 * 1024), b""):
                h.update(block)
                self.bytes_read += len(block)
        self.reads += 1
        if signature(path) != sig:
            raise ReadError("Plik zmienił się podczas kontroli: " + path.name)
        value = h.hexdigest().upper()
        if len(self.hashes) >= 4096:
            self.hashes.pop(next(iter(self.hashes)))
        self.hashes[str(path)] = (sig, value, now)
        return value

    def bound(self, relative, digest):
        if not isinstance(digest, str) or len(digest) != 64:
            return False
        try:
            return self.digest(safe_relative(self.root, relative)) == digest.upper()
        except (ReadError, OSError):
            return False

_CORE = None
def k1_core():
    global _CORE
    if _CORE is None:
        path = SYSTEM_ROOT / "tools/k1-lite-v2/k1_lite_v2_core.py"
        spec = importlib.util.spec_from_file_location("_panel_k1_core", path)
        module = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = module
        spec.loader.exec_module(module)
        _CORE = module
    return _CORE

def inventory(root):
    """Metadata and small-file guards; omit original media and cache directories."""
    rows = []
    for directory, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in {".git", "__pycache__", "_oryginaly", "node_modules"}
                   and not (Path(directory) / d).is_symlink()
                   and not (getattr((Path(directory) / d).lstat(), "st_file_attributes", 0) & 1024)]
        for name in files:
            path = Path(directory) / name
            if path.suffix.lower() in {".sqlite3", ".db", ".tmp", ".lock"}:
                continue
            rows.append((str(path), signature(path)))
    # Validator changes also invalidate previous answers.
    tools = SYSTEM_ROOT / "tools"
    for name in ("Narrative-Receipts.ps1", "Narrative-V2.ps1", "Narrative-Efficiency.ps1", "Project-Origin.ps1", "K1-PublishIntegrity.ps1"):
        rows.append((str(tools / name), signature(tools / name)))
    adapter = Path(__file__).with_name("Read-PanelProofs.ps1")
    rows.append((str(adapter), signature(adapter)))
    return tuple(sorted(rows))

class Verifier:
    """One worker, no mutation commands. A changed snapshot never reuses a green result."""
    def __init__(self, root):
        self.root = Path(root)
        self.key = None
        self.result = {}
        self.running = False
        self.checked_at = 0
        self.checked_mono = 0
        self.lock = threading.Lock()
        self.thread = None

    def get(self, key):
        with self.lock:
            ttl = 15 if self.result.get("error") else 300
            if key == self.key and self.result and time.monotonic() - self.checked_mono < ttl:
                return self.result
            if not self.running:
                self.running = True
                self.thread = threading.Thread(target=self._run, args=(key,), daemon=True)
                self.thread.start()
        return {"pending": True}

    def _run(self, key):
        try:
            shell = shutil.which("pwsh")
            if not shell:
                raise ReadError("Brak PowerShell 7 — ważność dowodów niezweryfikowana")
            flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
            proc = subprocess.run([shell, "-NoProfile", "-NonInteractive", "-File",
                str(Path(__file__).with_name("Read-PanelProofs.ps1")),
                "-ProjectPath", str(self.root), "-SystemRoot", str(SYSTEM_ROOT)],
                capture_output=True, encoding="utf-8", errors="replace", timeout=90, creationflags=flags)
            if proc.returncode:
                raise ReadError(proc.stderr.strip()[:500] or "Błąd walidatora")
            data = json_load(proc.stdout.lstrip("\ufeff"))
            if not isinstance(data, dict):
                raise ReadError("Nieprawidłowa odpowiedź walidatora")
            if inventory(self.root) != key:
                data = {"error": "Pliki zmieniły się podczas kontroli; ponowienie po ustabilizowaniu"}
                key = None
        except Exception as exc:
            data = {"error": str(exc)}
        with self.lock:
            self.key, self.result, self.running = key, data, False
            self.checked_at = time.time()
            self.checked_mono = time.monotonic()
