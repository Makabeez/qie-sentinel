'use strict';
// Read-only chain RPC; never requests a wallet, signature or transaction.
// RPC/CORS failures are shown as unavailable, never as 'blocked'.
const RPCS = ['https://rpc1mainnet.qie.digital', 'https://mainnet.qie.digital/api/eth-rpc'];
const VAULT = '0xb752F05a55059C89a43a289d5d055F303B6DD96E';
const GUARD = '0x532Ee81939386E23b8c58076e643D9FCe489F15C';
const APPROVED = '0xce99cF8EdfD199dB02b830445d89E746B8c1C7ff';
const UNKNOWN = '0x000000000000000000000000000000000000dead';
const SELECTOR = Object.freeze({
  validate:'0x98e0ae14', nonce:'0x5d00bb12', paused:'0x5c975abb',
  allow:'0x4df6d6cc', max:'0xd1129bf3', remaining:'0xfc3c5515',
  notAllowed:'0x6ee9124e', overLimit:'0x4cf7e6a3', daily:'0xef664d6a', zero:'0xcbca5aa2'
});
// Selectors are keccak256(signature).slice(0,4).
const SCENARIOS = {
 valid: { recipient: APPROVED, amount:50000n, nonce:3n, deadline:'future' },
 recipient: { recipient:UNKNOWN, amount:50000n, nonce:4n, deadline:'future' },
 oversize: { recipient:APPROVED, amount:1000001n, nonce:5n, deadline:'future' },
 replay: { recipient:APPROVED, amount:50000n, nonce:1n, deadline:'future' },
 expired: { recipient:APPROVED, amount:50000n, nonce:6n, deadline:'past' }
};
const text = id => document.getElementById(id);
const pad = v => BigInt(v).toString(16).padStart(64,'0');
const addr = a => a.slice(2).toLowerCase().padStart(64,'0');
const fmt = n => (Number(n)/1e6).toFixed(6);
async function rpc(method, params) {
 const failures=[];
 for (const endpoint of RPCS) {
  const controller=new AbortController(); const timeout=setTimeout(()=>controller.abort(),9500);
  try {
   const response=await fetch(endpoint,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({jsonrpc:'2.0',id:1,method,params}),signal:controller.signal,cache:'no-store'});
   if(!response.ok) throw new Error('HTTP '+response.status);
   const obj=await response.json();
   if(obj.error) {const e=new Error(obj.error.message||'RPC returned an error');e.rpcData=obj.error.data;throw e;}
   if(typeof obj.result!=='string' && obj.result===undefined)throw new Error('Missing RPC result');
   return obj.result;
  } catch(e) {
   // A JSON-RPC contract revert must be passed through rather than mistaken for an endpoint outage.
   if(e.rpcData || /execution reverted|VM execution error/i.test(e.message)) throw e;
   failures.push(e.message);
  } finally {clearTimeout(timeout);}
 }
 throw new Error('Public RPC unavailable or blocked by browser CORS ('+failures.join('; ')+'). Try a browser/network allowing cross-origin RPC.');
}
async function call(to,data){return rpc('eth_call',[{to,data},'latest']);}
async function boolCall(to,data){return BigInt(await call(to,data))!==0n;}
async function uintCall(to,data){return BigInt(await call(to,data));}
const errData=e=>{
 let x=e.rpcData;
 for(let n=0;n<4;n++){
  if(typeof x==='string'){const m=x.match(/0x[0-9a-fA-F]{8,}/);return m?m[0]:'';}
  if(x&&typeof x==='object'){x=x.data||x.originalError||x.result||x.message;continue;}
  break;
 }
 const m=(e.message||'').match(/0x[0-9a-fA-F]{8,}/);return m?m[0]:'';
};
async function guardCheck(recipient, amount) {
 const data=SELECTOR.validate+addr(recipient)+pad(amount);
 try {const result=await call(GUARD,data);if(!/^0x[0-9a-f]*$/i.test(result)||result.length<130)throw new Error('Unexpected PolicyGuard response');return {pass:true,detail:'PolicyGuard.validate: PASS (contract eth_call)'};}
 catch(e){
  const hex=errData(e).slice(0,10).toLowerCase();
  const known={ [SELECTOR.notAllowed]:'RecipientNotAllowed', [SELECTOR.overLimit]:'TransferLimitExceeded', [SELECTOR.daily]:'DailyLimitExceeded', [SELECTOR.zero]:'AmountZero' };
  if(known[hex])return {pass:false,detail:'PolicyGuard.validate: REVERT '+known[hex]+' (contract eth_call)'};
  // Some RPC nodes omit revert data; attempt corroboration with actual guard getters.
  if(/revert/i.test(e.message)){
   const allowed=await boolCall(GUARD,SELECTOR.allow+addr(recipient));
   const max=await uintCall(GUARD,SELECTOR.max);
   const remaining=await uintCall(GUARD,SELECTOR.remaining);
   if(!allowed)return {pass:false,detail:'On-chain allowedRecipients=false; validate reverted (RPC did not expose custom error bytes)'};
   if(amount>max)return {pass:false,detail:'On-chain maxPerTransfer='+fmt(max)+' QUSDC; validate reverted (no custom error bytes)'};
   if(amount>remaining)return {pass:false,detail:'On-chain remainingToday='+fmt(remaining)+' QUSDC; validate reverted (no custom error bytes)'};
  }
  throw e;
 }
}
let running=false;
async function evaluate(){
 if(running)return;running=true;
 const button=text('run');button.disabled=true;button.textContent='Reading mainnet…';
 const lines=['> READ-ONLY MAINNET CHECK — no signing, no broadcast'];
 const title=text('decision-title'),detail=text('decision-detail'),icon=text('decision-icon');
 icon.className='status-icon';icon.textContent='◇'; title.textContent='Querying QIE Mainnet';detail.textContent='';text('signature-status').textContent='Not requested';
 try{
  const key=text('scenario').value, s=SCENARIOS[key];
  const chain=BigInt(await rpc('eth_chainId',[]));
  if(chain!==1990n)throw new Error('Wrong chain: '+chain.toString());
  const block=await rpc('eth_getBlockByNumber',['latest',false]);
  if(!block||!block.timestamp)throw new Error('Cannot read latest block timestamp');
  const now=BigInt(block.timestamp);
  lines.push('> Chain 1990 · block '+parseInt(block.number,16)+' · timestamp '+now.toString());
  const paused=await boolCall(VAULT,SELECTOR.paused);
  lines.push('> Vault paused (on-chain): '+paused);
  const guard=await guardCheck(s.recipient,s.amount);
  lines.push('> '+guard.detail);
  const used=await boolCall(VAULT,SELECTOR.nonce+pad(s.nonce));
  lines.push('> Vault isNonceUsed('+s.nonce+'): '+used+' (contract eth_call)');
  const deadline=s.deadline==='past'?1n:now+3600n;
  const expired=now>deadline;
  lines.push('> Deadline '+deadline+' vs block timestamp '+now+': '+(expired?'EXPIRED':'CURRENT'));
  const eligible=!paused&&guard.pass&&!used&&!expired;
  const reasons=[];if(paused)reasons.push('vault paused');if(!guard.pass)reasons.push(guard.detail);if(used)reasons.push('nonce already used');if(expired)reasons.push('deadline expired');
  title.textContent=eligible?'Eligible for independent owner approval':'Rejected by read-only policy assessment';
  detail.textContent=eligible?'Contract state permits the proposed payment parameters. A valid EIP-712 owner signature and authorized executor are still mandatory.':reasons.join(' · ');
  icon.className='status-icon '+(eligible?'allowed':'blocked');icon.textContent=eligible?'✓':'×';
  text('signature-status').textContent=eligible?'Required — not provided':'Not requested';
  lines.push('> RESULT: '+(eligible?'ELIGIBLE FOR OWNER APPROVAL':'NOT ELIGIBLE'));
  lines.push('> Not an execute() transaction or on-chain reverted payment');
 }catch(e){title.textContent='Live check unavailable';detail.textContent=e.message;icon.textContent='!';lines.push('> UNAVAILABLE: '+e.message);lines.push('> No policy verdict inferred from failed RPC');}
 text('terminal').textContent=lines.join('\n');button.disabled=false;button.textContent='Evaluate policy →';running=false;
}
text('run').addEventListener('click',evaluate);
text('copy-vault').addEventListener('click',async()=>{
 const b=text('copy-vault');try{await navigator.clipboard.writeText(VAULT);b.textContent='Copied ✓'}catch{b.textContent='Select address above to copy'}
});
