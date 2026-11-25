import test from 'node:test';
import assert from 'node:assert/strict';
import {makeUnsignedEnvelope,DEMO_OWNER} from './authorization.mjs';
import {NETWORK} from './policy.mjs';
import {VERIFY_SELECTORS,encodeDigestCall,parseAddressWord,evaluateDigestSnapshot} from './freshness.mjs';
const executor='0xD0612b00030AC351EAb6A7800E4b7679e3f7D95A';
const recipient='0xce99cF8EdfD199dB02b830445d89E746B8c1C7ff';
const review={
 result:'ELIGIBLE_FOR_INDEPENDENT_OWNER_APPROVAL',validated:true,paused:false,nonceUsed:false,
 network:1990,contract:NETWORK.vault,recipient,amountQUSDC:'0.050000',
 nonce:'3',deadline:'1800000200',block:'12000000',chainTimestamp:'1800000000'
};
const packet=()=>makeUnsignedEnvelope({review,viewer:DEMO_OWNER});
const good=()=>({
 chainId:1990,vault:NETWORK.vault,owner:DEMO_OWNER,executor,token:NETWORK.token,
 guard:NETWORK.guard,paused:false,nonceUsed:false,policyPass:true,
 timestamp:1800000000n,block:'0xb71b00',balance:550000n,
 digest:'0x'+'cd'.repeat(32),domainSeparator:'0x'+'ef'.repeat(32),
 codeExists:true,identityMatches:true
});
test('paymentDigest calldata uses exact six statically encoded Payment words',()=>{
 const call=encodeDigestCall(packet());
 assert.equal(VERIFY_SELECTORS.paymentDigest,'0x56ac28f4');
 assert.ok(call.startsWith('0x56ac28f4'));
 assert.equal(call.length,394);
 assert.equal(call.slice(10,74).toLowerCase(),'0'.repeat(24)+NETWORK.token.slice(2).toLowerCase());
 assert.equal(call.slice(74,138).toLowerCase(),'0'.repeat(24)+recipient.slice(2).toLowerCase());
 assert.equal(BigInt('0x'+call.slice(138,202)),50000n);
 assert.equal(BigInt('0x'+call.slice(202,266)),3n);
 assert.equal(BigInt('0x'+call.slice(266,330)),1800000200n);
 assert.equal(call.slice(330).toLowerCase(),'0'.repeat(24)+executor.slice(2).toLowerCase());
});
test('address word parsing rejects malformed padding',()=>{
 assert.equal(parseAddressWord('0x'+'0'.repeat(24)+DEMO_OWNER.slice(2),'owner').toLowerCase(),DEMO_OWNER.toLowerCase());
 assert.throws(()=>parseAddressWord('0x'+'f'.repeat(64),'owner'));
 assert.throws(()=>parseAddressWord('0x00','owner'));
});
test('fresh unsigned review is never signature verification',()=>{
 const v=evaluateDigestSnapshot(packet(),good());
 assert.equal(v.state,'CURRENT_UNSIGNED');assert.equal(v.checksPassed,true);
 assert.equal(v.signaturePresent,false);assert.equal(v.transactionBroadcast,false);
 assert.match(v.disclaimer,/NOT an independently computed/);
});
test('fail closed for stale owner, rotated executor, replay, paused and expiry',()=>{
 const mutations=[
  {owner:recipient},{executor:recipient},{nonceUsed:true},{paused:true},
  {timestamp:1800000201n},{policyPass:false},{balance:1n},
  {chainId:1},{guard:recipient},{token:recipient},{codeExists:false},{identityMatches:false},
  {digest:'0xdead'},{domainSeparator:'0xbeef'}
 ];
 for(const change of mutations){
  const result=evaluateDigestSnapshot(packet(),{...good(),...change});
  assert.equal(result.state,'STALE_OR_BLOCKED',JSON.stringify(change,(_,v)=>typeof v==='bigint'?String(v):v));
  assert.ok(result.reasons.length);
 }
});
test('tampered packet fields cannot create digest calldata',()=>{
 for(const change of [
  {token:recipient},{amount:'-1'},{amount:'0'},{nonce:'1e9'}, {deadline:'-4'},
  {recipient:'0x1234'},{executor:'0x1234'}
 ]){
  const p=packet();Object.assign(p.typedData.message,change);
  assert.throws(()=>encodeDigestCall(p));
 }
 const p=packet();p.typedData.domain.chainId=1;assert.throws(()=>encodeDigestCall(p));
});
