import json
import os
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from types import ModuleType

sys.path.insert(0,str(Path(__file__).resolve().parent))
import workflow
# Unit-test runner in a clean environment need not have Foundry installed.
# Substitute only the read-only server imports; tests patch all on-chain results.
server_stub=ModuleType('server')
server_stub.KNOWN_RECIPIENT='0xce99cF8EdfD199dB02b830445d89E746B8c1C7ff'
server_stub.VAULT='0xb752F05a55059C89a43a289d5d055F303B6DD96E'
server_stub.evaluate=lambda payload: None
server_stub.snapshot=lambda: None
server_stub.call=lambda *args: None
with patch.dict(sys.modules, {'server':server_stub}):
    import demo


def fake_evaluate(payload):
    recipient=payload['recipient']
    amount=payload['amount']
    nonce=payload['nonce']
    checks=[
        {'name':'Recipient is allowlisted', 'ok':recipient.lower()==demo.KNOWN_RECIPIENT.lower()},
        {'name':'Amount within per-transfer limit','ok':amount<=1000000},
        {'name':'Nonce has not been used','ok':nonce!=1},
    ]
    return {'decision':'ELIGIBLE_FOR_OWNER_SIGNATURE' if all(c['ok'] for c in checks) else 'REJECT', 'checks':checks}

class DemoTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.old=workflow.DB
        workflow.DB=Path(self.temp.name)/'test.sqlite3'

    def tearDown(self):
        workflow.DB=self.old
        self.temp.cleanup()

    def test_agent_creates_one_unsigned_candidate_and_four_rejections(self):
        with patch.object(demo,'snapshot',return_value={'maxPerTransfer':1000000,'balance':550000}),\
             patch.object(demo,'call',side_effect=lambda *args: int(args[-1],16)==1),\
             patch.object(demo,'evaluate',side_effect=fake_evaluate):
            data=demo.run()
        self.assertEqual(data['mode'],'NO_KEYS_NO_TRANSACTIONS')
        self.assertEqual(len(data['scenarios']),5)
        rows=workflow.proposals()
        self.assertEqual(len(rows),5)
        self.assertEqual([r['status'] for r in rows].count('AWAITING_OWNER'),1)
        self.assertEqual([r['status'] for r in rows].count('REJECTED'),4)
        with workflow.connection() as con:
            unsigned=con.execute("SELECT count(*) FROM proposals WHERE signature IS NOT NULL OR tx_hash IS NOT NULL").fetchone()[0]
            self.assertEqual(unsigned,0)
        self.assertGreaterEqual(len(workflow.events()),9)

    def test_nonce_not_reused_between_demo_runs(self):
        with patch.object(demo,'snapshot',return_value={'maxPerTransfer':1000000,'balance':550000}),\
             patch.object(demo,'call',side_effect=lambda *args: int(args[-1],16)==1),\
             patch.object(demo,'evaluate',side_effect=fake_evaluate):
            demo.run()
            demo.run()
        with workflow.connection() as con:
            n=[r[0] for r in con.execute("SELECT nonce FROM proposals WHERE status='AWAITING_OWNER'")]
        self.assertEqual(len(n),len(set(n)))
        self.assertEqual(len(n),2)

    def test_demo_fails_closed_if_network_unavailable(self):
        with patch.object(demo,'snapshot',side_effect=RuntimeError('RPC unavailable')):
            with self.assertRaisesRegex(RuntimeError,'RPC unavailable'):
                demo.run()
        self.assertEqual(workflow.proposals(),[])

if __name__ == '__main__':
    unittest.main()
