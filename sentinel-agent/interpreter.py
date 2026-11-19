"""Fail-closed natural-language payment parser. No keys, signatures or transactions.

Text is treated as untrusted data: all payment fields are extracted deterministically,
then checked by the existing live on-chain evaluator. Does not claim LLM inference.
"""
import re
from decimal import Decimal, InvalidOperation

KNOWN_RECIPIENT = '0xce99cF8EdfD199dB02b830445d89E746B8c1C7ff'
ALIASES = ('approved service provider', 'approved provider', 'approved recipient',
           'deployer wallet', 'deployer')
ADDRESS = re.compile(r'0x[a-fA-F0-9]{40}\b')
AMOUNT = re.compile(r'(?<![\w.])(?P<number>\d+(?:[.,]\d{1,6})?)\s*(?:QUSDC)\b', re.I)
SUSPICIOUS = re.compile(r'\b(?:ignore\s+(?:all\s+)?(?:previous|prior|security|policy)|bypass|override\s+(?:the\s+)?(?:guard|policy|approval)|skip\s+(?:the\s+)?(?:signature|owner|checks)|private\s+key|seed\s+phrase)\b', re.I)

class RequestError(ValueError):
    pass


def parse_request(text):
    if not isinstance(text,str) or not 8 <= len(text) <= 600:
        raise RequestError('Request must be 8–600 characters')
    if any(ord(ch)<32 and ch not in '\n\t' for ch in text):
        raise RequestError('Invalid control characters')
    if SUSPICIOUS.search(text):
        raise RequestError('Request contains instructions attempting to bypass payment controls')
    if not re.search(r'\b(?:pay|send|transfer|reimburse|settle)\b',text,re.I):
        raise RequestError('Request must explicitly ask to pay, send, or transfer QUSDC')
    amounts=list(AMOUNT.finditer(text))
    if len(amounts)!=1:
        raise RequestError('Specify exactly one QUSDC amount, for example 0.05 QUSDC')
    raw=amounts[0].group('number').replace(',','.')
    try:
        amount=int(Decimal(raw)*1000000)
    except (InvalidOperation,OverflowError) as exc:
        raise RequestError('Invalid QUSDC amount') from exc
    if not 0 < amount <= 100_000_000_000:
        raise RequestError('Amount must be positive and within parser limits')
    # Other numeric quantities may refer to invoices or dates, but a second currency
    # amount is ambiguous and must be resolved by the human operator.
    if re.search(r'(?i)\b(?:USD|USDC|WQIE|QIE|ETH|EUR|CHF)\b',text):
        raise RequestError('Multiple token/currency references are ambiguous; use QUSDC only')
    addresses={a.group().lower() for a in ADDRESS.finditer(text)}
    alias_hits=[alias for alias in ALIASES if re.search(r'(?<!\w)'+re.escape(alias)+r'(?!\w)',text,re.I)]
    if len(addresses)>1:
        raise RequestError('Multiple recipient addresses found')
    if addresses and alias_hits:
        if next(iter(addresses))!=KNOWN_RECIPIENT.lower():
            raise RequestError('Recipient alias conflicts with the supplied address')
    if addresses:
        recipient=next(iter(addresses))
        recipient_source='explicit address'
    elif alias_hits:
        recipient=KNOWN_RECIPIENT
        recipient_source='configured demo alias'
    else:
        raise RequestError('Recipient not recognized; use an explicit 0x address or configured approved-provider alias')
    # Prevent latent instructions that a human might mistake for security approval.
    notes=[]
    if re.search(r'\b(?:urgent|immediately|right now)\b',text,re.I):
        notes.append('Urgency does not bypass owner authorization')
    if re.search(r'\b(?:invoice|service|subscription)\b',text,re.I):
        notes.append('Payment purpose is descriptive only, not proof of an invoice')
    return {'recipient':recipient,'amount':amount,'amountQUSDC':f'{amount/1000000:.6f}',
            'recipientSource':recipient_source,'explanation':'Parsed a single QUSDC payment and an explicit or configured recipient. Live policy validation is required.',
            'riskNotes':notes, 'engine':'deterministic-local-v1'}


def interpret(text, nonce, evaluate_fn):
    if type(nonce) is not int or not 0 <= nonce < 2**256:
        raise RequestError('A non-negative integer nonce is required')
    parsed=parse_request(text)
    evaluated=evaluate_fn({'recipient':parsed['recipient'], 'amount':parsed['amount'], 'nonce':nonce})
    return {**parsed,'nonce':nonce,'decision':evaluated['decision'],'checks':evaluated['checks'],
            'warning':'This is an unsigned proposal. Owner approval and on-chain enforcement remain mandatory.'}
