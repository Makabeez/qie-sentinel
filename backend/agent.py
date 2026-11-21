"""Phase 4.1: deterministic, proposal-only agent simulator with persistent audit log.

No wallet access, transaction submission, model-driven spending, or user secrets.
"""
import os
import re
import sqlite3
from datetime import datetime, timezone
from pathlib import Path
from threading import Lock
from uuid import uuid4

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

DB_PATH = Path(os.getenv('QIE_AGENT_DB', str(Path(__file__).resolve().parent.parent / 'data' / 'agent_events.sqlite3')))
DB_LOCK = Lock()


def _connect():
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(DB_PATH), timeout=10)
    conn.execute('''CREATE TABLE IF NOT EXISTS agent_events (
        id TEXT PRIMARY KEY, timestamp TEXT NOT NULL, run_id TEXT NOT NULL,
        invoice_id TEXT NOT NULL, recipient TEXT NOT NULL,
        amount_base_units INTEGER NOT NULL, purpose TEXT NOT NULL,
        decision TEXT NOT NULL, reasons TEXT NOT NULL, block_checked INTEGER NOT NULL
    )''')
    return conn


class Invoice(BaseModel):
    invoice_id: str = Field(min_length=3, max_length=60)
    recipient: str
    amount_base_units: int = Field(ge=1, le=10**12)
    purpose: str = Field(min_length=3, max_length=180)


class RunRequest(BaseModel):
    scenario: str = 'demo'


def create_router(snapshot_for, evaluate, recipient):
    router = APIRouter(prefix='/api/agent', tags=['agent'])

    def local_only(request: Request):
        if request.client is None or request.client.host not in {'127.0.0.1', '::1'}:
            raise HTTPException(403, 'Local operator access only')

    @router.get('/events')
    def list_events(request: Request):
        local_only(request)
        with DB_LOCK, _connect() as conn:
            rows = conn.execute('''SELECT id,timestamp,run_id,invoice_id,recipient,
                  amount_base_units,purpose,decision,reasons,block_checked
                  FROM agent_events ORDER BY rowid DESC LIMIT 60''').fetchall()
        keys = ['id','timestamp','run_id','invoice_id','recipient','amount_base_units',
                'purpose','decision','reasons','block_checked']
        return {'items': [{**dict(zip(keys, r)), 'reasons': r[8].split('\n') if r[8] else [],
                           'execution': 'NOT_SUBMITTED'} for r in rows], 'storage': 'sqlite'}

    @router.post('/run')
    def run_demo(request: Request, body: RunRequest):
        local_only(request)
        if body.scenario != 'demo':
            raise HTTPException(422, 'Only the deterministic demo scenario is enabled')
        # The three fixed invoices intentionally demonstrate both positive and negative decisions.
        invoices = [
            Invoice(invoice_id='DEMO-001', recipient=recipient, amount_base_units=250000,
                    purpose='Approved AI compute service (simulated)'),
            Invoice(invoice_id='DEMO-002', recipient=recipient, amount_base_units=2000000,
                    purpose='Oversized infrastructure invoice (simulated)'),
            Invoice(invoice_id='DEMO-003', recipient='0x000000000000000000000000000000000000dEaD',
                    amount_base_units=100000,
                    purpose='Unallowlisted vendor invoice (simulated)'),
        ]
        run_id = str(uuid4())
        entries = []
        # All on-chain reads must succeed before logging any results.
        for inv in invoices:
            if not re.fullmatch(r"0x[0-9a-fA-F]{40}", inv.recipient):
                raise HTTPException(422, 'Invalid invoice recipient')
            try:
                data, snap = snapshot_for(inv.recipient)
            except Exception as exc:
                raise HTTPException(503, f'Agent fail-closed: live state unavailable: {exc}') from exc
            verdict = evaluate(inv.amount_base_units, snap)
            entries.append({'id': str(uuid4()), 'timestamp': datetime.now(timezone.utc).isoformat(),
                            'run_id': run_id, 'invoice_id': inv.invoice_id,
                            'recipient': inv.recipient,
                            'amount_base_units': inv.amount_base_units, 'purpose': inv.purpose,
                            'decision': verdict['decision'], 'reasons': verdict['reasons'],
                            'block_checked': data['block'], 'execution': 'NOT_SUBMITTED'})
        with DB_LOCK, _connect() as conn:
            conn.executemany('''INSERT INTO agent_events
                (id,timestamp,run_id,invoice_id,recipient,amount_base_units,purpose,decision,reasons,block_checked)
                VALUES (?,?,?,?,?,?,?,?,?,?)''', [
                (e['id'], e['timestamp'], e['run_id'], e['invoice_id'], e['recipient'],
                 e['amount_base_units'], e['purpose'], e['decision'], '\n'.join(e['reasons']),
                 e['block_checked']) for e in entries])
        return {'run_id': run_id, 'items': entries, 'broadcast': False, 'owner_approval_required': True}

    return router
