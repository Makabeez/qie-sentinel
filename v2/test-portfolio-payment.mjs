import test from 'node:test';
import assert from 'node:assert/strict';
import { paymentDigest } from './portfolio-payment.mjs';

test('V35 sample digest matches an independent OpenSSL Keccak-256 vector', () => {
  const payment = {
    token: '0x2000000000000000000000000000000000000002',
    recipient: '0x3000000000000000000000000000000000000003',
    amount: '250000',
    nonce: '7',
    deadline: '1800000000',
    executor: '0x4000000000000000000000000000000000000004',
    ownerEpoch: '1',
    executorEpoch: '1',
    signerEpoch: '0'
  };
  const digest = paymentDigest(payment);
  assert.equal(digest, '0xf1e45f9df0ad66a12229ed4d387af3f7d0a84397c6db0f39306756442044129d');
  for (const epochField of ['ownerEpoch', 'executorEpoch', 'signerEpoch']) {
    assert.notEqual(paymentDigest({ ...payment, [epochField]: '2' }), digest);
  }
});
