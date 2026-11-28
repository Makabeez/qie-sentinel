"""Local proposal ledger. No keys are loaded by the web process."""
import json
import os
import sqlite3
import time
import uuid
from contextlib import contextmanager
from pathlib import Path

DB = Path(os.environ.get('SENTINEL_DB', str(Path(__file__).resolve().parent / 'data' / 'sentinel.sqlite3')))


@contextmanager
def connection():
    """Commit on success, roll back on error, and ALWAYS close.

    sqlite3's own `with con:` only manages the transaction; it never closes the
    handle, so the previous version leaked one connection per HTTP request.
    """
    con = _open()
    try:
        with con:
            yield con
    finally:
        con.close()


def _open():
    DB.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(str(DB), timeout=10)
    con.row_factory = sqlite3.Row
    con.execute('PRAGMA busy_timeout=10000')
    con.execute('PRAGMA journal_mode=WAL')
    con.executescript('''
    CREATE TABLE IF NOT EXISTS proposals (
      id TEXT PRIMARY KEY, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
      recipient TEXT NOT NULL, amount INTEGER NOT NULL, nonce INTEGER NOT NULL,
      deadline INTEGER NOT NULL, status TEXT NOT NULL, checks TEXT NOT NULL,
      digest TEXT, signature TEXT, tx_hash TEXT, error TEXT
    );
    CREATE UNIQUE INDEX IF NOT EXISTS uniq_active_nonce ON proposals(nonce)
      WHERE status IN ('AWAITING_OWNER','SIGNED','SUBMITTING','SUBMITTED','CONFIRMED');
    CREATE TABLE IF NOT EXISTS audit (
      id INTEGER PRIMARY KEY AUTOINCREMENT, at INTEGER NOT NULL,
      proposal_id TEXT, kind TEXT NOT NULL, detail TEXT NOT NULL
    );
    ''')
    return con


def audit(con, proposal_id, kind, detail):
    con.execute('INSERT INTO audit(at,proposal_id,kind,detail) VALUES(?,?,?,?)',
                (int(time.time()), proposal_id, kind, json.dumps(detail, separators=(',', ':'))))


def get(proposal_id):
    with connection() as con:
        row = con.execute('SELECT * FROM proposals WHERE id=?', (proposal_id,)).fetchone()
    if row is None:
        raise ValueError('Proposal not found')
    return dict(row)


def proposals(limit=50):
    with connection() as con:
        rows = con.execute('SELECT id,created_at,updated_at,recipient,amount,nonce,deadline,status,checks,digest,tx_hash,error FROM proposals ORDER BY created_at DESC LIMIT ?', (limit,)).fetchall()
    return [dict(row) for row in rows]


def events(limit=80):
    with connection() as con:
        rows=con.execute('SELECT id,at,proposal_id,kind,detail FROM audit ORDER BY id DESC LIMIT ?', (limit,)).fetchall()
    return [dict(row) for row in rows]


def submit(recipient, amount, nonce, deadline, evaluation):
    now = int(time.time())
    if deadline <= now + 60 or deadline > now + 86400:
        raise ValueError('Deadline must be 1 minute to 24 hours in the future')
    status = 'AWAITING_OWNER' if evaluation['decision'] == 'ELIGIBLE_FOR_OWNER_SIGNATURE' else 'REJECTED'
    proposal_id = str(uuid.uuid4())
    with connection() as con:
        try:
            con.execute('INSERT INTO proposals(id,created_at,updated_at,recipient,amount,nonce,deadline,status,checks) VALUES(?,?,?,?,?,?,?,?,?)',
                        (proposal_id,now,now,recipient,amount,nonce,deadline,status,json.dumps(evaluation['checks'])))
        except sqlite3.IntegrityError as exc:
            raise ValueError('Another active proposal already reserves this nonce') from exc
        audit(con, proposal_id, 'PROPOSAL_'+status, {'recipient':recipient,'amount':amount,'nonce':nonce,'checks':evaluation['checks']})
    return {'id':proposal_id,'status':status,'checks':evaluation['checks']}


def transition(proposal_id, expected, target, **values):
    allowed = {'digest','signature','tx_hash','error'}
    if not set(values).issubset(allowed):
        raise ValueError('Invalid update field')
    with connection() as con:
        fields = ['status=?','updated_at=?']+[f'{k}=?' for k in values]
        args = [target,int(time.time()),*values.values(),proposal_id,expected]
        result=con.execute(f'UPDATE proposals SET {", ".join(fields)} WHERE id=? AND status=?',args)
        if result.rowcount != 1:
            raise ValueError(f'Proposal status changed; expected {expected}')
        # Preserve the linked receipt hash when reconciling SUBMITTED -> CONFIRMED.
        stored = con.execute('SELECT tx_hash FROM proposals WHERE id=?', (proposal_id,)).fetchone()
        audit(con, proposal_id, target, {'tx_hash': stored['tx_hash'], 'error':values.get('error')})
