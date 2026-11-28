#!/usr/bin/env python3
"""QIE Sentinel dashboard + read-only policy evaluator. No keys; no transactions."""
import json
import os
import time
import urllib.request
import urllib.error
import logging
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path

RPC = os.environ.get('QIE_RPC', 'https://rpc1mainnet.qie.digital')
VAULT = os.environ.get('SENTINEL_VAULT', '0xb752F05a55059C89a43a289d5d055F303B6DD96E')
GUARD = os.environ.get('SENTINEL_GUARD', '0x532Ee81939386E23b8c58076e643D9FCe489F15C')
TOKEN = '0x3F43DA82eC9A4f5285F10FaF1F26EcA7319E5DA5'
EXPECTED_OWNER = '0x395215ab5Dde403801868fa850b89e305F01725E'
EXPECTED_EXECUTOR = '0xD0612b00030AC351EAb6A7800E4b7679e3f7D95A'
KNOWN_RECIPIENT = '0xce99cF8EdfD199dB02b830445d89E746B8c1C7ff'
# Contract topic hashes observed in successful mainnet receipt.
PAYMENT_EXECUTED_TOPIC = '0xf667481f4d24622c7e078738f5329ac66d13d43ca14a97896cff51689af800fc'
BUDGET_CONSUMED_TOPIC = '0xc6a60832f21db26f376b4d58c7404edbf71955ea89af3457027e3d2d7192dae1'
WEB = Path(__file__).resolve().parent / 'web'

from workflow import submit, proposals, events

# keccak256(signature)[:4], pinned so the server starts without Foundry installed.
# Re-verify with: cast sig '<signature>'  (tests/test_selectors.py does this when cast exists)
SELECTORS = {
    'owner': '0x8da5cb5b',      # owner()
    'executor': '0xc34c08e5',   # executor()
    'token': '0xfc0c546a',      # token()
    'guard': '0x7ceab3b1',      # guard()
    'paused': '0x5c975abb',     # paused()
    'balance': '0xb69ef8a8',    # balance()
    'max': '0xd1129bf3',        # maxPerTransfer()
    'daily': '0x67eeba0c',      # dailyLimit()
    'remaining': '0xfc3c5515',  # remainingToday()
    'allowed': '0x4df6d6cc',    # allowedRecipients(address)
    'nonce': '0x5d00bb12',      # isNonceUsed(uint256)
}


def rpc(method, params):
    payload = json.dumps({'jsonrpc':'2.0','id':1,'method':method,'params':params}).encode()
    request = urllib.request.Request(RPC, data=payload, headers={'Content-Type':'application/json'})
    with urllib.request.urlopen(request, timeout=12) as resp:
        result = json.load(resp)
    if 'error' in result:
        raise RuntimeError(result['error'].get('message', 'RPC error'))
    return result['result']


def call(address, name, arg=''):
    data = SELECTORS[name] + arg
    raw = rpc('eth_call', [{'to': address, 'data': data}, 'latest'])
    if not raw or raw == '0x':
        raise RuntimeError(f'Empty response for {name}')
    return int(raw, 16)


def address_value(n):
    return '0x' + format(n, '064x')[-40:]


def addr_arg(addr):
    if not isinstance(addr, str) or len(addr) != 42 or not addr.startswith('0x'):
        raise ValueError('Recipient must be a 20-byte hex address')
    int(addr[2:], 16)
    return addr[2:].lower().rjust(64, '0')


def snapshot():
    chain = int(rpc('eth_chainId', []), 16)
    if chain != 1990:
        raise RuntimeError(f'Wrong chain {chain}; refusing evaluation')
    owner = address_value(call(VAULT, 'owner'))
    executor = address_value(call(VAULT, 'executor'))
    token = address_value(call(VAULT, 'token'))
    guard = address_value(call(VAULT, 'guard'))
    if (owner.lower(), executor.lower(), token.lower(), guard.lower()) != (
        EXPECTED_OWNER.lower(), EXPECTED_EXECUTOR.lower(), TOKEN.lower(), GUARD.lower()
    ):
        raise RuntimeError('Contract configuration mismatch; refusing evaluation')
    block = int(rpc('eth_blockNumber', []), 16)
    return {
        'chainId': chain, 'block': block, 'vault': VAULT, 'guard': GUARD,
        'owner': owner, 'executor': executor, 'token': token,
        'paused': bool(call(VAULT, 'paused')),
        'balance': call(VAULT, 'balance'),
        'maxPerTransfer': call(GUARD, 'max'),
        'dailyLimit': call(GUARD, 'daily'),
        'remainingToday': call(GUARD, 'remaining'),
        'updatedAt': int(time.time())
    }


