import test from 'node:test';
import assert from 'node:assert/strict';
import {keccak256,offlineEip712,compareEip712} from './keccak-eip712.mjs';
import {makeUnsignedEnvelope,DEMO_OWNER} from './authorization.mjs';
import {NETWORK} from './policy.mjs';
const recipient='0xce99cF8EdfD199dB02b830445d89E746B8c1C7ff';
const review={result:'ELIGIBLE_FOR_INDEPENDENT_OWNER_APPROVAL',validated:true,paused:false,nonceUsed:false,
 network:1990,contract:NETWORK.vault,recipient,amountQUSDC:'0.050000',nonce:'3',
 deadline:'1795878480',block:'12163842',chainTimestamp:'1795615748'};
const packet=()=>makeUnsignedEnvelope({review,viewer:DEMO_OWNER});
const EXPECTED_DIGEST='0xed659a0295a064f8df6e87206d820567486226538d206fb7fcc4e3322b2373c9';
const EXPECTED_DOMAIN='0x3110fd77d0fc8822df2d08726a5f7c58eb7be8980c14378cffd3929740c99c6c';
test('independent Keccak agrees with canonical Ethereum known vectors',()=>{
 assert.equal(keccak256(new Uint8Array([])),
  '0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470');
 assert.equal(keccak256(new TextEncoder().encode('abc')),
  '0x4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45');
});
test('independent EIP-712 digest matches actual QIE Mainnet receipt evidence',()=>{
 const calculated=offlineEip712(packet());
 assert.equal(calculated.domainSeparator,EXPECTED_DOMAIN);
 assert.equal(calculated.digest,EXPECTED_DIGEST);
 assert.equal(compareEip712(packet(),EXPECTED_DIGEST,EXPECTED_DOMAIN).match,true);
 assert.equal(compareEip712(packet(),'0x'+'ab'.repeat(32),EXPECTED_DOMAIN).match,false);
});
test('tampering with any signed field changes independently computed hash',()=>{
 const original=offlineEip712(packet()).digest;
 for(const change of [{amount:'50001'},{recipient:DEMO_OWNER},{nonce:'4'},
   {deadline:'1795878481'},{executor:recipient}]){
  const mutated=packet();Object.assign(mutated.typedData.message,change);
  if(change.executor)assert.throws(()=>offlineEip712(mutated)); // demo executor pinned
  else assert.notEqual(offlineEip712(mutated).digest,original);
 }
});
test('wrong chain and vault fail closed before digest generation',()=>{
 const altered=packet();altered.typedData.domain.chainId=1;
 assert.throws(()=>offlineEip712(altered));
 const other=packet();other.typedData.domain.verifyingContract=recipient;
 assert.throws(()=>offlineEip712(other));
});
