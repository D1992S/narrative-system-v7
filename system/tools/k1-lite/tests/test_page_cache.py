import json
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import pdf_to_markdown as converter
import fitz


class PageCacheTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.pdf = self.root/'source.pdf'
        with fitz.open() as doc:
            for i in range(3):
                doc.new_page().insert_text((50, 50), f'Unique source page {i}.')
            doc.save(self.pdf)
        self.cache = self.root/'cache.sqlite3'

    def convert(self, name):
        return converter.render_preview(pdf_path=self.pdf,
            expected_pdf_sha256=converter.sha256_file(self.pdf), pages_to_ocr=[],
            languages_text='none', dpi=300, psm=3, tesseract='unused',
            preview_path=self.root/(name+'.md'), report_path=self.root/(name+'.json'),
            source_reference='source.pdf', preview_reference=name+'.md', cache_path=self.cache)

    def test_warm_cache_avoids_extraction_and_preserves_bytes(self):
        self.convert('cold')
        with patch.object(converter, 'native_text', side_effect=AssertionError('must reuse')):
            report = self.convert('warm')
        self.assertEqual(report['page_cache']['hits'], 3)
        self.assertEqual((self.root/'cold.md').read_bytes(), (self.root/'warm.md').read_bytes())

    def test_interruption_resumes_completed_pages(self):
        original=converter.native_text
        def fail_last(page):
            if page.number==2:
                raise RuntimeError('interrupted')
            return original(page)
        with patch.object(converter,'native_text',side_effect=fail_last):
            with self.assertRaisesRegex(RuntimeError,'interrupted'):
                self.convert('first')
        self.assertFalse((self.root/'first.md').exists())
        with patch.object(converter,'native_text',wraps=original) as extract:
            report=self.convert('first')
        self.assertEqual(extract.call_count,1)
        self.assertEqual(report['page_cache']['hits'],2)

    def test_damaged_entry_is_recomputed(self):
        self.convert('cold')
        with sqlite3.connect(self.cache) as db:
            db.execute("UPDATE pages SET body='damaged' WHERE key=(SELECT key FROM pages LIMIT 1)")
        db.close()
        with patch.object(converter,'native_text',wraps=converter.native_text) as extract:
            self.convert('warm')
        self.assertEqual(extract.call_count,1)
        self.assertEqual((self.root/'cold.md').read_bytes(),(self.root/'warm.md').read_bytes())

    def test_corrupt_database_falls_back(self):
        self.cache.write_bytes(b'not sqlite')
        report=self.convert('fallback')
        self.assertEqual(report['page_cache']['hits'],0)
        self.assertIsNotNone(report['page_cache']['error'])

    def test_binary_cache_body_is_recomputed(self):
        self.convert('cold')
        with sqlite3.connect(self.cache) as db:
            db.execute("UPDATE pages SET body=?", (b'invalid binary body',))
        db.close()
        report = self.convert('warm')
        self.assertEqual(report['page_cache']['hits'], 0)
        self.assertEqual((self.root/'cold.md').read_bytes(), (self.root/'warm.md').read_bytes())

    def test_changed_pdf_does_not_reuse(self):
        self.convert('first')
        with fitz.open(self.pdf) as doc:
            doc[0].insert_text((50,80),'New information.')
            doc.saveIncr()
        report=self.convert('second')
        self.assertEqual(report['page_cache']['hits'],0)
        self.assertIn('New information.',(self.root/'second.md').read_text())

    def test_original_output_collision_is_preserved(self):
        self.convert('first')
        before=(self.root/'first.md').read_bytes()
        with self.assertRaisesRegex(converter.K1LiteError,'PREVIEW_OUTPUT_EXISTS'):
            self.convert('first')
        self.assertEqual(before,(self.root/'first.md').read_bytes())


if __name__=='__main__':
    unittest.main()
