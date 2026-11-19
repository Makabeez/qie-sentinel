import unittest
from showcase import build_page

class ShowcaseTests(unittest.TestCase):
    def setUp(self):
        self.data={'schema':'qie-sentinel-evidence-v1','chain_id':1990,'generated_at':1795112909,
          'proposals':[{'id':'one','status':'CONFIRMED','amount':100000,'nonce':2,'recipient':'0x'+'a'*40,'created_at':1795112797,'tx_hash':'0x'+'1'*64,'checks':[]},
                       {'id':'two','status':'REJECTED','amount':50000,'nonce':4,'recipient':'0x'+'b'*40,'created_at':1795112798,'checks':[{'name':'Recipient is allowlisted','ok':False}]}],
          'events':[{'kind':'SUBMITTED','proposal_id':'one','at':1795112799,'detail':{'tx_hash':'0x'+'1'*64}}]}
    def test_showcase_receipt_and_rejection(self):
        rendered=build_page(self.data)
        self.assertIn('https://mainnet.qie.digital/tx/0x'+'1'*64,rendered)
        self.assertIn('Recipient not authorized',rendered)
        self.assertIn('Off-chain rejected proposals',rendered)
        self.assertNotIn('signature',rendered.lower().split('proposal and transaction history')[0].split('confirmed ledger volume')[-1].split('approval boundary')[0])
    def test_reject_wrong_chain(self):
        self.data['chain_id']=1
        with self.assertRaises(ValueError):build_page(self.data)
    def test_escape_untrusted_text(self):
        self.data['proposals'][1]['checks'][0]['name']='<script>alert(1)</script>'
        rendered=build_page(self.data)
        self.assertNotIn('<script>alert(1)</script>',rendered)
        self.assertIn('&lt;script&gt;',rendered)
if __name__=='__main__':unittest.main()
