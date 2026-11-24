import {deploymentPreview} from './onboarding.mjs';
import {NETWORK,SELECTORS,amountToUnits,unitsToAmount,validAddress,encodedCall,assess,reasonForRevert,proposalEvidence} from './policy.mjs';

const $=id=>document.getElementById(id);
const DEAD='0x0000000000000000000000000000000000000000';
const TOKEN_BALANCE_OF='0x70a08231';
let viewer=null;
let report=null;
const provider=window.ethereum;

function showConnection(){
 $('connect').textContent=viewer ? viewer.slice(0,6)+'…'+viewer.slice(-4) : (provider?'Connect wallet':'Wallet optional');
}
showConnection();
// We never request a signature or transaction. Wallet requestAccounts is only called by button click.
$('connect').addEventListener('click',async()=>{
 if(!provider){setStatus('No injected wallet detected','Read-only checks work without a wallet. Install an EVM wallet only if you want the optional reviewer identity.','warn');return;}
 $('connect').disabled=true;
 try{
  const accounts=await provider.request({method:'eth_requestAccounts'});
  const chain=await provider.request({method:'eth_chainId'});
  if(BigInt(chain)!==1990n){viewer=null;throw new Error('Connected wallet is on another network. Switch to QIE Mainnet (chain 1990) in your wallet. No network switch was requested.');}
  if(!accounts?.length||!validAddress(accounts[0]))throw new Error('Wallet returned no usable address.');
  viewer=accounts[0];showConnection();$('new-owner').value=viewer;resetPlan();
  clearReport();
  setStatus('Wallet identified','Connected account: '+viewer+'. This identity does not grant control over the demonstration vault.','warn');
 }catch(e){viewer=null;showConnection();setStatus('Wallet connection unavailable',String(e.message||e),'warn');}
 finally{$('connect').disabled=false;}
});
provider?.on?.('accountsChanged',()=>{
 viewer=null;showConnection();clearReport();$('new-owner').value='';resetPlan();
 setStatus('Wallet context changed','Reconnect to attach your current wallet address to a new review.','warn');
});
provider?.on?.('chainChanged',()=>{
 viewer=null;showConnection();clearReport();$('new-owner').value='';resetPlan();
 setStatus('Wallet network changed','Reconnect after switching to QIE Mainnet.','warn');
});
function clearReport(){report=null;$('export').disabled=true;$('copy').disabled=true;$('facts').replaceChildren();}
function setStatus(title,summary,kind){
 $('status-title').textContent=title;$('status-summary').textContent=summary;
 $('status-icon').textContent=kind==='good'?'✓':kind==='bad'?'×':'!';
 $('status-icon').className='status-icon '+kind;
}
function fact(name,value){
 const d=document.createElement('div');d.className='fact';
 const a=document.createElement('span');a.textContent=name;
 const b=document.createElement('strong');b.textContent=String(value);
 d.append(a,b);$('facts').append(d);
}
function units(hex){if(!/^0x[0-9a-f]+$/i.test(hex)||hex.length<66)throw new Error('Unexpected contract uint256 response');return BigInt(hex);}
function failRpc(e){
 const error=new Error('QIE RPC unavailable or returned an unexpected result. No eligibility verdict issued.');
 error.cause=e;return error;
}
async function rpc(method,params){
 const ctl=new AbortController(),timer=setTimeout(()=>ctl.abort(),12000);
 try{
  const res=await fetch(NETWORK.rpc,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({jsonrpc:'2.0',id:1,method,params}),signal:ctl.signal,cache:'no-store'});
  if(!res.ok)throw failRpc(new Error('HTTP '+res.status));
  const j=await res.json();if(j.error){const e=new Error(j.error.message||'JSON-RPC error');e.data=j.error.data;throw e;}
  if(j.result===undefined||j.result===null)throw failRpc(new Error('Missing JSON-RPC result'));
  return j.result;
 }catch(e){if(e?.data||/execution reverted/i.test(e?.message||''))throw e;throw failRpc(e);}
 finally{clearTimeout(timer);}
}
async function readContract(to,data,block){return rpc('eth_call',[{to,data},block]);}
async function readBool(to,data,block){return units(await readContract(to,data,block))!==0n;}
async function readUInt(to,data,block){return units(await readContract(to,data,block));}
async function checkGuard(recipient,amount,block){
 try{
  const out=await readContract(NETWORK.guard,encodedCall(SELECTORS.validate,[recipient,amount]),block);
  if(typeof out!=='string'||!/^0x[0-9a-f]+$/i.test(out)||out.length<130)throw new Error('Unexpected PolicyGuard validate response');
  return {pass:true,reason:null,method:'contract eth_call PASS'};
 }catch(e){
  const known=reasonForRevert(e);
  if(known)return {pass:false,reason:known,method:'contract eth_call custom error'};
  if(!/revert/i.test(e.message||''))throw e;
  // Read actual getter values as corroboration if an RPC strips revert bytes.
  const allowed=await readBool(NETWORK.guard,encodedCall(SELECTORS.allowed,[recipient]),block);
  const max=await readUInt(NETWORK.guard,SELECTORS.max,block);
  const remaining=await readUInt(NETWORK.guard,SELECTORS.remaining,block);
  if(!allowed)return {pass:false,reason:'Recipient is not on the vault allowlist',method:'validate reverted; verified with allowedRecipients getter'};
  if(amount>max)return {pass:false,reason:'Payment exceeds the vault per-transfer limit',method:'validate reverted; verified with maxPerTransfer getter'};
  if(amount>remaining)return {pass:false,reason:'Payment exceeds remaining daily budget',method:'validate reverted; verified with remainingToday getter'};
  throw failRpc(e);
 }
}
function futureDefault(){
 const dt=new Date(Date.now()+60*60*1000);
 // datetime-local expects local wall time; display the actual local time, convert to UTC on submit.
 const n=new Date(dt.getTime()-dt.getTimezoneOffset()*60000);
 $('expiry').value=n.toISOString().slice(0,16);
}
futureDefault();
$('proposal').addEventListener('submit',async ev=>{
 ev.preventDefault();const btn=$('evaluate');btn.disabled=true;btn.textContent='Checking QIE Mainnet…';
 clearReport();setStatus('Checking real chain state','No signature or transaction will be requested.','warn');
 try{
  const recipient=$('recipient').value.trim();
  if(!validAddress(recipient)||recipient.toLowerCase()===DEAD.toLowerCase())throw new Error('Enter a valid nonzero recipient address.');
  const amount=amountToUnits($('amount').value.trim());
  const nv=$('nonce').value.trim();
  if(!/^\d{1,25}$/.test(nv))throw new Error('Nonce must be a nonnegative integer.');
  const nonce=BigInt(nv);
  const timestamp=new Date($('expiry').value).getTime();
  if(!Number.isFinite(timestamp))throw new Error('Enter a valid deadline date and time.');
  const deadline=BigInt(Math.floor(timestamp/1000));
  const purpose=$('purpose').value.trim();
  if(purpose.length<3||purpose.length>240)throw new Error('A review note of 3 to 240 characters is required.');
  const chain=await rpc('eth_chainId',[]);
  if(BigInt(chain)!==1990n)throw new Error('RPC returned the wrong chain (expected 1990).');
  const block=await rpc('eth_getBlockByNumber',['latest',false]);
  if(!block?.number||!block.timestamp)throw new Error('Latest block unavailable.');
  const pinned=block.number;
  const paused=await readBool(NETWORK.vault,SELECTORS.paused,pinned);
  const [guard,nonceUsed,max,remaining,balance]=await Promise.all([
   checkGuard(recipient,amount,pinned),
   readBool(NETWORK.vault,encodedCall(SELECTORS.nonce,[nonce]),pinned),
   readUInt(NETWORK.guard,SELECTORS.max,pinned),
   readUInt(NETWORK.guard,SELECTORS.remaining,pinned),
   readUInt(NETWORK.token,encodedCall(TOKEN_BALANCE_OF,[NETWORK.vault]),pinned)
  ]);
  const results=assess({paused,validated:guard.pass,nonceUsed,deadline,blockTime:BigInt(block.timestamp),balance,amount});
  if(!guard.pass&&guard.reason)results.reasons.unshift(guard.reason);
  $('chain-label').textContent='BLOCK '+BigInt(block.number).toString();
  setStatus(results.eligible?'Eligible for independent owner approval':'Not eligible under current demo-vault policy',
   results.eligible?'All requested read-only checks passed. A real payment would still require a valid owner signature and the authorized executor.':results.reasons.join(' · '),
   results.eligible?'good':'bad');
  fact('PolicyGuard.validate',guard.method);
  fact('Vault paused',paused?'YES':'NO');
  fact('Nonce '+nonce,nonceUsed?'USED':'UNUSED');
  fact('Proposed amount',unitsToAmount(amount)+' QUSDC');
  fact('Per-transfer maximum',unitsToAmount(max)+' QUSDC');
  fact('Remaining daily allowance',unitsToAmount(remaining)+' QUSDC');
  fact('Vault QUSDC balance',unitsToAmount(balance)+' QUSDC');
  fact('Chain timestamp',new Date(Number(BigInt(block.timestamp))*1000).toISOString());
  fact('Deadline',new Date(Number(deadline)*1000).toISOString());
  fact('Review method','RPC eth_call / on-chain block state; NO execution');
  report={...proposalEvidence({recipient,amount,nonce,deadline,block:BigInt(block.number),account:viewer,results}),
    purpose,guardReadMethod:guard.method,chainTimestamp:String(BigInt(block.timestamp)),
    maxPerTransfer:unitsToAmount(max),remainingToday:unitsToAmount(remaining),
    demoVaultQUSDCBalance:unitsToAmount(balance),paused,nonceUsed,
    validated:guard.pass};
  $('export').disabled=false;$('copy').disabled=false;
 }catch(e){
  $('chain-label').textContent='UNAVAILABLE / INVALID INPUT';
  setStatus('No verdict issued',String(e.message||e),'warn');
  fact('Safety state','Fail closed: no inferred approval and no broadcast');
 }finally{btn.disabled=false;btn.textContent='Evaluate proposal →';}
});
$('export').addEventListener('click',()=>{
 if(!report)return;
 const blob=new Blob([JSON.stringify(report,null,2)+'\n'],{type:'application/json'});
 const u=URL.createObjectURL(blob),a=document.createElement('a');
 a.href=u;a.download='sentinel-review-'+report.block+'.json';a.click();
 setTimeout(()=>URL.revokeObjectURL(u),1000);
});
$('copy').addEventListener('click',async()=>{
 if(!report)return;
 try{await navigator.clipboard.writeText(JSON.stringify(report,null,2));$('copy').textContent='Copied ✓'}
 catch{$('copy').textContent='Clipboard unavailable'}
});


