import pytest
from backend.policy import Snapshot, evaluate

BASE = Snapshot(paused=False, vault_balance=750000, remaining_today=4750000,
                max_per_transfer=1000000, allowed=True)

def test_eligible():
    assert evaluate(250000, BASE)["decision"] == "ELIGIBLE_FOR_OWNER_SIGNATURE"

@pytest.mark.parametrize("change,amount,expected", [
    ({"paused": True}, 250000, "Emergency pause"),
    ({"allowed": False}, 250000, "not allowlisted"),
    ({}, 1100000, "per-transfer"),
    ({"remaining_today": 100000}, 250000, "daily budget"),
    ({"vault_balance": 100000}, 250000, "vault balance"),
    ({}, 0, "positive"),
])
def test_blocked(change,amount,expected):
    s = Snapshot(**{**BASE.__dict__, **change})
    verdict = evaluate(amount,s)
    assert verdict["decision"] == "BLOCKED"
    assert any(expected in r for r in verdict["reasons"])
