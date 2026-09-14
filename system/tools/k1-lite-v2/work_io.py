"""Local durability helpers; callers hold the project/run lock."""
import json
import os
import tempfile
from contextlib import contextmanager
from pathlib import Path
from k1_lite_v2_core import K1LiteV2Error, ensure_within


def safe(path: Path, root: Path) -> Path:
    for parent in (path.absolute(), *path.absolute().parents):
        if parent.is_symlink() or (parent.exists() and getattr(parent.lstat(), 'st_file_attributes', 0) & 1024):
            raise K1LiteV2Error('WORK_REPARSE_POINT_BLOCKED')
    return ensure_within(path, root)


def json_bytes(value):
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2)+'\n').encode('utf-8')


def atomic_new(path: Path, data: bytes):
    if path.exists():
        if path.read_bytes() != data:
            raise K1LiteV2Error(f'WORK_IMMUTABLE_FILE_MISMATCH: {path.name}')
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.work-', suffix='.tmp', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data); stream.flush(); os.fsync(stream.fileno())
        try:
            os.link(temporary, path)  # Atomic CreateNew, including on NTFS.
        except FileExistsError:
            if path.read_bytes() != data:
                raise K1LiteV2Error(f'WORK_IMMUTABLE_FILE_MISMATCH: {path.name}')
            return False
        return True
    finally:
        if os.path.exists(temporary): os.unlink(temporary)


@contextmanager
def run_lock(run: Path, root: Path):
    with safe(run/'work-cycle.lock', root).open('a+b') as handle:
        handle.seek(0, 2)
        if handle.tell() == 0: handle.write(b'0'); handle.flush()
        handle.seek(0)
        try:
            if os.name == 'nt':
                import msvcrt
                msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as exc:
            raise K1LiteV2Error('WORK_CYCLE_BUSY') from exc
        try:
            yield
        finally:
            handle.seek(0)
            if os.name == 'nt': msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
            else: fcntl.flock(handle, fcntl.LOCK_UN)
