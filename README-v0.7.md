# QIE Sentinel v0.7 — Consent-only AI Risk Advisory

This is a **small overlay** for the existing v0.6.1 installation. It overwrites
only `sentinel-agent/server.py` and `sentinel-agent/web/index.html`, and adds
`sentinel-agent/advisor.py`, `sentinel-agent/test_advisor.py`. Existing contracts,
SQLite proposal database, signer/executor workflows, and prior evidence are preserved.

## Features

- Optional **Explain risks with AI** action in the natural-language section.
- The user must explicitly check the privacy-consent box for each browser session.
- The backend must have `OPENAI_API_KEY` set to activate the feature.
- The deterministic interpreter and **live QIE Mainnet policy preflight run BEFORE**
  any AI request. They remain the sole source of the verdict.
- The external API receives the user's request text, the parsed recipient/amount/nonce,
  risk notes, and pass/fail policy checks **only after consent**. Do not submit
  sensitive payment descriptions or credentials.
- OpenAI Responses API invoked with `store: false`. This is a request setting;
  review provider privacy policies separately.
- Never signs, submits, modifies proposal records or sees owner/executor keys.
- On key missing, connectivity problems, or policy check errors, no AI advice is
  returned and the independent local flow keeps working.

## Install from WSL

```bash
cd /mnt/c/Github/qie-sentinel
export PATH="$HOME/.foundry/bin:$PATH"
unzip -o /mnt/c/Users/VPS/Downloads/qie-sentinel-v0.7-ai-advisory.zip
python3 -m unittest discover -s sentinel-agent -p 'test_*.py' -v
python3 -m py_compile sentinel-agent/*.py
```

## Start without AI (default, no API key needed)

```bash
sudo fuser -k 8765/tcp 2>/dev/null || true
SENTINEL_PORT=8765 python3 -u sentinel-agent/server.py
```

Open `http://127.0.0.1:8765/index.html` and refresh. Existing policy checks,
proposals, and demo scenario runner work unchanged. AI button reports missing key.

## Optional OpenAI AI explanation

Run the server in a dedicated WSL terminal and enter the API key **interactively**,
not as a command-line argument or pasted into the browser:

```bash
cd /mnt/c/Github/qie-sentinel
export PATH="$HOME/.foundry/bin:$PATH"
read -rsp 'OpenAI API key: ' OPENAI_API_KEY; echo
export OPENAI_API_KEY
export SENTINEL_OPENAI_MODEL=gpt-6.1-terra
sudo fuser -k 8765/tcp 2>/dev/null || true
SENTINEL_PORT=8765 python3 -u sentinel-agent/server.py
```

Use the **Explain risks with AI (optional)** button only after selecting the
consent checkbox. The model response is **advisory text**, never an authorization.
An API key is a paid OpenAI Platform credential; it is separate from ChatGPT plans.
The default model can be overridden by `SENTINEL_OPENAI_MODEL` if it isn't
available to your account. The third-party network request is only made on an
explicit user action, never on page load or background refresh.

## Verify the route fails closed without a key

```bash
curl -sS http://127.0.0.1:8765/api/agent/advice \
  -H 'Content-Type: application/json' \
  -d '{"text":"Pay 0.05 QUSDC to approved provider","consent":false}'
```

Expected: an HTTP 400 JSON error about consent, without any external request.

## Safety limitations

Not audited. LLM output may be incomplete, unreliable, or influenced by malicious
request text; the model is never trusted to determine payment eligibility. Consent
should not be taken as permission to transmit credentials or sensitive invoices.
The server still binds to loopback and should **not** be exposed to the public
internet without authentication, TLS, and abuse prevention.
