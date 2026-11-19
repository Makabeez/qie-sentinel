import os
import tempfile
import unittest
from pathlib import Path

from workflow import connection, get, events, submit, transition

class WorkflowTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        import workflow
        workflow.DB=Path(self.temp.name)/'test.sqlite3'

    def tearDown(self):
        self.temp.cleanup()

    def test_lifecycle_and_nonce_lock(self):
        decision={'decision':'ELIGIBLE_FOR_OWNER_SIGNATURE','checks':[{'name':'Vault is active','ok':True}]}
        import time
        deadline=int(time.time())+1800
        result=submit('0x'+'1'*40,100000,12,deadline,decision)
        self.assertEqual(result['status'],'AWAITING_OWNER')
        with self.assertRaisesRegex(ValueError,'reserves this nonce'):
            submit('0x'+'2'*40,100000,12,deadline,decision)
        transition(result['id'],'AWAITING_OWNER','SIGNED',digest='0x'+'a'*64,signature='0x'+'b'*130)
        self.assertEqual(get(result['id'])['status'],'SIGNED')
        with self.assertRaises(ValueError):
            transition(result['id'],'AWAITING_OWNER','SIGNED')
        self.assertEqual(len(events()),2)

    def test_rejected_audit(self):
        import time
        d={'decision':'REJECT','checks':[{'name':'Recipient is allowlisted','ok':False}]}
        result=submit('0x'+'0'*40,2000000,13,int(time.time())+1800,d)
        self.assertEqual(result['status'],'REJECTED')
        self.assertEqual(get(result['id'])['status'],'REJECTED')

if __name__=='__main__':
    unittest.main()
