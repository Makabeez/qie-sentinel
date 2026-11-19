#!/usr/bin/env python3
"""Unprivileged demo planner. No wallet signing, no transaction submission.

Exercises real on-chain preflight against known security scenarios and stores an
append-only decision record in the same SQLite ledger as the approval queue.
"""
import argparse
import json
import time

from server import KNOWN_RECIPIENT, VAULT, evaluate, snapshot, call
from workflow import connection, submit, proposals, audit

UNKNOWN_RECIPIENT = '0x000000000000000000000000000000000000dEaD'


def available_nonce(start=3, limit=500):
    """Pick a nonce unused on-chain and not reserved in local active proposals."""
    with connection() as con:
        reserved = {r[0] for r in con.execute(
            "SELECT nonce FROM proposals WHERE status IN ('AWAITING_OWNER','SIGNED','SUBMITTING','SUBMITTED','CONFIRMED')")}
    for nonce in range(start, start + limit):
        if nonce not in reserved and not call(VAULT, 'nonce', format(nonce, '064x')):
            return nonce
    raise RuntimeError('Unable to find an available nonce')


def record_expired(recipient, amount, nonce):
    """Record a deliberately expired request as REJECTED; never put it in signing queue."""
    checks = [
        {'name': 'Owner authorization deadline is in the future', 'ok': False},
        {'name': 'Expired intent must never be signed or broadcast', 'ok': False},
    ]
    now = int(time.time())
    import uuid
    proposal_id = str(uuid.uuid4())
    with connection() as con:
        con.execute('''INSERT INTO proposals
            (id,created_at,updated_at,recipient,amount,nonce,deadline,status,checks,error)
            VALUES(?,?,?,?,?,?,?,?,?,?)''',
            (proposal_id,now,now,recipient,amount,nonce,now-60,'REJECTED',json.dumps(checks),
             'Expired authorization: deadline has passed'))
        audit(con, proposal_id, 'PROPOSAL_REJECTED',
              {'scenario':'expired_intent','reason':'deadline expired','checks':checks})
    return {'id':proposal_id, 'status':'REJECTED', 'checks':checks}


def run():
    # Fail closed if RPC is inaccessible or contracts do not match expected deployment.
    state = snapshot()
    nonce = available_nonce()
    deadline = int(time.time()) + 3600
    scenarios = [
        ('approved_small_payment', KNOWN_RECIPIENT, 50000, nonce),
        ('unauthorized_recipient', UNKNOWN_RECIPIENT, 50000, nonce + 1),
        ('oversized_payment', KNOWN_RECIPIENT, max(state['maxPerTransfer'],state['balance'])+1, nonce+2),
        ('replayed_nonce', KNOWN_RECIPIENT, 50000, 1),
    ]
    created = []
    for name, recipient, amount, payment_nonce in scenarios:
        decision = evaluate({'recipient':recipient,'amount':amount,'nonce':payment_nonce})
        # Fail closed: a demo reject scenario MUST be rejected by real preflight.
        if name != 'approved_small_payment' and decision['decision'] != 'REJECT':
            raise RuntimeError(f'Demo scenario {name} unexpectedly passed real chain checks')
        if name == 'approved_small_payment' and decision['decision'] != 'ELIGIBLE_FOR_OWNER_SIGNATURE':
            raise RuntimeError('Approved demo payment is not eligible under live chain rules')
        row = submit(recipient,amount,payment_nonce,deadline,decision)
        with connection() as con:
            audit(con,row['id'],'AGENT_DECISION',{
                'scenario':name, 'decision':decision['decision'],
                'failed_checks':[c['name'] for c in decision['checks'] if not c['ok']],
                'explanation': ('Potential payment; requires an independent owner signature.'
                    if name == 'approved_small_payment' else 'Rejected by live policy preflight; no signature or transfer.')
            })
        created.append({'scenario':name,'id':row['id'],'status':row['status'],
                        'failed_checks':[c['name'] for c in decision['checks'] if not c['ok']]})
    expired = record_expired(KNOWN_RECIPIENT, 50000, nonce+3)
    created.append({'scenario':'expired_intent','id':expired['id'],
                    'status':'REJECTED','failed_checks':['Owner authorization deadline is in the future']})
    return {'mode':'NO_KEYS_NO_TRANSACTIONS','chainId':1990,'vault':VAULT,'scenarios':created}


if __name__=='__main__':
    parser=argparse.ArgumentParser(description='Run an unprivileged, on-chain-grounded security demo')
    parser.add_argument('action', choices=['run'])
    args=parser.parse_args()
    try:
        print(json.dumps(run(),indent=2))
    except Exception as exc:
        parser.exit(1, f'Demo failed without submitting a transaction: {exc}\n')
