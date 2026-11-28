import {classifyLocalReport,EXPECTED} from './lifecycle-validation.mjs';
// QIE Sentinel 2.7: local JSON evidence viewer. Never contacts an RPC or wallet.
// Reports are user-controlled, so the display is not an independent test attestation.
const $=id=>document.getElementById(id);
const pretty=name=>name.replace(/^testV27/,'').replace(/([a-z])([A-Z])/g,'$1 $2');
function fact(name,value){
 const row=document.createElement('div');row.className='fact';
 const a=document.createElement('span');a.textContent=name;
 const b=document.createElement('strong');b.textContent=String(value);
 row.append(a,b);$('lifecycle-facts').append(row);
}
$('lifecycle-form').addEventListener('submit',async e=>{
 e.preventDefault();
 $('lifecycle-facts').replaceChildren();$('lifecycle-cases').replaceChildren();
 $('lifecycle-json').textContent='No trusted evidence loaded.';
 try{
  const file=$('lifecycle-file').files?.[0];
  if(!file)throw new Error('Choose a local test report');
  if(file.size>100000)throw new Error('JSON file exceeds 100 kB');
  const report=JSON.parse(await file.text());
  const result=classifyLocalReport(report);
  $('lifecycle-title').textContent=result.passes?'LOCAL TESTS REPORTED PASSING':'INCOMPLETE OR FAILED LOCAL TESTS';
  $('lifecycle-summary').textContent=result.message;
  $('lifecycle-feedback').textContent='Imported report only. No wallet or network APIs used.';
  for(const [key,value] of [
   ['Reported tests',result.reported+' / '+result.expected],['Git commit',report.repoCommit],
   ['Test run',report.createdUtc],['Foundry',report.foundryVersion],
   ['Test environment',report.network],['Live execution','NO'],['Report attestation','NONE']
  ])fact(key,value);
  for(const name of EXPECTED){
   const div=document.createElement('div');div.className='fact';
   const label=document.createElement('span');label.textContent=pretty(name);
   const verdict=document.createElement('strong');
   const ok=report.passedTests.includes(name)&&!report.missingOrFailedTests.includes(name);
   verdict.textContent=ok?'REPORTED PASS':'NOT VERIFIED';
   div.append(label,verdict);$('lifecycle-cases').append(div);
  }
  $('lifecycle-json').textContent=JSON.stringify(report,null,2);
 }catch(error){
  $('lifecycle-title').textContent='UNVERIFIABLE';
  $('lifecycle-summary').textContent=String(error.message||error);
  $('lifecycle-feedback').textContent='Could not inspect report; no trusted evidence established.';
 }
});
