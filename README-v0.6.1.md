# QIE Sentinel v0.6.1 — HTTP disconnect fix

Overlay for v0.6. Changes only `sentinel-agent/server.py`.

- Handles `BrokenPipeError`, `ConnectionResetError`, and `ConnectionAbortedError` without trying to write a second HTTP error response.
- Handles Ctrl+C cleanly.
- Does not modify Solidity, wallet credentials, SQLite data, payment workflow, or on-chain configuration.

Install from repository root:

```bash
unzip -o /mnt/c/Users/VPS/Downloads/qie-sentinel-v0.6.1-server-fix.zip
python3 -m py_compile sentinel-agent/server.py
python3 -m unittest discover -s sentinel-agent -p 'test_*.py' -v
```

Start persistently:

```bash
export PATH="$HOME/.foundry/bin:$PATH"
nohup env SENTINEL_PORT=8765 python3 -u sentinel-agent/server.py > /tmp/qie-sentinel-dashboard.log 2>&1 < /dev/null &
sleep 2
curl -fsS --max-time 30 http://127.0.0.1:8765/api/state | python3 -m json.tool
```

If port already used: `ss -ltnp | grep ':8765'` and stop only the old Sentinel process.
