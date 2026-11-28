#!/usr/bin/env python3
"""Offline owner approval and explicit executor broadcast; never imported by the HTTP server."""
import argparse
import json
import os
import re
import subprocess
import sys
import time

from server import VAULT, GUARD, TOKEN, EXPECTED_OWNER, EXPECTED_EXECUTOR, rpc, evaluate, snapshot, addr_arg
from workflow import get, proposals, transition

CAST = os.environ.get('SENTINEL_CAST', os.path.expanduser('~/.foundry/bin/cast'))
RPC = os.environ.get('QIE_RPC', 'https://rpc1mainnet.qie.digital')
PAYMENT_TYPE = 'paymentDigest((address,address,uint256,uint256,uint256,address))(bytes32)'
EXECUTE_TYPE = 'execute((address,address,uint256,uint256,uint256,address),bytes)'
HEX32 = re.compile(r'^0x[0-9a-fA-F]{64}$')
HEX_SIG = re.compile(r'^0x[0-9a-fA-F]{130}$')


def cmd(*argv, interactive=False):
    command = [CAST, *[str(x) for x in argv]]
    if interactive:
        subprocess.run(command, check=True)
        return None
    result=subprocess.run(command, check=True, text=True, stdout=subprocess.PIPE, timeout=180 if '--account' in command else 45)
    return result.stdout.strip()


def payment(row):
    return f"({TOKEN},{row['recipient']},{row['amount']},{row['nonce']},{row['deadline']},{EXPECTED_EXECUTOR})"


def verify(row):
    if int(time.time()) >= row['deadline'] - 45:
        raise ValueError('Approval expired or too close to expiry; create a new proposal')
    checks=evaluate({'recipient':row['recipient'],'amount':row['amount'],'nonce':row['nonce']})
    if checks['decision'] != 'ELIGIBLE_FOR_OWNER_SIGNATURE':
        raise ValueError('On-chain policy rejects this payment: '+str([c['name'] for c in checks['checks'] if not c['ok']]))
    return checks


DOMAIN_NAME, DOMAIN_VERSION, CHAIN_ID = 'QIE Sentinel Vault', '1', 1990
EIP712_DOMAIN = 'EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'
PAYMENT_STRUCT = 'Payment(address token,address recipient,uint256 amount,uint256 nonce,uint256 deadline,address executor)'


def local_digest(row, vault=VAULT, chain_id=CHAIN_ID):
    """EIP-712 digest computed OFFLINE (no RPC). Never sign a hash an RPC handed you."""
    k=lambda data: cmd('keccak', data)
    domain=k(cmd('abi-encode','f(bytes32,bytes32,bytes32,uint256,address)',
                 k(EIP712_DOMAIN), k(DOMAIN_NAME), k(DOMAIN_VERSION), chain_id, vault))
    struct=k(cmd('abi-encode','f(bytes32,address,address,uint256,uint256,uint256,address)',
                 k(PAYMENT_STRUCT), TOKEN, row['recipient'], row['amount'], row['nonce'],
                 row['deadline'], EXPECTED_EXECUTOR))
    return k('0x1901'+domain[2:]+struct[2:])


def digest(row):
    value=cmd('call',VAULT,PAYMENT_TYPE,payment(row),'--rpc-url',RPC)
    if not HEX32.fullmatch(value):
        raise ValueError('Unexpected digest returned by deployed vault')
    # A malicious or compromised QIE_RPC could return the digest of a DIFFERENT
    # payment (any allowlisted recipient, max amount, far deadline) and the owner
    # would blind-sign it with `cast wallet sign --no-hash`. Cross-check offline.
    expected=local_digest(row)
    if value.lower()!=expected.lower():
        raise ValueError('RPC digest does not match locally computed EIP-712 digest; refusing to sign')
    return expected


