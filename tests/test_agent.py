from fastapi import FastAPI
from fastapi.testclient import TestClient
from backend.agent import create_router
from backend.policy import Snapshot, evaluate

RECIPIENT='0xce99cF8EdfD199dB02b830445d89E746B8c1C7ff'


def mock_snapshot(addr):
    allowed = addr.lower() == RECIPIENT.lower()
    return {'block': 12021721}, Snapshot(paused=False, vault_balance=750000,
                                          remaining_today=4750000, max_per_transfer=1000000,
                                          allowed=allowed)


def test_invoice_agent(tmp_path, monkeypatch):
    import backend.agent as agent
    monkeypatch.setattr(agent, 'DB_PATH', tmp_path / 'agent.sqlite3')
    app=FastAPI()
    app.include_router(create_router(mock_snapshot, evaluate, RECIPIENT))
    client=TestClient(app, client=('127.0.0.1', 34567))
    r=client.post('/api/agent/run', json={'scenario':'demo'})
    assert r.status_code == 200, r.text
    items=r.json()['items']
    assert [x['decision'] for x in items] == ['ELIGIBLE_FOR_OWNER_SIGNATURE','BLOCKED','BLOCKED']
    assert all(x['execution']=='NOT_SUBMITTED' for x in items)
    audit=client.get('/api/agent/events')
    assert audit.status_code==200
    assert len(audit.json()['items'])==3
    assert all(x['execution']=='NOT_SUBMITTED' for x in audit.json()['items'])


def test_agent_fail_closed(tmp_path, monkeypatch):
    import backend.agent as agent
    monkeypatch.setattr(agent, 'DB_PATH', tmp_path / 'agent.sqlite3')
    app=FastAPI()
    def broken(_): raise RuntimeError('RPC offline')
    app.include_router(create_router(broken, evaluate, RECIPIENT))
    client=TestClient(app, client=('127.0.0.1', 34567))
    assert client.post('/api/agent/run', json={'scenario':'demo'}).status_code==503
    assert client.get('/api/agent/events').json()['items']==[]