def evaluate(payload):
    s = snapshot()  # fail closed if RPC/config inaccessible
    recipient = payload.get('recipient', '')
    amount = payload.get('amount')
    nonce = payload.get('nonce')
    if type(amount) is not int or not (0 < amount < 2**256):
        raise ValueError('amount must be a positive integer of QUSDC base units')
    if type(nonce) is not int or not (0 <= nonce < 2**256):
        raise ValueError('nonce must be a non-negative integer')
    argument = addr_arg(recipient)
    allowlisted = bool(call(GUARD, 'allowed', argument))
    nonce_used = bool(call(VAULT, 'nonce', format(nonce, '064x')))
    checks = [
        {'name':'Vault is active', 'ok':not s['paused']},
        {'name':'Recipient is allowlisted', 'ok':allowlisted},
        {'name':'Amount within per-transfer limit', 'ok':amount <= s['maxPerTransfer']},
        {'name':'Amount within daily remaining', 'ok':amount <= s['remainingToday']},
        {'name':'Vault has sufficient QUSDC', 'ok':amount <= s['balance']},
        {'name':'Nonce has not been used', 'ok':not nonce_used},
    ]
    return {'decision':'ELIGIBLE_FOR_OWNER_SIGNATURE' if all(c['ok'] for c in checks) else 'REJECT',
            'checks':checks,'recipient':recipient,'amount':amount,'nonce':nonce,
            'warning':'Read-only eligibility is not a payment authorization. An owner signature is always required.',
            'state':s}


