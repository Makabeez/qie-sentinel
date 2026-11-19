import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parent

class EvidenceTests(unittest.TestCase):
    def test_export_excludes_signatures_and_preserves_receipt_hash(self):
        with tempfile.TemporaryDirectory() as td:
            import workflow
            old_db=workflow.DB
            try:
                workflow.DB=Path(td)/'audit.db'
                with workflow.connection() as con:
                    con.execute('INSERT INTO proposals(id,created_at,updated_at,recipient,amount,nonce,deadline,status,checks,signature,tx_hash) VALUES(?,?,?,?,?,?,?,?,?,?,?)',('abc',1,1,'0xabc',100000,3,9999999999,'SUBMITTED','[]','0xSECRET_SIGNATURE','0x'+'ab'*32))
                workflow.transition('abc','SUBMITTED','CONFIRMED')
                import evidence
                report=evidence.build_report()
                self.assertEqual(report['events'][-1]['detail']['tx_hash'],'0x'+'ab'*32)
                self.assertNotIn('signature',json.dumps(report).lower())
                self.assertEqual(report['proposals'][0]['status'],'CONFIRMED')
            finally:
                workflow.DB=old_db

if __name__=='__main__':
    unittest.main()
