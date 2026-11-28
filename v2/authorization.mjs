// QIE Sentinel 2.2 — exact EIP-712 envelope, intentionally UNSIGNED.
// Matches src/SentinelVault.sol's Payment and EIP712("QIE Sentinel Vault", "1").
// This module contains no wallet signing or broadcast capability.
import {NETWORK,validAddress,amountToUnits,unitsToAmount} from './policy.mjs';
export const DEMO_OWNER='0x395215ab5Dde403801868fa850b89e305F01725E';
export const DEMO_EXECUTOR='0xD0612b00030AC351EAb6A7800E4b7679e3f7D95A';
const ZERO='0x0000000000000000000000000000000000000000';
const uint=value=>{
 const s=String(value);
 if(!/^(0|[1-9][0-9]*)$/.test(s))throw new Error('Expected canonical unsigned integer');
 const n=BigInt(s);
 if(n>=(1n<<256n))throw new Error('uint256 overflow');
 return s;
};
const address=(value,name)=>{
 if(!validAddress(value)||value.toLowerCase()===ZERO)throw new Error('Invalid '+name+' address');
 return value;
};
export const FIELDS=Object.freeze([
 {name:'token',type:'address'},
 {name:'recipient',type:'address'},
 {name:'amount',type:'uint256'},
 {name:'nonce',type:'uint256'},
 {name:'deadline',type:'uint256'},
 {name:'executor',type:'address'}
]);
export function makeUnsignedEnvelope({review,viewer,owner=DEMO_OWNER,executor=DEMO_EXECUTOR}){
 if(!review||review.result!=='ELIGIBLE_FOR_INDEPENDENT_OWNER_APPROVAL'||review.validated!==true||review.paused!==false||review.nonceUsed!==false)
  throw new Error('A recent, successful read-only policy review is required');
 if(!validAddress(viewer)||viewer.toLowerCase()!==owner.toLowerCase()||owner.toLowerCase()!==DEMO_OWNER.toLowerCase())
  throw new Error('Only the recorded demonstration-vault owner may prepare this specific vault envelope');
 if(review.network!==1990||review.contract?.toLowerCase()!==NETWORK.vault.toLowerCase())
  throw new Error('Wrong chain or vault in review');
 if(!validAddress(executor)||executor.toLowerCase()!==DEMO_EXECUTOR.toLowerCase())
  throw new Error('Executor differs from recorded demonstration vault executor');
 const amount=amountToUnits(String(review.amountQUSDC));
 const nonce=uint(review.nonce),deadline=uint(review.deadline),block=uint(review.block),chainTimestamp=uint(review.chainTimestamp);
 if(BigInt(deadline)<BigInt(chainTimestamp))throw new Error('Deadline had already expired at review block');
 const recipient=address(review.recipient,'recipient');
 const message={token:NETWORK.token,recipient,amount:String(amount),nonce,deadline,executor};
 const typedData={
  types:{
   EIP712Domain:[
    {name:'name',type:'string'},
    {name:'version',type:'string'},
    {name:'chainId',type:'uint256'},
    {name:'verifyingContract',type:'address'}
   ],
   Payment:FIELDS.map(x=>({...x}))
  },
  primaryType:'Payment',
  domain:{
   name:'QIE Sentinel Vault',version:'1',
   chainId:1990,verifyingContract:NETWORK.vault
  },
  message
 };
 return {
  schema:'qie-sentinel-unsigned-authorization-preview-v1',
  state:'UNSIGNED_NOT_AUTHORIZED',
  reviewBlock:block,
  reviewedChainTimestamp:chainTimestamp,
  recordedOwner:owner,
  ownerMatchesConnectedWallet:true,
  typedData,
  humanReadable:{
   recipient,
   amountQUSDC:unitsToAmount(amount),
   nonce,
   deadlineUTC:new Date(Number(BigInt(deadline))*1000).toISOString(),
   intendedExecutor:executor
  },
  notSigned:true,
  notBroadcast:true,
  signature:null,
  disclaimer:'READ-ONLY UNSIGNED EIP-712 REVIEW. No wallet signature, transaction or approval has occurred. Owner/executor may change after the snapshot. Never interpret this JSON as an authorization. Purpose or invoice notes are NOT signed by the Solidity Payment struct.'
 };
}
export function matchesProposal(envelope,{recipient,amount,nonce,deadline}){
 if(!envelope||envelope.state!=='UNSIGNED_NOT_AUTHORIZED')return false;
 try{
  const m=envelope.typedData.message;
  return recipient.toLowerCase()===m.recipient.toLowerCase() &&
    String(amountToUnits(String(amount)))===m.amount &&
    uint(nonce)===m.nonce &&
    uint(deadline)===m.deadline;
 }catch{return false;}
}
