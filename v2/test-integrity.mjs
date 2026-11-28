import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {makeUnsignedEnvelope,DEMO_OWNER} from './authorization.mjs';
import {integrityComparison} from './integrity.mjs';
import {NETWORK} from './policy.mjs';
const recipient='0xce99cF8EdfD199dB02b830445d89E746B8c1C7ff';
function packet(){
 const review={result:'ELIGIBLE_FOR_INDEPENDENT_OWNER_APPROVAL',validated:true,paused:false,nonceUsed:false,
 network:1990,contract:NETWORK.vault,recipient,amountQUSDC:'0.050000',nonce:'3',
 deadline:'1795878480',block:'12163842',chainTimestamp:'1795615748'};
 return makeUnsignedEnvelope({review,viewer:DEMO_OWNER});
}
test('every signing field mutation modifies commitment or is rejected',()=>{
 for(const field of ['amount','nonce','recipient','deadline','executor','chain','vault']){
  const outcome=integrityComparison(packet(),field);
  assert.equal(outcome.detected,true,field);
  assert.equal(outcome.signatureVerification,'NOT_PERFORMED');
  assert.notEqual(outcome.originalDigest,outcome.modifiedDigest);
  assert.notEqual(outcome.status,'AUTHORIZED');
 }
});
test('unknown mutations fail closed',()=>{
 assert.throws(()=>integrityComparison(packet(),'secret'),/Unsupported mutation/);
});
test('UI never requests wallet accounts, signs or sends a transaction',()=>{
 const app=readFileSync(new URL('./lab-v25.mjs',import.meta.url),'utf8');
 const html=readFileSync(new URL('./crypto-lab.html',import.meta.url),'utf8');
 assert.match(html,/NO WALLET/);
 assert.match(html,/signature-validation scenarios/);
 for(const method of ['eth_requestAccounts','eth_sign','personal_sign','eth_sendTransaction','eth_sendRawTransaction']){
  assert.equal(app.includes(method),false,method);
 }
 assert.match(app,/integrityComparison/);
 assert.match(app,/download-lab/);
});
