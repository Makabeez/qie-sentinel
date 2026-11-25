const EXPECTED=Object.freeze([
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
]);
export function classifyLocalReport(r){
 if(!r||r.schema!=='qie-sentinel-v27-local-authorization-tests-v1')throw new Error('Wrong local report schema');
 if(r.network!=='LOCAL_FOUNDRY_EVM_ONLY'||r.mainnetBroadcast!==false||
    r.realWalletKeysUsed!==false||r.realFundsMoved!==false)
  throw new Error('Missing local-only security markers');
 if(!/^[0-9a-f]{40}$/.test(r.repoCommit||''))throw new Error('Invalid source commit');
 if(!Array.isArray(r.passedTests)||!Array.isArray(r.missingOrFailedTests)||
    !Array.isArray(r.unexpectedTests))throw new Error('Malformed test accounting');
 const exactly=EXPECTED.length===r.passedTests.length&&
   new Set(r.passedTests).size===EXPECTED.length&&
   EXPECTED.every(x=>r.passedTests.includes(x));
 const clear=r.missingOrFailedTests.length===0&&r.unexpectedTests.length===0;
 const passes=r.status==='PASSED_LOCAL_SIMULATION'&&r.exitCode===0&&
   r.expectedTests===EXPECTED.length&&exactly&&clear;
 return {passes,expected:EXPECTED.length,reported:r.passedTests.length,
   message:passes?'11 expected tests reported passing in local Foundry. This evidence is user-controlled and not independently verified.':
    'Local test report is incomplete, failed, or inconsistent; do not treat it as a pass.'};
}
