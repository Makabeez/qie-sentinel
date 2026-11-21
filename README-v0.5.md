# QIE Sentinel v0.5 — Offline Judge Showcase

Additive, read-only upgrade. This ZIP contains only `sentinel-agent/showcase.py` and `sentinel-agent/test_showcase.py`; does not overwrite the app, deployed contracts, database, agent approval/execution logic, or existing evidence exporter.

## Install / use

```bash
cd /mnt/c/Github/qie-sentinel
unzip -o /mnt/c/Users/VPS/Downloads/qie-sentinel-v0.5-showcase.zip
python3 -m unittest discover -s sentinel-agent -p 'test_*.py' -v
python3 sentinel-agent/evidence.py --output sentinel-evidence.json
python3 sentinel-agent/showcase.py --input sentinel-evidence.json --output sentinel-showcase.html
```

Open `C:\Github\qie-sentinel\sentinel-showcase.html` in Chrome (or `explorer.exe sentinel-showcase.html` in WSL). No server, network calls, key access or token transactions required for generation or viewing.

## Boundaries

- This static page reflects the moment the evidence JSON was exported. Refresh by rerunning both export commands.
- It never embeds signatures or keystore data; review it before public release because transaction hashes, addresses, amounts and times are included.
- A locally rejected request is **not an on-chain revert**. The report says so explicitly.
- The count of confirmed payments is derived from the proposal ledger only, not a comprehensive on-chain history.
- The HTML contains no JavaScript and uses only local CSS. Explorer links are ordinary external hyperlinks.
