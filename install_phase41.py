"""Safely install Phase 4.1 without replacing the working Phase 4 source files."""
from pathlib import Path

root = Path(__file__).resolve().parent
main = root / 'backend' / 'main.py'
html = root / 'web' / 'index.html'
s = main.read_text()
h = html.read_text()
if 'create_agent_router' in s or 'id="agent-run"' in h:
    raise SystemExit('Phase 4.1 already installed; no changes made')
assert 'from backend.policy import Snapshot, evaluate' in s, 'Unexpected main.py import layout'
assert 'app = FastAPI(' in s, 'Unexpected app layout'
assert '</section></div>' in h, 'Unexpected HTML layout'
assert 'refresh();setInterval(refresh,15000);' in h, 'Unexpected dashboard refresh layout'
assert (root / 'backend' / 'agent.py').is_file(), 'backend/agent.py missing'

s = s.replace('from backend.policy import Snapshot, evaluate',
              'from backend.policy import Snapshot, evaluate\nfrom backend.agent import create_router as create_agent_router', 1)
s += '\n# Phase 4.1: local, proposal-only invoice agent and persistent audit history.\n'
s += 'app.include_router(create_agent_router(snapshot_for, evaluate, RECIPIENT))\n'

block = '''
<section class="panel" style="margin-top:16px" id="agent-panel">
  <h2>Autonomous agent lab <small>(simulation · no fund movement)</small></h2>
  <p class="muted">Run three simulated invoices through <b>live QIE Mainnet guardrails</b>. All results are logged in SQLite; no signatures or broadcasts.</p>
  <button id="agent-run" type="button">Run invoice agent</button>
  <p class="muted" id="agent-feedback" role="status">Ready to evaluate three simulated invoices.</p>
  <div id="agent-events" class="muted">Loading agent audit history…</div>
</section>
'''
h = h.replace('</section></div>', '</section></div>' + block, 1)
script = '''
async function refreshAgent(){
 try{
  const d=await get('/api/agent/events');
  document.getElementById('agent-events').innerHTML=d.items.length?
   d.items.slice(0,18).map(x=>`<div class="item"><span class="status ${x.decision==='BLOCKED'?'bad':'good'}">${esc(x.decision)}</span> · <b>${esc(x.invoice_id)}</b> · ${fmt(x.amount_base_units)} QUSDC<br><span class="muted">${esc(x.purpose)} · block ${esc(x.block_checked)}</span>${x.reasons.length?'<br>'+x.reasons.map(esc).join('; '):''}<br><small>Audit only · Not submitted on-chain</small></div>`).join(''):
   'No agent runs yet.';
 }catch(e){document.getElementById('agent-events').textContent='Agent audit unavailable: '+e.message}
}
document.getElementById('agent-run').addEventListener('click',async()=>{
 const btn=document.getElementById('agent-run'),feedback=document.getElementById('agent-feedback');
 btn.disabled=true;feedback.textContent='Reading live policy and evaluating invoices…';
 try{
  const r=await fetch('/api/agent/run',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({scenario:'demo'})});
  const d=await r.json();if(!r.ok)throw Error(d.detail||r.status);
  const blocked=d.items.filter(x=>x.decision==='BLOCKED').length;
  feedback.textContent=`Processed ${d.items.length} simulated invoices · ${blocked} blocked · ${d.items.length-blocked} eligible for owner signature. No payment submitted.`;
  await refreshAgent();
 }catch(e){feedback.textContent='Agent run failed closed: '+e.message}
 finally{btn.disabled=false}
});
refreshAgent();setInterval(refreshAgent,15000);
'''
h = h.replace('refresh();setInterval(refresh,15000);', script + '\nrefresh();setInterval(refresh,15000);', 1)

for p in (main, html):
    backup = p.with_suffix(p.suffix + '.phase40.bak')
    if not backup.exists():
        backup.write_bytes(p.read_bytes())
main.write_text(s)
html.write_text(h)
print('Phase 4.1 installed: invoice agent / SQLite audit / dashboard panel')
