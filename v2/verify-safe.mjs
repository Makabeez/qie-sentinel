import {NETWORK,SELECTORS,encodedCall} from './policy.mjs';
import {VERIFY_SELECTORS,encodeDigestCall,parseAddressWord,parseWord,evaluateDigestSnapshot} from './freshness.mjs';
const $=id=>document.getElementById(id);
let evidence=null;
function note(title,message){$('verify-title').textContent=title;$('verify-summary').textContent=message;$('verify-feedback').textContent=message;}
function fact(label,value){const line=document.createElement('div');line.className='fact';const a=document.createElement('span');a.textContent=label;const b=document.createElement('strong');b.textContent=String(value);line.append(a,b);$('verify-facts').append(line);}
async function rpc(method,params){
 const ctrl=new AbortController(),timeout=setTimeout(()=>ctrl.abort(),10000);
 try{
  const r=await fetch(NETWORK.rpc,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({jsonrpc:'2.0',id:29,method,params}),signal:ctrl.signal,cache:'no-store'});
  if(!r.ok)throw new Error('RPC HTTP '+r.status);
  const data=await r.json();
  if(data.error)throw new Error('RPC '+(data.error.message||'contract revert'));
  if(data.result===undefined||data.result===null)throw new Error('Missing RPC result');
  return data.result;
 }finally{clearTimeout(timeout);}
}
const call=(address,data,block)=>rpc('eth_call',[{to:address,data},block]);
const num=async(address,data,block)=>parseWord(await call(address,data,block),'uint256');
const addr=async(address,data,block)=>parseAddressWord(await call(address,data,block),'address');
async function policy(recipient,amount,block){
 try{
  const out=await call(NETWORK.guard,encodedCall(SELECTORS.validate,[recipient,BigInt(amount)]),block);
  if(!/^0x[0-9a-f]{128}$/i.test(out))throw new Error('Malformed PolicyGuard result');
  return true;
 }catch(error){if(/revert/i.test(String(error?.message||'')))return false;throw error;} // RPC failures are unverifiable, not policy rejections.
}
async function verify(packet){
 const digestCalldata=encodeDigestCall(packet);
 if(packet.schema!=='qie-sentinel-unsigned-authorization-preview-v1')
  throw new Error('Incorrect unsigned packet schema');
 const chain=BigInt(await rpc('eth_chainId',[]));
 if(chain!==1990n)throw new Error('Wrong RPC chain; expected QIE Mainnet 1990');
 const block=await rpc('eth_getBlockByNumber',['latest',false]);
 if(!/^0x[0-9a-f]+$/i.test(block?.number||'')||!/^0x[0-9a-f]+$/i.test(block?.timestamp||''))throw new Error('Invalid latest block');
 const tag=block.number;
 const m=packet.typedData.message;
 const [owner,executor,token,guard,paused,nonceUsed,balance,digest,domainSeparator,code,policyPass]=await Promise.all([
  addr(NETWORK.vault,VERIFY_SELECTORS.owner,tag),
  addr(NETWORK.vault,VERIFY_SELECTORS.executor,tag),
  addr(NETWORK.vault,VERIFY_SELECTORS.token,tag),
  addr(NETWORK.vault,VERIFY_SELECTORS.guard,tag),
  num(NETWORK.vault,VERIFY_SELECTORS.paused,tag).then(n=>n!==0n),
  num(NETWORK.vault,encodedCall(VERIFY_SELECTORS.nonce,[BigInt(m.nonce)]),tag).then(n=>n!==0n),
  num(NETWORK.token,encodedCall('0x70a08231',[NETWORK.vault]),tag),
  call(NETWORK.vault,digestCalldata,tag),
  call(NETWORK.vault,VERIFY_SELECTORS.domainSeparator,tag),
  rpc('eth_getCode',[NETWORK.vault,tag]),
  policy(m.recipient,m.amount,tag)
 ]);
 const snapshot={chainId:1990,vault:NETWORK.vault,owner,executor,token,guard,paused,nonceUsed,
  balance,policyPass,timestamp:BigInt(block.timestamp),block:tag,digest,domainSeparator,
  codeExists:typeof code==='string'&&code.length>4,
  }; // No wallet connection here. Current wallet ownership is NOT authenticated.
 const result=evaluateDigestSnapshot(packet,snapshot);
 return {...result,nonceUsed,paused,policyPass,balanceRaw:balance.toString(),
  ownerAuthentication:'NOT_PERFORMED — this page does not connect to a wallet',
  importedPacketIsUserControlled:true,
  verificationType:'contract paymentDigest and pinned state reads, NOT signature verification'};
}
$('verify-form').addEventListener('submit',async e=>{
 e.preventDefault();evidence=null;$('download-evidence').disabled=true;$('verify-facts').replaceChildren();$('evidence-json').textContent='Checking…';
 const btn=$('verify-btn');btn.disabled=true;note('Checking on-chain state','Reading a pinned QIE Mainnet block, without signing or broadcasting.');
 try{
  const file=$('packet-file').files?.[0];if(!file)throw new Error('Choose an unsigned packet JSON');
  if(file.size>100000)throw new Error('JSON exceeds 100 kB limit');
  const packet=JSON.parse(await file.text());
  evidence=await verify(packet);
  $('block-label').textContent='BLOCK '+BigInt(evidence.block).toString();
  const good=evidence.checksPassed;
  note(good?'CURRENT UNSIGNED · NOT AUTHORIZED':'STALE OR BLOCKED',
   good?'Contract digest and current policy checks succeeded. No signature has been verified.':evidence.reasons.join(' · '));
  for(const [label,value] of [
   ['Vault owner',evidence.recordedOwner],['Executor',evidence.recordedExecutor],
   ['Payment digest (contract)',evidence.onchainPaymentDigest],['Domain separator',evidence.onchainDomainSeparator],
   ['PolicyGuard',evidence.policyPass?'PASS':'NOT CONFIRMED'],['Nonce used',evidence.nonceUsed?'YES':'NO'],
   ['Vault paused',evidence.paused?'YES':'NO'],['Signature status','NOT VERIFIED'],['Transaction','NOT BROADCAST']])fact(label,value);
  $('evidence-json').textContent=JSON.stringify(evidence,null,2);
  $('download-evidence').disabled=false;
 }catch(error){
  note('UNVERIFIABLE — FAIL CLOSED',String(error.message||error));
  $('block-label').textContent='NO VERIFIED BLOCK';
  $('evidence-json').textContent='No trusted evidence produced. No authorization or transaction.';
 }finally{btn.disabled=false;}
});
$('download-evidence').addEventListener('click',()=>{
 if(!evidence)return;
 const url=URL.createObjectURL(new Blob([JSON.stringify(evidence,null,2)+'\n'],{type:'application/json'}));
 const a=document.createElement('a');a.href=url;a.download='sentinel-v2-onchain-verification.json';a.click();
 setTimeout(()=>URL.revokeObjectURL(url),1000);
});
