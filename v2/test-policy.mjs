import test from 'node:test';
import assert from 'node:assert/strict';
import {amountToUnits,unitsToAmount,validAddress,encodedCall,SELECTORS,assess,reasonForRevert,proposalEvidence,NETWORK} from './policy.mjs';
test('six decimal precision, no rounding',()=>{
 assert.equal(amountToUnits('0.05'),50000n);assert.equal(amountToUnits('1.000001'),1000001n);
 assert.equal(unitsToAmount(1000001n),'1.000001');
 for(const a of ['0','-1','1e5','1.0000001','0.0000001','1.','NaN'])assert.throws(()=>amountToUnits(a));
});
test('address and eth_call encoding',()=>{
 assert.equal(validAddress('0xce99cF8EdfD199dB02b830445d89E746B8c1C7ff'),true);
 assert.equal(validAddress('0x1234'),false);
 assert.equal(encodedCall(SELECTORS.nonce,[1n]).length,74);
 assert.equal(encodedCall(SELECTORS.validate,['0xce99cF8EdfD199dB02b830445d89E746B8c1C7ff',50000n]).length,138);
});
test('fail closed, expired and nonce replay',()=>{
 const good={paused:false,validated:true,nonceUsed:false,deadline:110n,blockTime:100n,balance:550000n,amount:50000n};
 assert.equal(assess(good).eligible,true);
 assert.equal(assess({...good,nonceUsed:true}).eligible,false);
 assert.equal(assess({...good,deadline:100n}).eligible,false);
 assert.equal(assess({...good,balance:1000n}).eligible,false);
 assert.equal(assess({...good,validated:false}).eligible,false);
});
test('contract custom errors classified as read-only',()=>{
 assert.match(reasonForRevert({data:SELECTORS.notAllowed+'00'}),/allowlist/);
 assert.match(reasonForRevert({data:SELECTORS.overLimit+'00'}),/per-transfer/);
 assert.equal(reasonForRevert(new Error('HTTP 502')),null);
});
test('evidence explicitly excludes authorization',()=>{
 const p=proposalEvidence({recipient:'0xce99cF8EdfD199dB02b830445d89E746B8c1C7ff',amount:50000n,nonce:3n,deadline:120n,block:100n,account:null,results:{eligible:true,reasons:[]}});
 assert.match(p.disclaimer,/Read-only review/);
 assert.equal(p.contract,NETWORK.vault);
 assert.ok(!JSON.stringify(p).includes('privateKey'));
});
