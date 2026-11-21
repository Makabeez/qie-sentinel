"""Pure deterministic proposal evaluation; never signs or executes transfers."""
from dataclasses import dataclass, asdict

@dataclass(frozen=True)
class Snapshot:
    paused: bool
    vault_balance: int
    remaining_today: int
    max_per_transfer: int
    allowed: bool


def evaluate(amount: int, snapshot: Snapshot) -> dict:
    reasons: list[str] = []
    if amount <= 0:
        reasons.append("Amount must be positive")
    if snapshot.paused:
        reasons.append("Emergency pause is active")
    if not snapshot.allowed:
        reasons.append("Recipient is not allowlisted")
    if amount > snapshot.max_per_transfer:
        reasons.append("Exceeds per-transfer limit")
    if amount > snapshot.remaining_today:
        reasons.append("Exceeds remaining daily budget")
    if amount > snapshot.vault_balance:
        reasons.append("Exceeds vault balance")
    return {"decision": "BLOCKED" if reasons else "ELIGIBLE_FOR_OWNER_SIGNATURE", "reasons": reasons}
