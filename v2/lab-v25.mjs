// Sentinel 2.5: local EIP-712 integrity demonstration only, no signing.
import {integrityComparison} from './integrity.mjs';
const $=id=>document.getElementById(id);
let lastReport=null;
function addFact(label,value){
 const line=document.createElement('div');line.className='fact';
 const left=document.createElement('span');left.textContent=label;
 const right=document.createElement('strong');right.textContent=String(value);
 line.append(left,right);$('lab-facts').append(line);
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