def approve(id):
    row=get(id)
    if row['status']!='AWAITING_OWNER':
        raise ValueError('Proposal is not awaiting approval')
    verify(row)
    d=digest(row)
    print('Payment to approve:')
    print('  recipient:',row['recipient'])
    print('  amount:', f"{row['amount']/1e6:.6f}", 'QUSDC')
    print('  nonce:',row['nonce'],'deadline:',row['deadline'])
    print('  digest:',d)
    print('Owner keystore prompt follows. The web server NEVER sees the keystore password.')
    # cast wallet sign requires a password prompt; capture only the final signature.
    # Cast writes the password prompt to stderr and reads from the terminal.
    signed = cmd('wallet','sign','--no-hash',d,'--account','sentinel-owner')
    signature = signed.splitlines()[-1].strip()
    if not HEX_SIG.fullmatch(signature):
        raise ValueError('Invalid signature returned from Foundry')
    # Validate against deployed contract, including ERC1271 SignatureChecker behavior.
    cmd('call',VAULT,EXECUTE_TYPE,payment(row),signature,'--from',EXPECTED_EXECUTOR,'--rpc-url',RPC)
    transition(id,'AWAITING_OWNER','SIGNED',digest=d,signature=signature)
    print('SIGNED. Simulation passed. Signature stored locally (not a private key).')


def execute(id):
    row=get(id)
    if row['status']!='SIGNED':
        raise ValueError('Proposal must be SIGNED before execution')
    verify(row)
    if digest(row).lower() != row['digest'].lower():
        raise ValueError('Payment digest mismatch')
    cmd('call',VAULT,EXECUTE_TYPE,payment(row),row['signature'],'--from',EXPECTED_EXECUTOR,'--rpc-url',RPC)
    print('You are about to broadcast a REAL mainnet payment:')
    print(f"  {row['amount']/1e6:.6f} QUSDC -> {row['recipient']}")
    if input('Type EXECUTE to broadcast: ').strip() != 'EXECUTE':
        print('Cancelled; proposal remains SIGNED.')
        return
    transition(id,'SIGNED','SUBMITTING')
    try:
        # --json emits the receipt to stdout and reads executor keystore password from tty.
        receipt = cmd('send',VAULT,EXECUTE_TYPE,payment(row),row['signature'],
                      '--rpc-url',RPC,'--account','sentinel-executor','--json')
        parsed=json.loads(receipt)
        tx=parsed.get('transactionHash')
        if not tx or not HEX32.fullmatch(tx):
            raise ValueError('Missing transaction hash in cast receipt; inspect chain before retrying')
        status=parsed.get('status',0)
        status_number = int(status, 16) if isinstance(status, str) and status.startswith('0x') else int(status)
        if status_number != 1:
            transition(id,'SUBMITTING','FAILED',tx_hash=tx,error='Transaction reverted')
            raise ValueError('Transaction reverted: '+tx)
        transition(id,'SUBMITTING','SUBMITTED',tx_hash=tx)
        print('Broadcast succeeded:',tx)
        reconcile(id)
    except Exception:
        print('Broadcast outcome uncertain; DO NOT retry before inspecting nonce and transaction history.')
        raise


def reconcile(id):
    row=get(id)
    if row['status'] not in ('SUBMITTING','SUBMITTED'):
        raise ValueError('Nothing to reconcile')
    used = cmd('call', VAULT,'isNonceUsed(uint256)(bool)',str(row['nonce']),'--rpc-url',RPC)
    if used == 'true':
        if row['tx_hash']:
            receipt = rpc('eth_getTransactionReceipt',[row['tx_hash']])
            if receipt and int(receipt['status'],16) == 1:
                transition(id,row['status'],'CONFIRMED')
                print('CONFIRMED on QIE Mainnet:',row['tx_hash'])
                return
        print('Nonce consumed, but matching receipt not proven. Inspect explorer before changing status.')
    else:
        print('Nonce unused; transaction not confirmed. Do not blind-retry a SUBMITTING proposal.')


def main():
    p=argparse.ArgumentParser(description='QIE Sentinel local signer/executor (never runs inside web server)')
    sub=p.add_subparsers(dest='action',required=True)
    sub.add_parser('list')
    for action in ('approve','execute','reconcile'):
        sub.add_parser(action).add_argument('id')
    args=p.parse_args()
    if args.action=='list':
        for row in proposals():
            print(row['id'],row['status'],f"{row['amount']/1e6:.6f}",row['recipient'], 'nonce',row['nonce'])
        return
    {'approve':approve,'execute':execute,'reconcile':reconcile}[args.action](args.id)


if __name__=='__main__':
    try:
        main()
    except (ValueError,subprocess.CalledProcessError,subprocess.TimeoutExpired) as exc:
        print('ERROR:',exc,file=sys.stderr)
        sys.exit(1)
