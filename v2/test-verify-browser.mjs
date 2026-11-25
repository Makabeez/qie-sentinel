import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const read=p=>readFileSync(new URL(p,import.meta.url),'utf8');
test('separate verification UI imports unsigned JSON without wallet access',()=>{
 const page=read('./verify.html'),app=read('./verify-v24.mjs');
 assert.match(page,/type="file"/);assert.match(page,/verify-v24\.mjs/);
 assert.match(app,/encodeDigestCall\(packet\)/);
 assert.match(app,/eth_getBlockByNumber/);
 assert.match(app,/eth_getCode/);
 assert.match(app,/domainSeparator/);
 assert.match(app,/policyPass/);
 assert.match(app,/compareEip712\(packet,digest,domainSeparator\)/);
 assert.match(app,/cryptographicDigestMatch/);
 for(const forbidden of ['eth_sendTransaction','eth_sendRawTransaction','eth_signTypedData','personal_sign','eth_requestAccounts']){
  assert.equal(app.includes(forbidden),false,forbidden);
 }
 assert.match(app,/UNVERIFIABLE — FAIL CLOSED/);
 assert.match(app,/NOT VERIFIED/);
});
