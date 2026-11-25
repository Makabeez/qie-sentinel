import test from 'node:test';
import assert from 'node:assert/strict';
import {makeUnsignedEnvelope,matchesProposal,DEMO_OWNER,DEMO_EXECUTOR,FIELDS} from './authorization.mjs';
import {NETWORK} from './policy.mjs';
const recipient='0xce99cF8EdfD199dB02b830445d89E746B8c1C7ff';
const review=()=>({
 schema:'qie-sentinel-read-only-review-v1',
 result:'ELIGIBLE_FOR_INDEPENDENT_OWNER_APPROVAL',validated:true,paused:false,nonceUsed:false,
 network:1990,contract:NETWORK.vault,recipient,amountQUSDC:'0.050000',
 nonce:'3',deadline:'1800000200',block:'12000000',chainTimestamp:'1800000000',
 maxPerTransfer:'1.000000',remainingToday:'5.000000',demoVaultQUSDCBalance:'0.550000'
});
const valid=()=>makeUnsignedEnvelope({review:review(),viewer:DEMO_OWNER});
test('EIP-712 matches verified vault contract fields and exact domain',()=>{
 const packet=valid();
 assert.equal(packet.state,'UNSIGNED_NOT_AUTHORIZED');
 assert.equal(packet.typedData.domain.chainId,1990);
 assert.equal(packet.typedData.domain.verifyingContract,NETWORK.vault);
 assert.equal(packet.typedData.domain.name,'QIE Sentinel Vault');
 assert.equal(packet.typedData.domain.version,'1');
 assert.equal(packet.typedData.primaryType,'Payment');
 assert.deepEqual(packet.typedData.types.Payment,FIELDS);
 assert.deepEqual(packet.typedData.message,{
 token:NETWORK.token,recipient,amount:'50000',nonce:'3',
 deadline:'1800000200',executor:DEMO_EXECUTOR
 });
 assert.equal(packet.signature,null);assert.equal(packet.notSigned,true);assert.equal(packet.notBroadcast,true);
});
test('rejects invalid review and nonowner wallet',()=>{
 for(const change of [
  {result:'NOT_ELIGIBLE'},{validated:false},{paused:true},{nonceUsed:true},
  {network:1},{contract:DEMO_EXECUTOR},{deadline:'1799999999'},
  {recipient:'0x1234'},{nonce:'-1'}
 ])assert.throws(()=>makeUnsignedEnvelope({review:{...review(),...change},viewer:DEMO_OWNER}));
 assert.throws(()=>makeUnsignedEnvelope({review:review(),viewer:DEMO_EXECUTOR}));
 assert.throws(()=>makeUnsignedEnvelope({review:review(),viewer:DEMO_OWNER,executor:recipient}));
});
test('any altered input invalidates exported preview',()=>{
 const packet=valid(),p={recipient,amount:'0.05',nonce:'3',deadline:'1800000200'};
 assert.equal(matchesProposal(packet,p),true);
 for(const altered of [{amount:'0.051'},{recipient:DEMO_OWNER},{nonce:'4'},{deadline:'1800000201'}])
  assert.equal(matchesProposal(packet,{...p,...altered}),false);
});
test('review is unsigned and invoice purpose is not bound by contract',()=>{
 const packet=valid();
 assert.ok(!packet.typedData.types.Payment.some(f=>f.name==='purpose'));
 assert.match(packet.disclaimer,/NOT signed/);
});
