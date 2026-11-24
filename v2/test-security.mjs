import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const read=(name)=>readFileSync(new URL(name,import.meta.url),'utf8');
test('read-only browser has no wallet signing, approvals or broadcasts',()=>{
 const app=read('./app.mjs');
 for(const disallowed of ['eth_sendTransaction','eth_sendRawTransaction','eth_signTypedData','personal_sign','wallet_switchEthereumChain','wallet_addEthereumChain','approve(']){
  assert.equal(app.includes(disallowed),false,'Forbidden browser operation '+disallowed);
 }
 assert.match(app,/eth_requestAccounts/);
 assert.match(app,/eth_chainId/);
 assert.match(app,/eth_call/);
 assert.match(app,/eth_getBlockByNumber/);
});
test('onboarding cannot deploy or sign',()=>{
 const app=read('./app.mjs'),plan=read('./onboarding.mjs');
 assert.match(app,/PREVIEW_ONLY|deploymentPreview/);
 assert.match(plan,/PREVIEW_ONLY_NOT_DEPLOYED/);
 assert.match(plan,/requiresNewFactoryDeployment:true/);
 assert.ok(!/eth_sendTransaction|eth_signTypedData|personal_sign/.test(plan));
});
test('browser is explicit about demo-vault boundaries',()=>{
 const html=read('./index.html');
 for(const disclosure of ['NOT DEPLOYED','No transaction capability','existing demonstration vault','does not bind this field'])
  assert.ok(html.includes(disclosure),disclosure);
});

test('deployment preview always has a clickable control and visible feedback',()=>{
 const html=read('./index.html');
 const app=read('./app.mjs');
 assert.match(html,/id="generate-plan" type="button"/);
 assert.match(html,/id="plan-feedback" role="status"/);
 assert.match(app,/\$\('generate-plan'\)\.addEventListener\('click',generatePlan\)/);
 assert.match(app,/\$\('plan-feedback'\)\.textContent='Action needed: '/);
 assert.match(app,/button\.disabled=false/);
});