let plan=null;
function resetPlan(){
 plan=null;
 $('download-plan').disabled=true;
 $('plan-facts').replaceChildren();
 $('plan-title').textContent='No plan generated';
 $('plan-summary').textContent='A valid plan can be exported, but this prototype cannot deploy a vault.';
}
async function generatePlan(event){
 event?.preventDefault();
 resetPlan();
 const button=$('generate-plan');
 button.disabled=true;
 $('plan-feedback').textContent='Validating configuration locally…';
 $('plan-title').textContent='Checking your inputs';
 $('plan-summary').textContent='No transaction or signature will be requested.';
 try {
  if(!viewer||!provider)throw new Error('Connect your QIE Mainnet wallet first. No signature is requested.');
  // Local-only configuration preview. Do not block on injected wallet RPC calls:
  // some providers leave eth_accounts/eth_chainId requests pending indefinitely.
  // viewer was identified on chain 1990 at initial connection, but a preview
  // is NOT evidence of current chain/account state or authorization.
  plan=deploymentPreview({
   owner:viewer,
   executor:$('new-executor').value.trim(),
   maxPerPayment:$('new-max').value.trim(),
   dailyLimit:$('new-daily').value.trim()
  });
  $('plan-title').textContent='Valid configuration — deployment NOT available';
  $('plan-summary').textContent='Preview only. Uses the wallet identity captured at connection; live identity must be independently rechecked before any actual deployment. No contract, authorization, transaction or escrow has been created.';
  const rows=[
   ['Owner',plan.owner],
   ['Executor',plan.executor],
   ['Token',plan.token],
   ['Per-transfer cap',plan.maxPerTransferQUSDC+' QUSDC'],
   ['Daily cap',plan.dailyLimitQUSDC+' QUSDC'],
   ['Initial allowlist','Empty · default deny'],
   ['Factory status','Experimental · not deployed']
  ];
  for(const [name,value] of rows){
   const el=document.createElement('div');el.className='fact';
   const a=document.createElement('span');a.textContent=name;
   const b=document.createElement('strong');b.textContent=value;
   el.append(a,b);$('plan-facts').append(el);
  }
  $('download-plan').disabled=false;
  $('plan-feedback').textContent='Configuration valid. Download the local JSON plan below. Wallet signing and deployment are disabled.';
 }catch(err){
  const message=String(err?.message||err);
  $('plan-title').textContent='Configuration rejected';
  $('plan-summary').textContent=message;
  $('plan-feedback').textContent='Action needed: '+message;
 }finally{
  button.disabled=false;
 }
}
$('generate-plan').addEventListener('click',generatePlan);
$('vault-plan').addEventListener('submit',generatePlan);
$('download-plan').addEventListener('click',()=>{
 if(!plan)return;
 const blob=new Blob([JSON.stringify(plan,null,2)+'\n'],{type:'application/json'});
 const url=URL.createObjectURL(blob),a=document.createElement('a');
 a.href=url;a.download='sentinel-v2-deployment-preview.json';a.click();
 setTimeout(()=>URL.revokeObjectURL(url),1000);
});
