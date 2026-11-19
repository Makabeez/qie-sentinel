import sys
import unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent))
from showcase import build_page
class ShowcaseV06Tests(unittest.TestCase):
    def setUp(self):
        self.doc={'schema':'qie-sentinel-evidence-v1','chain_id':1990,'generated_at':1795112909,'events':[],
          'proposals':[{'id':'r','status':'REJECTED','amount':50000,'nonce':4,'recipient':'0x'+'b'*40,'created_at':1795112798,'checks':[{'name':'Recipient is allowlisted','ok':False}]}]}
    def test_plain_language_security_label(self):
        self.assertIn('Recipient not authorized',build_page(self.doc))
    def test_extra_onchain_events(self):
        rendered=build_page(self.doc,{'payments':[{'txHash':'0x'+'1'*64,'amount':250000,'nonce':1,'block':123}]})
        self.assertIn('0.250000 QUSDC',rendered)
        self.assertIn('On-chain payment events',rendered)
    def test_absent_chain_snapshot_not_misrepresented(self):
        self.assertNotIn('On-chain payment events',build_page(self.doc))
if __name__=='__main__':unittest.main()
