import {APPROVAL_CHECKS,reviewConsent} from './owner-review.mjs';
const $=id=>document.getElementById(id);
let record=null;
function displayFact(key,value){
 const row=document.createElement('div');row.className='fact';
 const a=document.createElement('span');a.textContent=key;
 const b=document.createElement('strong');b.textContent=String(value);
 row.append(a,b);$('review-facts').append(row);
}
for(const check of APPROVAL_CHECKS){
 const label=document.createElement('label');
 label.className='risk-check';
 const input=document.createElement('input');input.type='checkbox';input.value=check.id;
 input.name='risk';input.setAttribute('aria-label',check.label);
 const text=document.createElement('span');text.textContent=check.label;
 label.append(input,text);$('review-checks').append(label);
 input.addEventListener('change',()=>{record=null;$('download-review').disabled=true;$('review-title').textContent='Review changed — regenerate';$('review-json').textContent='No current acknowledgement record.';});
}
async function readJSON(id){
 const file=$(id).files?.[0];
 if(!file)throw new Error('Select both files');
 if(file.size>100000)throw new Error('File exceeds 100 kB');
 return JSON.parse(await file.text());
}
for(const id of ['payment-file','evidence-file'])$(id).addEventListener('change',()=>{
 record=null;$('download-review').disabled=true;$('review-facts').replaceChildren();
 $('review-title').textContent='Files changed — regenerate';
 $('review-json').textContent='No current acknowledgement record.';
});
$('review-form').addEventListener('submit',async event=>{
 event.preventDefault();record=null;$('download-review').disabled=true;
 $('review-facts').replaceChildren();$('review-json').textContent='Validating local inputs…';
 try{
  const [packet,evidence]=await Promise.all([readJSON('payment-file'),readJSON('evidence-file')]);
  const checks=Array.from(document.querySelectorAll('input[name="risk"]:checked')).map(x=>x.value);
  record=reviewConsent({packet,evidence,checks});
  $('review-title').textContent='ACKNOWLEDGED — NOT AUTHORIZED';
  $('review-summary').textContent='This is a local digest-bound human risk checklist. It does not authenticate the wallet, verify a signature or grant an executor permission.';
  for(const [name,value] of [
   ['Digest',record.paymentDigest],['Recipient',record.recipient],['Token',record.token],
   ['Amount (raw units)',record.amountRaw],['Nonce',record.nonce],
   ['Executor',record.executor],['Evidence block',record.evidenceBlock],
   ['Wallet ownership','NOT VERIFIED'],['Signing','DISABLED'],['Execution','DISABLED']
  ])displayFact(name,value);
  $('review-json').textContent=JSON.stringify(record,null,2);
  $('review-feedback').textContent='Local acknowledgement record prepared. No wallet signing was requested.';
  $('download-review').disabled=false;
 }catch(error){
  $('review-title').textContent='REVIEW REJECTED';
  $('review-summary').textContent=String(error.message||error);
  $('review-json').textContent='No valid review record created.';
  $('review-feedback').textContent='Cannot record acknowledgement: '+String(error.message||error);
 }
});
$('download-review').addEventListener('click',()=>{
 if(!record)return;
 const url=URL.createObjectURL(new Blob([JSON.stringify(record,null,2)+'\n'],{type:'application/json'}));
 const a=document.createElement('a');a.href=url;a.download='sentinel-v26-acknowledgement-not-authorized.json';a.click();
 setTimeout(()=>URL.revokeObjectURL(url),1000);
});
