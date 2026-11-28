// QIE Sentinel 2.6 — conservative, local-only owner consent review.
// This review is an ACKNOWLEDGEMENT OF RISKS, never a signature/authorization.
// No wallet providers, RPC calls or transaction APIs.
import {offlineEip712} from './keccak-eip712.mjs';

const APPROVAL_CHECKS=Object.freeze([
 {id:'recipient',label:'I have independently confirmed the recipient address.'},
 {id:'amount',label:'I understand the exact QUSDC amount and token.'},
 {id:'scope',label:'I checked the vault, chain, nonce, deadline and executor.'},
 {id:'purpose',label:'I understand the free-text payment reason is NOT EIP-712 signed.'},
 {id:'authority',label:'I understand this checklist cannot authorize or execute a payment.'},
 {id:'freshness',label:'I understand policy and account state must be rechecked before actual signing.'}
]);
export {APPROVAL_CHECKS};
const HASH=/^0x[0-9a-f]{64}$/i;
function equalHex(a,b){return typeof a==='string'&&typeof b==='string'&&a.toLowerCase()===b.toLowerCase();}
export function reviewConsent({packet,evidence,checks}){
 // Imported evidence and packet are user-controlled. They are not authenticity proofs.
 const computed=offlineEip712(packet);
 if(!evidence||typeof evidence!=='object')throw new Error('Import a valid v2.4 verification report');
 if(evidence.state!=='CURRENT_UNSIGNED'||evidence.checksPassed!==true||
    evidence.cryptographicDigestMatch!==true)
  throw new Error('Verification report does not show a current unsigned digest match');
 if(!HASH.test(evidence.onchainPaymentDigest||'')||!HASH.test(evidence.onchainDomainSeparator||''))
  throw new Error('Missing on-chain cryptographic evidence');
 if(!equalHex(computed.digest,evidence.onchainPaymentDigest)||
    !equalHex(computed.domainSeparator,evidence.onchainDomainSeparator)||
    !equalHex(computed.digest,evidence.independentlyComputedDigest)||
    !equalHex(computed.domainSeparator,evidence.independentlyComputedDomainSeparator))
  throw new Error('Packet does not match the imported verification digest/domain');
 if(evidence.chainId!==1990||evidence.signaturePresent!==false||
    evidence.transactionBroadcast!==false)
  throw new Error('Evidence chain or no-signature markers are inconsistent');
 if(!Number.isSafeInteger(Number(evidence.blockTimestamp))||Number(evidence.blockTimestamp)<=0)
  throw new Error('Invalid evidence block timestamp');
 const required=APPROVAL_CHECKS.map(item=>item.id);
 if(!Array.isArray(checks)||checks.length!==required.length||
    required.some(k=>!checks.includes(k))||new Set(checks).size!==required.length)
  throw new Error('Every risk acknowledgement must be selected');
 const m=packet.typedData.message;
 return Object.freeze({
  schema:'qie-sentinel-owner-review-v1',
  status:'ACKNOWLEDGED_NOT_AUTHORIZED',
  paymentDigest:computed.digest,
  domainSeparator:computed.domainSeparator,
  vault:packet.typedData.domain.verifyingContract,
  chainId:1990,recipient:m.recipient,amountRaw:m.amount,
  token:m.token,nonce:m.nonce,deadline:m.deadline,executor:m.executor,
  evidenceBlock:String(evidence.block),
  evidenceBlockTimestamp:String(evidence.blockTimestamp),
  checks:required,
  walletIdentityVerified:false,
  signature:null,signatureVerified:false,broadcast:false,
  disclaimer:'Human risk checklist only. Uploaded evidence can be forged or stale. No wallet ownership, cryptographic signature, policy freshness at time of use, payment authorization or execution has been established.'
 });
}
