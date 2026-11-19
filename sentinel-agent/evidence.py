#!/usr/bin/env python3
"""Export a privacy-safe, read-only audit bundle for hackathon evidence."""
import argparse
import json
import time
from pathlib import Path

from workflow import connection


def build_report():
    with connection() as con:
        proposal_rows = con.execute('''SELECT id,created_at,updated_at,recipient,amount,nonce,deadline,status,checks,digest,tx_hash,error FROM proposals ORDER BY created_at,id''').fetchall()
        audit_rows = con.execute('SELECT id,at,proposal_id,kind,detail FROM audit ORDER BY id').fetchall()
    items=[]
    for row in proposal_rows:
        r=dict(row)
        r['checks']=json.loads(r['checks'])
        items.append(r)
    events=[]
    for row in audit_rows:
        r=dict(row)
        r['detail']=json.loads(r['detail'])
        events.append(r)
    return {
        'schema':'qie-sentinel-evidence-v1',
        'generated_at':int(time.time()),
        'chain_id':1990,
        'note':'Off-chain preflight rejections are NOT on-chain failed transactions. Confirm on-chain receipts independently.',
        'counts':{s:sum(p['status']==s for p in items) for s in sorted({p['status'] for p in items})},
        'proposals':items,
        'events':events,
    }


def main():
    ap=argparse.ArgumentParser(description='Export public audit evidence, excluding signatures and keystore data')
    ap.add_argument('--output',default='sentinel-evidence.json')
    args=ap.parse_args()
    dest=Path(args.output).resolve()
    dest.parent.mkdir(parents=True,exist_ok=True)
    dest.write_text(json.dumps(build_report(),indent=2)+'\n',encoding='utf-8')
    print('Audit evidence exported:',dest)
    print('No owner signature or wallet keystore fields included.')

if __name__=='__main__':
    main()
