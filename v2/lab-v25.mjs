// Sentinel 2.5: local EIP-712 integrity demonstration only, no signing.
import {offlineEip712} from './keccak-eip712.mjs';
const $=id=>document.getElementById(id);
let lastReport=null;
const OTHER='0x000000000000000000000000000000000000dEaD';
function addFact(label,value){
 const line=document.createElement('div');line.className='fact';
 const left=document.createElement('span');left.textContent=label;
 const right=document.createElement('strong');right.textContent=String(value);
 line.append(left,right);$('lab-facts').append(line);
}
function altered(packet,field){
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
$('offline-form').addEventListener('submit',async event=>{
 event.preventDefault();
 lastReport=null;$('download-lab').disabled=true;$('lab-facts').replaceChildren();
 try{
  const file=$('packet-file').files?.[0];
  if(!file)throw new Error('Select an unsigned EIP-712 packet');
  if(file.size>100000)throw new Error('Packet exceeds 100 kB limit');
  const parsed=JSON.parse(await file.text());
  const result=integrityComparison(parsed,$('mutation').value);
  lastReport=result;
  $('lab-title').textContent=result.mutationRejected?'DOMAIN CHANGE REJECTED':'PAYMENT DIGEST CHANGED';
  $('lab-summary').textContent='The original EIP-712 commitment cannot be reused unchanged for these altered details. No signature was tested.';
  for(const [label,value] of [
   ['Mutation',result.mutation],
   ['Original digest',result.originalDigest],
   ['Modified digest',result.modifiedDigest??'(domain rejected)'],
   ['Modification detected',result.detected?'YES':'NO'],
   ['Wallet signature','NOT VERIFIED'],
   ['Transaction','NOT AVAILABLE']])addFact(label,value);
  $('lab-feedback').textContent='Offline integrity check completed. No wallet or RPC connection was used.';
  $('download-lab').disabled=false;
 }catch(error){
  $('lab-title').textContent='UNVERIFIABLE — FAIL CLOSED';
  $('lab-summary').textContent=String(error.message||error);
  $('lab-feedback').textContent='No integrity report was produced.';
 }
});
$('download-lab').addEventListener('click',()=>{
 if(!lastReport)return;
 const url=URL.createObjectURL(new Blob([JSON.stringify(lastReport,null,2)+'\n'],{type:'application/json'}));
 const link=document.createElement('a');link.href=url;link.download='sentinel-v25-offline-integrity.json';link.click();
 setTimeout(()=>URL.revokeObjectURL(url),1000);
});
