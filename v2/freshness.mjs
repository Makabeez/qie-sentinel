// QIE Sentinel 2.3 — read-only, block-pinned on-chain EIP-712 packet validation.
// No wallet signing, no eth_sendTransaction and no client-supplied digest claims.
import {NETWORK,validAddress,encodedCall,amountToUnits} from './policy.mjs';

export const VERIFY_SELECTORS=Object.freeze({
  paymentDigest:'0x56ac28f4', // keccak256("paymentDigest((address,address,uint256,uint256,uint256,address))")
  owner:'0x8da5cb5b', executor:'0xc34c08e5',
  domainSeparator:'0xf698da25', nonce:'0x5d00bb12',
  paused:'0x5c975abb', token:'0xfc0c546a',guard:'0x7ceab3b1'
});
const UINT256_MAX=(1n<<256n)-1n;
export function parseWord(value,label){
 if(typeof value!=='string'||!/^0x[0-9a-fA-F]{64}$/.test(value))
   throw new Error('Invalid '+label+' contract word');
 return BigInt(value);
}
export function parseAddressWord(value,label){
 const n=parseWord(value,label);
 if(n>(1n<<160n)-1n)throw new Error('Malformed '+label+' address word');
 return '0x'+n.toString(16).padStart(40,'0');
}
export function sameAddress(a,b){return validAddress(a)&&validAddress(b)&&a.toLowerCase()===b.toLowerCase();}
export function encodeDigestCall(packet){
 if(!packet||packet.state!=='UNSIGNED_NOT_AUTHORIZED'||packet.signature!==null||
    packet.notSigned!==true||packet.notBroadcast!==true)
   throw new Error('Only intact unsigned packets may be checked');
 if(packet.typedData?.primaryType!=='Payment')throw new Error('Incorrect primary type');
 const domain=packet.typedData.domain;
 if(domain?.name!=='QIE Sentinel Vault'||domain.version!=='1'||
    domain.chainId!==1990||!sameAddress(domain.verifyingContract,NETWORK.vault))
   throw new Error('Wrong EIP-712 signing domain');
 const fields=packet.typedData.types?.Payment;
 const expected=['token','recipient','amount','nonce','deadline','executor'];
 if(!Array.isArray(fields)||fields.length!==6||fields.some((f,i)=>f.name!==expected[i]||f.type!==(i<2||i===5?'address':'uint256')))
   throw new Error('Unexpected EIP-712 Payment structure');
 const m=packet.typedData.message;
 if(!sameAddress(m.token,NETWORK.token)||!validAddress(m.recipient)||!validAddress(m.executor))
   throw new Error('Invalid payment addresses');
 const raw=[];
 for(const name of ['amount','nonce','deadline']){
  const str=m[name];
  if(typeof str!=='string'||!/^(0|[1-9][0-9]*)$/.test(str))throw new Error('Noncanonical '+name);
  const n=BigInt(str);
  if(n>UINT256_MAX)throw new Error('Uint256 overflow: '+name);
  raw.push(n);
 }
 if(raw[0]===0n)throw new Error('Zero payment amount');
 return encodedCall(VERIFY_SELECTORS.paymentDigest,[m.token,m.recipient,...raw,m.executor]);
}
export function evaluateDigestSnapshot(packet, snapshot){
 if(!packet||!snapshot)throw new Error('Missing packet or on-chain snapshot');
 const failures=[];
 const needs=(ok,reason)=>{if(!ok)failures.push(reason);};
 const m=packet.typedData.message;
 needs(snapshot.chainId===1990,'Wrong RPC chain');
 needs(sameAddress(snapshot.vault,NETWORK.vault),'Wrong vault address');
 needs(sameAddress(snapshot.owner,packet.recordedOwner),'Vault owner changed');
 needs(sameAddress(snapshot.executor,m.executor),'Executor was rotated');
 needs(sameAddress(snapshot.token,m.token),'Vault token mismatch');
 needs(sameAddress(snapshot.guard,NETWORK.guard),'Vault guard changed');
 needs(!snapshot.paused,'Vault is paused');
 needs(!snapshot.nonceUsed,'Payment nonce was used');
 needs(snapshot.policyPass===true,'PolicyGuard does not permit payment');
 needs(BigInt(m.deadline)>=BigInt(snapshot.timestamp),'Payment deadline expired');
 needs(BigInt(m.amount)<=BigInt(snapshot.balance),'Vault balance too low');
 needs(/^0x[0-9a-f]{64}$/i.test(snapshot.digest||''),'Invalid contract payment digest');
 needs(/^0x[0-9a-f]{64}$/i.test(snapshot.domainSeparator||''),'Invalid contract domain separator');
 needs(snapshot.codeExists===true,'Verified vault contract code unavailable');
 needs(snapshot.identityMatches===true,'Connected wallet account or network changed');
 // This is a check of *current chain policy* only, not proof of a signature.
 return {state:failures.length?'STALE_OR_BLOCKED':'CURRENT_UNSIGNED',
   checksPassed:failures.length===0,reasons:failures,chainId:1990,
   block:String(snapshot.block),blockTimestamp:String(snapshot.timestamp),
   onchainPaymentDigest:snapshot.digest, onchainDomainSeparator:snapshot.domainSeparator,
   recordedOwner:snapshot.owner, recordedExecutor:snapshot.executor,
   signaturePresent:false,transactionBroadcast:false,
   disclaimer:'Read-only on-chain digest and current-state check, NOT an independently computed off-chain digest comparison, signature validation, authorization, execution simulation or transaction. Repeat all checks before any future signing.'};
}
