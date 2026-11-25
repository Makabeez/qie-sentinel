// Pure offline integrity checks; does not access DOM, wallet or network.
import {offlineEip712} from './keccak-eip712.mjs';
const OTHER='0x000000000000000000000000000000000000dEaD';
export function altered(packet,field){
 const copy=structuredClone(packet);
 const m=copy.typedData.message;
 switch(field){
 case 'amount':m.amount=(BigInt(m.amount)+1n).toString();break;
 case 'nonce':m.nonce=(BigInt(m.nonce)+1n).toString();break;
 case 'recipient':m.recipient=m.recipient.toLowerCase()===OTHER.toLowerCase()?'0x000000000000000000000000000000000000bEEF':OTHER;break;
 case 'deadline':m.deadline=(BigInt(m.deadline)+1n).toString();break;
 case 'executor':m.executor=m.executor.toLowerCase()===OTHER.toLowerCase()?'0x000000000000000000000000000000000000bEEF':OTHER;break;
 case 'chain':copy.typedData.domain.chainId=1;break;
 case 'vault':copy.typedData.domain.verifyingContract=OTHER;break;
 default:throw new Error('Unsupported mutation');
 }
 return copy;
}
export function integrityComparison(packet,field){
 const original=offlineEip712(packet);
 let mutatedHash=null,mutationRejected=false,reason='';
 try{mutatedHash=offlineEip712(altered(packet,field)).digest;}
 catch(error){mutationRejected=true;reason=String(error.message||error);}
 const detected=mutationRejected||mutatedHash!==original.digest;
 if(!detected)throw new Error('Mutation was not detected; fail closed.');
 return {schema:'qie-sentinel-offline-integrity-v1',
  status:mutationRejected?'DOMAIN_CHANGE_REJECTED':'MODIFIED_DIGEST',
  mutation:field,originalDigest:original.digest,modifiedDigest:mutatedHash,
  mutationRejected,reason,detected,
  signatureVerification:'NOT_PERFORMED',
  signing:'NOT_AVAILABLE',transactions:'NOT_AVAILABLE',
  explanation:'Changing a field changes the EIP-712 commitment, or an unsupported signing domain is rejected. This is NOT a demonstration of cryptographic signature verification.'};
}
