import test from 'node:test';
import assert from 'node:assert/strict';
import {validateVaultPlan,deploymentPreview} from './onboarding.mjs';
const owner='0x395215ab5Dde403801868fa850b89e305F01725E';
const executor='0xD0612b00030AC351EAb6A7800E4b7679e3f7D95A';
test('valid independent owner executor and spending policies',()=>{
 const p=deploymentPreview({owner,executor,maxPerPayment:'0.1',dailyLimit:'2'});
 assert.equal(p.state,'PREVIEW_ONLY_NOT_DEPLOYED');
 assert.equal(p.maxPerTransferRaw,'100000');
 assert.equal(p.dailyLimitRaw,'2000000');
 assert.deepEqual(p.initialAllowlist,[]);
 assert.equal(p.requiresNewFactoryDeployment,true);
});
test('same owner and executor rejected',()=>{
 const p=validateVaultPlan({owner,executor:owner,maxPerPayment:'1',dailyLimit:'2'});
 assert.equal(p.valid,false);assert.match(p.reasons.join(' '),/different wallets/);
});
test('invalid and zero executor rejected',()=>{
 for(const ex of ['0x1234','0x0000000000000000000000000000000000000000'])
 assert.equal(validateVaultPlan({owner,executor:ex,maxPerPayment:'1',dailyLimit:'2'}).valid,false);
});
test('invalid budget, zero, precision rejected',()=>{
 for(const [maxPerPayment,dailyLimit] of [['2','1'],['0','1'],['0.0000001','1'],['1','1e9']])
 assert.equal(validateVaultPlan({owner,executor,maxPerPayment,dailyLimit}).valid,false);
});
test('cannot create a plan without an identified owner wallet',()=>{
 assert.throws(()=>deploymentPreview({owner:null,executor,maxPerPayment:'1',dailyLimit:'3'}));
});
