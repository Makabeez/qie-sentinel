import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {classifyLocalReport} from './lifecycle-validation.mjs';
const names=[
 'testV27IndependentUsersReceiveDistinctOwnershipAndGuards',
 'testV27IndependentOwnerConsentAndExecutorPerformOnlyScopedTransfer',
 'testV27AIAgentOrUnauthorizedCallerCannotSubmitSignedPayment',
 'testV27WrongOwnerSignatureRejectedWithNoStateChange',
 'testV27SignatureForAliceVaultCannotAuthorizeBobVault',
 'testV27OwnerRevocationPreventsExecutionOfPreviouslyValidSignature',
 'testV27OwnerPausesToBlockEvenCorrectlySignedIntent',
 'testV27BudgetLimitBlocksAdditionalPaymentWithoutConsumingNonce',
 'testV27ExpiredIntentFailsWithNoNonceConsumption',
 'testV27RotatingExecutorInvalidatesOldExecutorPermission',
 'testV27OutsiderCannotManageAnotherOwnerVault'
];
const sample=()=>({
 schema:'qie-sentinel-v27-local-authorization-tests-v1',status:'PASSED_LOCAL_SIMULATION',
 network:'LOCAL_FOUNDRY_EVM_ONLY',repoCommit:'a'.repeat(40),mainnetBroadcast:false,
 realWalletKeysUsed:false,realFundsMoved:false,passedTests:names.slice(),
 missingOrFailedTests:[],unexpectedTests:[],exitCode:0,expectedTests:11
});
test('complete local report is labeled only as user-reported',()=>{
 const r=classifyLocalReport(sample());
 assert.equal(r.passes,true);
 assert.match(r.message,/user-controlled/);
});
test('incomplete, duplicate, failed or deceptive report cannot pass',()=>{
 for(const mutation of [
 {passedTests:names.slice(1)}, {passedTests:[...names.slice(1),names[0],names[0]]},
 {status:'FAILED_LOCAL_SIMULATION'}, {exitCode:1},{expectedTests:10},
 {mainnetBroadcast:true},{realWalletKeysUsed:true},{network:'QIE_MAINNET'},
 {missingOrFailedTests:['testV27OwnerPausesToBlockEvenCorrectlySignedIntent']}
 ]){
  const value={...sample(),...mutation};
  if(['mainnetBroadcast','realWalletKeysUsed','network'].some(k=>Object.hasOwn(mutation,k)))
   assert.throws(()=>classifyLocalReport(value));
  else assert.equal(classifyLocalReport(value).passes,false);
 }
});
test('browser viewer contains no wallet signing or network calls',()=>{
 const src=readFileSync(new URL('./lifecycle-v27.mjs',import.meta.url),'utf8');
 for(const method of ['eth_requestAccounts','eth_sendTransaction','eth_signTypedData','personal_sign','fetch(','XMLHttpRequest('])
  assert.equal(src.includes(method),false,method);
});
