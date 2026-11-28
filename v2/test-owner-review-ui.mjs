import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const read=p=>readFileSync(new URL(p,import.meta.url),'utf8');
test('v2.6 owner review never has wallet signing or sending capability',()=>{
 const html=read('./owner-review.html'),browser=read('./owner-review-ui.mjs'),core=read('./owner-review.mjs');
 assert.match(html,/NOT AUTHORIZED/);
 assert.match(html,/type="file"/);
 assert.match(browser,/reviewConsent/);
 assert.match(browser,/download-review/);
 for(const forbidden of ['eth_sendTransaction','eth_signTypedData','eth_requestAccounts','personal_sign','eth_sendRawTransaction','wallet_requestPermissions']){
  assert.equal(browser.includes(forbidden),false,forbidden);
  assert.equal(core.includes(forbidden),false,forbidden);
 }
 assert.match(core,/ACKNOWLEDGED_NOT_AUTHORIZED/);
 assert.match(core,/walletIdentityVerified:false/);
 assert.match(core,/signatureVerified:false/);
});
