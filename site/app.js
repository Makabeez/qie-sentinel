'use strict';
const cases = {
  valid: { verdict: 'Eligible for owner approval', ok: true, reason: 'Approved recipient, 0.05 QUSDC within contract limits, unused nonce, unexpired intent.', checks: ['Recipient allowlist: PASS','Per-transfer limit: PASS','Daily budget: PASS','Nonce and deadline: PASS'], signature: 'Required — not present' },
  recipient: { verdict: 'Blocked: recipient not allowed', ok: false, reason: 'Destination is not on the vault’s approved recipient list.', checks: ['Recipient allowlist: FAIL','No authorization requested','No transaction broadcast'], signature: 'Not requested' },
  oversize: { verdict: 'Blocked: exceeds payment limit', ok: false, reason: '1.000001 QUSDC is greater than the 1.000000 QUSDC per-transfer limit.', checks: ['Per-transfer limit: FAIL','No authorization requested','No transaction broadcast'], signature: 'Not requested' },
  replay: { verdict: 'Blocked: nonce already used', ok: false, reason: 'An earlier execution consumed this nonce. It cannot authorize another transfer.', checks: ['Nonce uniqueness: FAIL','No authorization requested','No transaction broadcast'], signature: 'Not requested' },
  expired: { verdict: 'Blocked: expired intent', ok: false, reason: 'An intent with a deadline in the past is invalid.', checks: ['Authorization deadline: FAIL','No authorization requested','No transaction broadcast'], signature: 'Not requested' }
};
const run = document.getElementById('run');
run.addEventListener('click', () => {
  const entry = cases[document.getElementById('scenario').value];
  const terminal = document.getElementById('terminal');
  terminal.textContent = ['> DEMO SIMULATION ONLY — no RPC call, no funds', ...entry.checks.map(x => '> ' + x), '> DECISION: ' + (entry.ok ? 'ELIGIBLE — OWNER SIGNATURE REQUIRED' : 'REJECT')].join('\n');
  const icon = document.getElementById('decision-icon');
  icon.textContent = entry.ok ? '✓' : '×';
  icon.className = 'status-icon ' + (entry.ok ? 'allowed' : 'blocked');
  document.getElementById('decision-title').textContent = entry.verdict;
  document.getElementById('decision-detail').textContent = entry.reason;
  document.getElementById('signature-status').textContent = entry.signature;
});
document.getElementById('copy-vault').addEventListener('click', async () => {
  const addr = '0xb752F05a55059C89a43a289d5d055F303B6DD96E';
  const button = document.getElementById('copy-vault');
  try { await navigator.clipboard.writeText(addr); button.textContent = 'Copied ✓'; }
  catch { button.textContent = 'Select address above to copy'; }
});
