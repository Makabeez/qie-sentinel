"""Safety invariants for optional AI advisory. No real API or chain access."""
import io
import json
import unittest
from advisor import advisory, AdvisoryError

class Response(io.BytesIO):
    def __enter__(self): return self
    def __exit__(self, *args): self.close()

class AdvisorTests(unittest.TestCase):
    def setUp(self):
        self.invocations=[]
        self.data={
            'amountQUSDC':'0.050000', 'recipient':'0xce99cF8EdfD199dB02b830445d89E746B8c1C7ff',
            'recipientSource':'configured demo alias','nonce':3,
            'decision':'REJECT',
            'checks':[{'name':'Recipient is allowlisted','ok':False}], 'riskNotes':[]
        }
    def interpreter(self, text, nonce):
        self.invocations.append(('interpret', text, nonce))
        return dict(self.data)
    def fetch(self, req, timeout):
        self.invocations.append(('fetch', req, timeout))
        self.assertEqual(req.full_url,'https://api.openai.com/v1/responses')
        self.assertEqual(timeout,20)
        d=json.loads(req.data)
        self.assertEqual(d['store'],False)
        self.assertNotIn('private key',d['input'].lower())
        return Response(json.dumps({'output':[{'type':'message','content':[{'type':'output_text','text':'Policy rejects this transfer.'}]}]}).encode())
    def run_advice(self,**kw):
        return advisory('Pay 0.05 QUSDC to approved provider', consent=True,
                        nonce_provider=lambda:3,interpreter=self.interpreter,fetch=self.fetch,
                        environ={'OPENAI_API_KEY':'sk-test-only','SENTINEL_OPENAI_MODEL':'gpt-6.1-terra'},**kw)
    def test_advice_cannot_override_rejection(self):
        response=self.run_advice()
        self.assertEqual(response['policy']['decision'],'REJECT')
        self.assertEqual(response['advice'],'Policy rejects this transfer.')
        self.assertEqual([x[0] for x in self.invocations],['interpret','fetch'])
        self.assertNotIn('signature',response['policy'])
    def test_no_consent_does_not_call_services(self):
        with self.assertRaisesRegex(AdvisoryError,'consent'):
            advisory('Pay 0.05 QUSDC to approved provider',consent=False,
                     nonce_provider=lambda:3,interpreter=self.interpreter,fetch=self.fetch,
                     environ={'OPENAI_API_KEY':'sk-test-only'})
        self.assertFalse(self.invocations)
    def test_no_key_does_not_call_network(self):
        with self.assertRaisesRegex(AdvisoryError,'OPENAI_API_KEY'):
            advisory('Pay 0.05 QUSDC to approved provider',consent=True,
                     nonce_provider=lambda:3,interpreter=self.interpreter,fetch=self.fetch,
                     environ={})
        self.assertFalse(self.invocations)
    def test_credential_looking_text_rejected(self):
        with self.assertRaisesRegex(AdvisoryError,'credentials'):
            advisory('Please send my private key with this payment request',consent=True,
                     nonce_provider=lambda:3,interpreter=self.interpreter,fetch=self.fetch,
                     environ={'OPENAI_API_KEY':'sk-test-only'})
        self.assertFalse(self.invocations)
    def test_model_instruction_cannot_change_policy(self):
        self.data['decision']='ELIGIBLE_FOR_OWNER_SIGNATURE'
        response=self.run_advice()
        self.assertEqual(response['policy']['decision'],'ELIGIBLE_FOR_OWNER_SIGNATURE')
        self.assertEqual(response['engine'],'openai-advisory-only')

if __name__=='__main__': unittest.main()
