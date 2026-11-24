// QIE Sentinel v2 prototype: pure checks, no signing or transaction methods.
export const NETWORK = Object.freeze({
  chainId: '0x7c6', decimalChainId: 1990,
  name: 'QIE Mainnet', rpc: 'https://rpc1mainnet.qie.digital',
  vault: '0xb752F05a55059C89a43a289d5d055F303B6DD96E',
  guard: '0x532Ee81939386E23b8c58076e643D9FCe489F15C',
  token: '0x3F43DA82eC9A4f5285F10FaF1F26EcA7319E5DA5',
  decimals: 6
});
export const SELECTORS = Object.freeze({
 validate:'0x98e0ae14', nonce:'0x5d00bb12', paused:'0x5c975abb',
 remaining:'0xfc3c5515', max:'0xd1129bf3', balance:'0xb69ef8a8',
 allowed:'0x4df6d6cc',
 notAllowed:'0x6ee9124e', overLimit:'0x4cf7e6a3',
 daily:'0xef664d6a', zero:'0xcbca5aa2'
});
export function validAddress(v) {return typeof v==='string' && /^0x[\da-fA-F]{40}$/.test(v);}
export function amountToUnits(v){
 if(typeof v!=='string'||!/^\d{1,12}(?:\.\d{1,6})?$/.test(v))throw new Error('Enter a positive QUSDC amount with up to six decimals.');
 const [whole,frac='']=v.split('.');
 const n=BigInt(whole)*1000000n+BigInt(frac.padEnd(6,'0'));
 if(n<=0n || n>1000000000000n)throw new Error('Amount must be greater than zero and no more than 1,000,000 QUSDC.');
 return n;
}
export function unitsToAmount(n){const x=BigInt(n);return (x/1000000n).toString()+'.'+(x%1000000n).toString().padStart(6,'0');}
export function encodedCall(selector,args=[]){return selector+args.map((v)=> (typeof v==='string'&&validAddress(v)?v.slice(2):BigInt(v).toString(16)).toLowerCase().padStart(64,'0')).join('');}
export function errorCode(err) {
 let v=err?.data??err?.error?.data??err?.message??'';
 for(let i=0;i<4;i++){if(typeof v==='string'){const m=v.match(/0x[\da-fA-F]{8,}/);return m?m[0].slice(0,10).toLowerCase():'';}
 if(!v||typeof v!=='object')break;v=v.data??v.originalError??v.result??v.message;}
 return '';
}
export function reasonForRevert(err){
 const c=errorCode(err);
 return ({[SELECTORS.notAllowed]:'Recipient is not on the vault allowlist',
 [SELECTORS.overLimit]:'Payment exceeds the vault per-transfer limit',
 [SELECTORS.daily]:'Payment exceeds the remaining daily budget',
 [SELECTORS.zero]:'Payment amount is zero'})[c]??null;
}
export function assess({paused,validated,nonceUsed,deadline,blockTime,balance,amount}){
 const reasons=[];
 if(paused)reasons.push('Vault is paused');
 if(!validated)reasons.push('PolicyGuard rejected recipient, amount or budget');
 if(nonceUsed)reasons.push('Nonce already used');
 // SentinelVault.execute checks block.timestamp > deadline, so equality remains valid.
 if(BigInt(deadline)<BigInt(blockTime))reasons.push('Intent deadline has expired');
 if(BigInt(amount)>BigInt(balance))reasons.push('Insufficient demonstration vault QUSDC balance');
 return {eligible:reasons.length===0,reasons};
}
export function proposalEvidence({recipient,amount,nonce,deadline,block,account,results}){
 return {schema:'qie-sentinel-read-only-review-v1',network:1990,contract:NETWORK.vault,
 recipient,amountQUSDC:unitsToAmount(amount),nonce:String(nonce),
 deadline:String(deadline),block:String(block),viewer:account||null,
 result:results.eligible?'ELIGIBLE_FOR_INDEPENDENT_OWNER_APPROVAL':'NOT_ELIGIBLE',
 reasons:[...results.reasons],
 disclaimer:'Read-only review; not owner authorization, signature, or transaction. Uses the demonstration vault, not the connected wallet treasury.'};
}
