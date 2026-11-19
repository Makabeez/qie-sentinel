#!/usr/bin/env python3
"""Generate a self-contained, read-only hackathon showcase from an exported evidence JSON."""
import argparse
import html
import json
from datetime import datetime, timezone
from pathlib import Path

EXPLORER = 'https://mainnet.qie.digital/tx/'
STYLES = '''
:root{color-scheme:dark;font-family:Inter,ui-sans-serif,system-ui,Segoe UI,sans-serif;background:#090f1d;color:#e8eefc}
*{box-sizing:border-box}body{margin:0;background:radial-gradient(circle at 80% 5%,#183059 0,transparent 34%),#090f1d}
main{max-width:1150px;margin:auto;padding:48px 22px 90px}h1{font-size:clamp(32px,5vw,58px);letter-spacing:-2px;margin:12px 0}
h2{font-size:21px;margin:38px 0 16px}h3{margin:0 0 8px;font-size:15px}.muted{color:#98aac6}.small{font-size:12px}
.eyebrow{color:#79baff;font-size:13px;letter-spacing:2px;font-weight:700}.lede{font-size:17px;max-width:740px;line-height:1.6;color:#b9c9e0}
.badge{display:inline-block;padding:7px 12px;border:1px solid #2e5d4b;border-radius:999px;background:#123125;color:#8ceabb;font-size:12px;margin:12px 8px 0 0}
.note{border-left:3px solid #d7af62;padding:12px 18px;background:#292315;color:#f6deb1;margin:22px 0;font-size:13px;line-height:1.7}
.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:13px;margin:30px 0}
.card{background:#121e32;border:1px solid #273952;border-radius:18px;padding:22px;min-width:0}
.value{font-size:31px;font-weight:750;letter-spacing:-1px;margin-top:9px}.caption{font-size:12px;color:#9badc4;margin-top:5px}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(245px,1fr));gap:14px}.good{color:#74e0aa}.bad{color:#ff9c9c}.pending{color:#f0ce7a}
.pill{font-size:11px;border-radius:7px;padding:4px 7px;background:#20344c;color:#c0d7f6;font-weight:700;display:inline-block}
.row{display:flex;align-items:baseline;justify-content:space-between;gap:15px;flex-wrap:wrap}.address{font-family:ui-monospace,SFMono-Regular,Consolas,monospace;overflow-wrap:anywhere;font-size:12px}
a{color:#91caff;text-decoration:none}a:hover{text-decoration:underline}
table{width:100%;border-collapse:collapse;font-size:13px}th,td{text-align:left;padding:13px;border-bottom:1px solid #2b3b51;vertical-align:top}th{color:#9aafcb;font-size:12px}
.table-wrap{overflow:auto}.foot{margin-top:44px;border-top:1px solid #2b3b51;padding-top:20px;font-size:12px;color:#97abc5}
.timeline{border-left:2px solid #334e6f;padding-left:19px;margin-left:8px}.item{margin:0 0 19px;position:relative}.item:before{content:'';position:absolute;left:-26px;top:5px;width:11px;height:11px;border-radius:50%;background:#7db9f6}
'''

def esc(value):
    return html.escape(str(value), quote=True)

def date(ts):
    try:
        return datetime.fromtimestamp(int(ts), tz=timezone.utc).strftime('%Y-%m-%d %H:%M UTC')
    except (ValueError, TypeError, OverflowError, OSError):
        return 'Unknown'

def short(value, width=12):
    s=str(value or '')
    return s if len(s) <= width+8 else s[:width]+'…'+s[-6:]

REASONS = {
    'Recipient is allowlisted': 'Recipient not authorized',
    'Amount within per-transfer limit': 'Amount exceeds the per-payment limit',
    'Vault has sufficient QUSDC': 'Insufficient vault balance',
    'Amount within daily remaining': 'Daily spending budget exceeded',
    'Nonce has not been used': 'Nonce already used (replay blocked)',
    'Owner authorization deadline is in the future': 'Authorization expired',
    'Expired intent must never be signed or broadcast': 'Expired intent cannot be signed',
    'Vault is active': 'Vault is paused',
}

