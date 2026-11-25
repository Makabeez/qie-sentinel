import test from 'node:test';
import assert from 'node:assert/strict';
import {makeUnsignedEnvelope,DEMO_OWNER} from './authorization.mjs';
import {NETWORK} from './policy.mjs';
import {offlineEip712} from './keccak-eip712.mjs';
import {APPROVAL_CHECKS,reviewConsent} from './owner-review.mjs';
const recipient='0xce99cF8EdfD199dB02b830445d89E746B8c1C7ff';
const packet=()=>makeUnsignedEnvelope({viewer:DEMO_OWNER,review:{
 result:'ELIGIBLE_FOR_INDEPENDENT_OWNER_APPROVAL',validated:true,paused:false,nonceUsed:false,
 network:1990,contract:NETWORK.vault,recipient,amountQUSDC:'0.050000',
 nonce:'3',deadline:'1800000200',block:'12000000',chainTimestamp:'1800000000'
}});
const evidence=p=>{
 const hash=offlineEip712(p);
 return {
 state:'CURRENT_UNSIGNED',checksPassed:true,cryptographicDigestMatch:true,chainId:1990,
 onchainPaymentDigest:hash.digest,independentlyComputedDigest:hash.digest,
 onchainDomainSeparator:hash.domainSeparator,independentlyComputedDomainSeparator:hash.domainSeparator,
 signaturePresent:false,transactionBroadcast:false,block:'0xb71b00',blockTimestamp:'1800000000'
 };
};
const checks=()=>APPROVAL_CHECKS.map(x=>x.id);
test('complete acknowledgement is still NOT authorization',()=>{
 const p=packet(),out=reviewConsent({packet:p,evidence:evidence(p),checks:checks()});
 assert.equal(out.status,'ACKNOWLEDGED_NOT_AUTHORIZED');
 assert.equal(out.signature,null);
 assert.equal(out.signatureVerified,false);
 assert.equal(out.walletIdentityVerified,false);
 assert.equal(out.broadcast,false);
 assert.equal(out.paymentDigest,offlineEip712(p).digest);
});
test('rejects missing or duplicate risk acknowledgements',()=>{
 const p=packet(),e=evidence(p);
 for(const c of [[],checks().slice(0,-1),[...checks().slice(0,-1),checks()[0]]])
  assert.throws(()=>reviewConsent({packet:p,evidence:e,checks:c}));
});
test('any modified unsigned packet breaks the proof binding',()=>{
 const p=packet(),e=evidence(p);
 const change=packet();change.typedData.message.amount='50001';
 assert.throws(()=>reviewConsent({packet:change,evidence:e,checks:checks()}),/does not match/);
});
test('reject forged chain, stale report and mismatched hash or missing report',()=>{
 const p=packet(),e=evidence(p);
 for(const mutation of [
 {state:'STALE_OR_BLOCKED'},{checksPassed:false},{cryptographicDigestMatch:false},
 {chainId:1},{signaturePresent:true},{transactionBroadcast:true},
 {onchainPaymentDigest:'0x'+'11'.repeat(32)},{onchainDomainSeparator:'0xbeef'},
 {independentlyComputedDigest:'0x'+'22'.repeat(32)},{blockTimestamp:'invalid'}
 ])assert.throws(()=>reviewConsent({packet:p,evidence:{...e,...mutation},checks:checks()}));
 assert.throws(()=>reviewConsent({packet:p,evidence:null,checks:checks()}));
});