def recent_payments(block, window=5000):
    start = max(0, block-window+1)
    logs = rpc('eth_getLogs', [{'address':VAULT, 'topics':[PAYMENT_EXECUTED_TOPIC],
                                'fromBlock':hex(start),'toBlock':hex(block)}])
    items=[]
    for event in logs[-20:]:
        topics = event['topics']
        data = event['data'][2:]
        if len(topics) != 4 or len(data) < 128:
            continue
        items.append({
            'txHash':event['transactionHash'],
            'block':int(event['blockNumber'],16),
            'digest':topics[1],
            'nonce':int(topics[2],16),
            'recipient':'0x'+topics[3][-40:],
            'amount':int(data[:64],16),
            'executor':'0x'+data[64:128][-40:]
        })
    return list(reversed(items))


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(WEB), **kwargs)

    def json_response(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            # Browser canceled the request; cannot send a second response.
            pass

    def _local_host_ok(self):
        host = self.headers.get('Host', '')
        port = self.server.server_port
        return host in (f'127.0.0.1:{port}', f'localhost:{port}')

    def list_directory(self, path):
        self.send_error(404, 'Not found')  # no directory listings
        return None

    def do_GET(self):
        # Reject DNS rebinding for ALL reads, not only writes: proposals and the audit
        # trail (recipients, amounts, digests, tx hashes) are private.
        if not self._local_host_ok():
            return self.json_response(403, {'error': 'Invalid local host'})
        if self.path not in ('/api/state', '/api/payments', '/api/proposals', '/api/agent/events'):
            return super().do_GET()
        try:
            if self.path == '/api/proposals':
                return self.json_response(200,{'proposals':proposals()})
            if self.path == '/api/agent/events':
                return self.json_response(200,{'events':events()})
            s=snapshot()
            if self.path == '/api/state':
                return self.json_response(200,s)
            try:
                payments=recent_payments(s['block'])
                return self.json_response(200,{'payments':payments,'fromBlock':max(0,s['block']-4999)})
            except Exception as event_error:
                return self.json_response(200,{'payments':[], 'warning':str(event_error)})
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            return  # Browser disconnected; do not reply again.
        except Exception as exc:
            try:
                self.json_response(503, {'error':str(exc)})
            except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
                return

    def do_POST(self):
        if self.path not in ('/api/evaluate','/api/proposals','/api/agent/demo','/api/agent/interpret','/api/agent/request','/api/agent/advice'):
            return self.json_response(404, {'error':'Unknown endpoint'})
        # Reject DNS rebinding to this loopback-only service.
        if not self._local_host_ok():
            return self.json_response(403, {'error':'Invalid local host'})
        # Prevent unrelated websites from issuing local write requests via browser.
        origin = self.headers.get('Origin')
        if origin and origin not in (f'http://127.0.0.1:{self.server.server_port}', f'http://localhost:{self.server.server_port}'):
            return self.json_response(403, {'error':'Cross-origin requests forbidden'})
        content_type = self.headers.get('Content-Type','').split(';',1)[0].strip().lower()
        if content_type != 'application/json':
            return self.json_response(415, {'error':'Use application/json'})
        try:
            length=int(self.headers.get('Content-Length','0'))
            if not 0 < length <= 4096:
                raise ValueError('Invalid input size')
            data=json.loads(self.rfile.read(length))
            if not isinstance(data,dict):
                raise ValueError('Expected JSON object')
            if self.path == '/api/agent/demo':
                if data:
                    raise ValueError('Demo endpoint accepts an empty JSON object only')
                from demo import run
                return self.json_response(201,run())
            if self.path == '/api/agent/advice':
                from advisor import advisory
                from interpreter import interpret
                from demo import available_nonce
                result=advisory(
                    data.get('text'), consent=data.get('consent') is True,
                    nonce_provider=available_nonce,
                    interpreter=lambda txt, nonce: interpret(txt, nonce, evaluate)
                )
                return self.json_response(200, result)
            if self.path in ('/api/agent/interpret','/api/agent/request'):
                from interpreter import interpret
                from demo import available_nonce
                text=data.get('text')
                # A new nonce is assigned on the trusted local server, never by the model.
                nonce=available_nonce()
                result=interpret(text,nonce,evaluate)
                if self.path == '/api/agent/request':
                    from workflow import connection, audit
                    saved=submit(result['recipient'],result['amount'],nonce,int(time.time())+3600,result)
                    with connection() as con:
                        audit(con,saved['id'],'NATURAL_LANGUAGE_DECISION',{
                            'engine':result['engine'], 'decision':result['decision'],
                            'recipient_source':result['recipientSource'],
                            'failed_checks':[c['name'] for c in result['checks'] if not c['ok']],
                            'text_sha256':__import__('hashlib').sha256(text.encode()).hexdigest(),
                        })
                    return self.json_response(201,{'proposal':saved,'interpretation':result})
                return self.json_response(200,result)
            decision=evaluate(data)
            if self.path == '/api/proposals':
                deadline=data.get('deadline')
                if type(deadline) is not int:
                    raise ValueError('deadline must be a Unix integer')
                result=submit(data['recipient'],data['amount'],data['nonce'],deadline,decision)
                return self.json_response(201,result)
            self.json_response(200,decision)
        except (ValueError,TypeError,KeyError) as exc:
            self.json_response(400,{'error':str(exc)})
        except Exception as exc:
            logging.exception('internal error')
            self.json_response(503,{'error':'Upstream RPC or internal error; nothing was saved or signed'})

    def log_message(self, fmt, *args):
        print('%s - %s' % (self.address_string(),fmt % args),flush=True)


if __name__ == '__main__':
    # Loopback only: dashboard is local, intentionally does not accept remote access.
    port = int(os.environ.get('SENTINEL_PORT','8765'))
    print(f'Sentinel read-only dashboard: http://127.0.0.1:{port}')
    print('No private keys loaded. Transactions cannot be submitted by this server.')
    try:
        ThreadingHTTPServer(('127.0.0.1',port),Handler).serve_forever()
    except KeyboardInterrupt:
        print('Sentinel dashboard stopped.')
