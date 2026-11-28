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

test('local vault preview never waits for a wallet RPC and invalidates on chain changes',()=>{
 const app=read('./app.mjs');
 const section=app.slice(app.indexOf('async function generatePlan('),app.indexOf("$('generate-plan').addEventListener"));
 assert.ok(section.includes('plan=deploymentPreview('));
 assert.ok(!section.includes('provider.request('));
 assert.ok(!section.includes('await provider.'));
 const chain=app.slice(app.indexOf("provider?.on?.('chainChanged'"),app.indexOf('function clearReport('));
 assert.match(chain,/resetPlan\(\)/);
 assert.match(chain,/\$\('new-owner'\)\.value=''/);
});

test('2.2 EIP-712 preview is unsigned and requires a live eligible review',()=>{
 const html=read('./index.html'),app=read('./app.mjs'),auth=read('./authorization.mjs');
 assert.match(html,/id="prepare-auth"/);
 assert.match(html,/id="download-auth"/);
 assert.match(html,/UNSIGNED PREVIEW|UNSIGNED PREVIEW|UNSIGNED|NO SIGNING/);
 assert.match(app,/makeUnsignedEnvelope\(\{review:report,viewer,owner:DEMO_OWNER\}\)/);
 assert.match(app,/matchesCurrentReview\(\)/);
 assert.match(app,/\$\(id\)\.addEventListener\('input'/);
 assert.match(app,/clearReport\(\)/);
 assert.match(app,/link\.download='sentinel-v2-unsigned-eip712\.json'/);
 assert.match(auth,/UNSIGNED_NOT_AUTHORIZED/);
 assert.ok(!/eth_sendTransaction|eth_signTypedData|personal_sign|eth_sendRawTransaction/.test(app));
});

test('plan resets clear stale successful labels and edited fields invalidate generated plans',()=>{
 const app=read('./app.mjs');
 const fn=app.slice(app.indexOf('function resetPlan('),app.indexOf('async function generatePlan('));
 assert.match(fn,/\$\('plan-feedback'\)\.textContent=message/);
 for(const id of ['new-executor','new-max','new-daily'])
  assert.ok(fn.includes("'"+id+"'"));
 assert.match(fn,/Configuration changed\. Generate a new deployment preview\./);
});
