# QIE Sentinel Phase 4.1 overlay

Keep the running project's `backend/main.py` and `web/index.html`. This overlay **does not replace them**. The installer modifies only two files after validating their expected markers and saves `.phase40.bak` backups.

## Install

```bash
cd /mnt/c/Github/qie-sentinel
unzip -o /mnt/c/Users/VPS/Downloads/qie-sentinel-phase4.1-overlay.zip
source .venv-dashboard/bin/activate
python install_phase41.py
python -m pytest -q tests/test_policy.py tests/test_agent.py
python -m uvicorn backend.main:app --host 127.0.0.1 --port 8765
```

Visit http://127.0.0.1:8765 and click **Run invoice agent**. Three fixed simulated invoices are evaluated against actual chain state; a persistent SQLite audit table is created at `data/agent_events.sqlite3`.

The backend **does not** load owner/executor keys, sign EIP-712 messages, or broadcast transactions. An eligible proposal is **not** an authorization. The run route is restricted to local loopback clients, and the operator should keep Uvicorn bound to 127.0.0.1. This is not a production authentication scheme.

## Restore

```bash
cp backend/main.py.phase40.bak backend/main.py
cp web/index.html.phase40.bak web/index.html
```

## APIs

- `POST /api/agent/run` with `{"scenario":"demo"}`: process three simulated invoices
- `GET /api/agent/events`: get up to 60 persisted audit entries

The agent is a deterministic *simulation*, not a language-model-driven autonomous payment executor. The next secure step is explicit owner-signed authorization and isolated executor, with separate verification tests.
