"""Disposable page cache. Transactions retain completed pages across interruptions."""
import hashlib
import json
import sqlite3
from pathlib import Path


class PageCache:
    def __init__(self, path: Path):
        self.db = None
        self.hits = self.misses = 0
        self.error = None
        try:
            for p in (path, *path.parents):
                if p.exists() and (p.is_symlink() or getattr(p.stat(), 'st_file_attributes', 0) & 1024):
                    raise ValueError('CACHE_REPARSE_POINT')
            path.parent.mkdir(parents=True, exist_ok=True)
            self.db = sqlite3.connect(path, timeout=5)
            self.db.execute('CREATE TABLE IF NOT EXISTS pages (key TEXT PRIMARY KEY, body TEXT NOT NULL, sha TEXT NOT NULL)')
            self.db.commit()
        except (OSError, sqlite3.Error, ValueError) as exc:
            self.disable(exc)

    def disable(self, exc):
        self.error = type(exc).__name__
        if self.db is not None:
            self.db.close()
        self.db = None

    @staticmethod
    def key(settings):
        return hashlib.sha256(json.dumps(settings, sort_keys=True, ensure_ascii=True).encode()).hexdigest()

    def get(self, key):
        if self.db is not None:
            try:
                row = self.db.execute('SELECT body, sha FROM pages WHERE key=?', (key,)).fetchone()
                if row and isinstance(row[0], str) and hashlib.sha256(row[0].encode('utf-8')).hexdigest() == row[1]:
                    self.hits += 1
                    return row[0]
            except sqlite3.Error as exc:
                self.disable(exc)
        self.misses += 1
        return None

    def put(self, key, body):
        if self.db is not None:
            try:
                with self.db:
                    self.db.execute('INSERT OR REPLACE INTO pages VALUES (?,?,?)',
                                    (key, body, hashlib.sha256(body.encode('utf-8')).hexdigest()))
            except sqlite3.Error as exc:
                self.disable(exc)

    def close(self):
        if self.db is not None:
            self.db.close()

    def discard(self, keys):
        if self.db is not None:
            try:
                with self.db:
                    self.db.executemany('DELETE FROM pages WHERE key=?', ((key,) for key in keys))
            except sqlite3.Error as exc:
                self.disable(exc)