def build_page(doc, chain_payments=None):
    if doc.get('schema') != 'qie-sentinel-evidence-v1' or doc.get('chain_id') != 1990:
        raise ValueError('Unsupported evidence schema or wrong chain ID')
    proposals=doc.get('proposals')
    events=doc.get('events')
    if not isinstance(proposals,list) or not isinstance(events,list):
        raise ValueError('Missing evidence arrays')
    confirmed=[p for p in proposals if p.get('status')=='CONFIRMED']
    rejected=[p for p in proposals if p.get('status')=='REJECTED']
    pending=[p for p in proposals if p.get('status') in ('AWAITING_OWNER','SIGNED')]
    spent=sum(int(p.get('amount',0)) for p in confirmed)
    hashes={}
    for evt in events:
        if not isinstance(evt,dict):continue
        pid=evt.get('proposal_id')
        detail=evt.get('detail') or {}
        if isinstance(detail,dict) and evt.get('kind') in ('SUBMITTED','CONFIRMED') and detail.get('tx_hash'):
            hashes[pid]=detail['tx_hash']
    for p in confirmed:
        if p.get('tx_hash'):hashes[p['id']]=p['tx_hash']
    def txlink(tx):
        if not isinstance(tx,str) or len(tx)!=66 or not tx.startswith('0x'):
            return '<span class="muted">Receipt hash unavailable</span>'
        try:int(tx[2:],16)
        except ValueError:return '<span class="muted">Invalid hash</span>'
        return f'<a href="{EXPLORER}{esc(tx)}" target="_blank" rel="noopener noreferrer">{esc(short(tx))} ↗</a>'
    rejected_cards=[]
    for p in rejected[-10:][::-1]:
        checks=p.get('checks',[])
        failed=[c.get('name','Unknown rule') for c in checks if isinstance(c,dict) and c.get('ok') is False]
        reason=', '.join(REASONS.get(name,name) for name in failed) or p.get('error') or 'Policy rejected'
        rejected_cards.append(f'<div class="card"><div class="row"><span class="pill">REJECTED</span><span class="muted small">Nonce {esc(p.get("nonce","?"))}</span></div><h3 style="margin-top:17px" class="bad">{esc(reason)}</h3><div class="caption">{int(p.get("amount",0))/1e6:.6f} QUSDC · {esc(short(p.get("recipient",""),9))}</div><div class="caption">{esc(date(p.get("created_at")))}</div></div>')
    rows=[]
    for p in sorted(proposals,key=lambda x:x.get('created_at',0),reverse=True)[:25]:
        status=p.get('status','UNKNOWN')
        tx=hashes.get(p.get('id'))
        klass='good' if status=='CONFIRMED' else ('bad' if status=='REJECTED' else 'pending')
        rows.append(f'<tr><td><span class="{klass}">{esc(status)}</span></td><td>{int(p.get("amount",0))/1e6:.6f}</td><td>{esc(p.get("nonce","?"))}</td><td class="address">{esc(short(p.get("recipient",""),10))}</td><td>{esc(date(p.get("created_at")))}</td><td>{txlink(tx) if tx else "—"}</td></tr>')
    chain_cards=[]
    if chain_payments is not None:
        if not isinstance(chain_payments,dict) or not isinstance(chain_payments.get('payments'),list):
            raise ValueError('Invalid on-chain payment snapshot')
        for item in chain_payments['payments'][:30]:
            tx=item.get('txHash')
            try:
                if not isinstance(tx,str) or len(tx)!=66 or not tx.startswith('0x'):continue
                int(tx[2:],16)
                amount=int(item['amount']);block=int(item['block']);nonce=int(item['nonce'])
                if not 0 <= amount < 2**256:continue
            except (ValueError,KeyError,TypeError):continue
            chain_cards.append(f'<tr><td>{amount/1e6:.6f} QUSDC</td><td>{nonce}</td><td>{block}</td><td>{txlink(tx)}</td></tr>')
    chain_section = ('<h2>On-chain payment events (RPC snapshot)</h2><div class="card table-wrap"><table><thead><tr><th>Amount</th><th>Nonce</th><th>Block</th><th>Explorer</th></tr></thead><tbody>'+
      (''.join(chain_cards) if chain_cards else '<tr><td colspan="4">No chain events in supplied snapshot</td></tr>')+
      '</tbody></table></div><p class="caption">Events reflect the RPC lookback window at capture time. Explorer links are for independent verification.</p>') if chain_payments is not None else ''
    timeline=[]
    for evt in events[-12:][::-1]:
        timeline.append(f'<div class="item"><span class="pill">{esc(evt.get("kind","EVENT"))}</span><div class="caption">{esc(date(evt.get("at")))} · {esc(short(evt.get("proposal_id",""),8))}</div></div>')
    return f'''<!doctype html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="referrer" content="no-referrer"><title>QIE Sentinel — Mainnet Security Showcase</title><style>{STYLES}</style></head><body><main>
<div class="eyebrow">QIE DIGITAL · MAINNET 1990 · SECURITY SHOWCASE</div>
<h1>Autonomous proposals.<br><span style="color:#7bbcff">Human-controlled funds.</span></h1>
<p class="lede">QIE Sentinel demonstrates rule-based agent payment proposals, on-chain guardrails, owner-signed EIP-712 authorization, replay protection, and independently submitted executor transactions.</p>
<span class="badge">✓ Mainnet payment receipts</span><span class="badge">✓ Owner/executor key separation</span><span class="badge">✓ Auditable policy decisions</span>
<div class="stats"><div class="card"><div class="muted small">Confirmed ledger payments</div><div class="value good">{len(confirmed)}</div><div class="caption">Local proposal records backed by receipt hashes</div></div>
<div class="card"><div class="muted small">Rejected proposals</div><div class="value bad">{len(rejected)}</div><div class="caption">Off-chain security preflight</div></div>
<div class="card"><div class="muted small">Awaiting independent approval</div><div class="value pending">{len(pending)}</div><div class="caption">No signature from autonomous agent</div></div>
<div class="card"><div class="muted small">Confirmed ledger volume</div><div class="value">{spent/1e6:.3f}</div><div class="caption">QUSDC represented in exported proposal ledger</div></div></div>
<div class="note"><strong>Evidence scope:</strong> This report is generated from the local SQLite evidence export, not a live chain query. Off-chain rejected proposals are <strong>not</strong> failed on-chain transactions. Confirmed transactions should be verified using their explorer links. Counts exclude earlier payments not captured in this proposal ledger. Export time: {esc(date(doc.get('generated_at')))}.</div>
<h2>Live-demo security cases</h2><div class="grid">{''.join(rejected_cards) if rejected_cards else '<div class="card muted">No rejected proposals in export.</div>'}</div>
<h2>Proposal and transaction history</h2><div class="card table-wrap"><table><thead><tr><th>Status</th><th>QUSDC</th><th>Nonce</th><th>Recipient</th><th>Proposed</th><th>Receipt</th></tr></thead><tbody>{''.join(rows) if rows else '<tr><td colspan="6">No proposals in evidence file.</td></tr>'}</tbody></table></div>
{chain_section}<h2>Approval boundary</h2><div class="grid"><div class="card"><h3>01 · Agent</h3><p class="muted">Creates structured payment requests and checks live vault policy. Does not hold signing keys.</p></div><div class="card"><h3>02 · Owner</h3><p class="muted">Independently authorizes an exact token, recipient, amount, nonce, deadline and executor using an EIP-712 signature.</p></div><div class="card"><h3>03 · Executor</h3><p class="muted">Submits the approved intent. The vault rechecks signature, nonce and PolicyGuard before transferring QUSDC.</p></div></div>
<h2>Recent audit activity</h2><div class="card"><div class="timeline">{''.join(timeline) if timeline else '<div class="muted">No audit events.</div>'}</div></div>
<div class="foot">QIE Sentinel · Standalone local evidence report · Generated without private keys or transaction submission · Do not confuse off-chain eligibility with final on-chain enforcement.</div>
</main></body></html>'''

def main():
    ap=argparse.ArgumentParser(description='Render a static security showcase from the Sentinel evidence export')
    ap.add_argument('--input',default='sentinel-evidence.json')
    ap.add_argument('--output',default='sentinel-showcase.html')
    ap.add_argument('--chain-payments',help='Optional API /api/payments JSON snapshot (read-only)')
    args=ap.parse_args()
    source=Path(args.input)
    if not source.is_file():raise SystemExit(f'Evidence file not found: {source}')
    doc=json.loads(source.read_text(encoding='utf-8'))
    dest=Path(args.output)
    dest.parent.mkdir(parents=True,exist_ok=True)
    chain=json.loads(Path(args.chain_payments).read_text(encoding='utf-8')) if args.chain_payments else None
    dest.write_text(build_page(doc,chain),encoding='utf-8')
    print('Read-only hackathon showcase generated:',dest.resolve())

if __name__=='__main__':main()
