import {validAddress,amountToUnits,unitsToAmount,NETWORK} from './policy.mjs';
export function validateVaultPlan({owner,executor,maxPerPayment,dailyLimit}) {
 const reasons=[];
 if(!validAddress(owner))reasons.push('Connect a valid EVM wallet first');
 if(!validAddress(executor)||/^0x0{40}$/i.test(executor))reasons.push('Provide a nonzero executor wallet');
 if(validAddress(owner)&&validAddress(executor)&&owner.toLowerCase()===executor.toLowerCase())reasons.push('Owner and executor must be different wallets');
 let max=null,daily=null;
 try{max=amountToUnits(maxPerPayment);}catch{reasons.push('Invalid per-payment QUSDC limit');}
 try{daily=amountToUnits(dailyLimit);}catch{reasons.push('Invalid daily QUSDC limit');}
 if(max!==null&&daily!==null&&max>daily)reasons.push('Per-payment limit cannot exceed daily limit');
 return {valid:reasons.length===0,reasons,max,daily};
}
export function deploymentPreview({owner,executor,maxPerPayment,dailyLimit}) {
 const x=validateVaultPlan({owner,executor,maxPerPayment,dailyLimit});
 if(!x.valid)throw new Error(x.reasons.join('; '));
 return {
  schema:'qie-sentinel-vault-creation-preview-v1',
  state:'PREVIEW_ONLY_NOT_DEPLOYED',
  network:{chainId:NETWORK.decimalChainId,name:NETWORK.name},
  proposedContract:'SentinelVaultFactory (v2 experimental, not deployed)',
  owner,executor,
  token:NETWORK.token,
  maxPerTransferRaw:String(x.max),
  dailyLimitRaw:String(x.daily),
  maxPerTransferQUSDC:unitsToAmount(x.max),
  dailyLimitQUSDC:unitsToAmount(x.daily),
  initialAllowlist:[],
  requiresNewFactoryDeployment:true,
  expectedOnChainPermissions:[
   'Only this owner can administer the new vault',
   'Executor only submits separately owner-signed EIP-712 intents',
   'No default recipients are allowlisted',
   'Owner can pause and emergency-recover from own vault'
  ],
  disclaimer:'Local configuration preview only. No contract was created, no owner signature was requested, and no funds were moved. The factory is experimental and unaudited.'
 };
}
