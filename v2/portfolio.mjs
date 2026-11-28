import { domain, paymentDigest } from './portfolio-payment.mjs';
import { amountToUnits } from './policy.mjs';

const sample = Object.freeze({
  token: '0x2000000000000000000000000000000000000002',
  recipient: '0x3000000000000000000000000000000000000003',
  amount: '250000',
  nonce: '7',
  deadline: '1800000000',
  executor: '0x4000000000000000000000000000000000000004',
  ownerEpoch: '1',
  executorEpoch: '1',
  signerEpoch: '0'
});

const form = document.getElementById('payment');
const original = paymentDigest(sample);
document.getElementById('original').textContent = original;
const digest = document.getElementById('digest');
const verdict = document.getElementById('verdict');
const packet = document.getElementById('packet');

function compare() {
  try {
    const epoch = form.elements.epoch.value.trim();
    if (!/^(0|[1-9][0-9]*)$/.test(epoch) || BigInt(epoch) >= 2n ** 256n) {
      throw new Error('Enter an executor epoch between 0 and the uint256 maximum.');
    }
    const message = {
      ...sample,
      amount: amountToUnits(form.elements.amount.value.trim()).toString(),
      executorEpoch: epoch
    };
    const result = paymentDigest(message);
    digest.textContent = result;
    verdict.textContent = result === original ? 'Digest matches the sample' : 'Digest changed';
    packet.textContent = JSON.stringify({ domain, message }, null, 2);
  } catch (error) {
    verdict.textContent = error.message;
    digest.textContent = '—';
    packet.textContent = '';
  }
}

form.addEventListener('submit', event => {
  event.preventDefault();
  compare();
});
form.addEventListener('input', compare);
compare();
