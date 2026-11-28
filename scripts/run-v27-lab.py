#!/usr/bin/env python3
"""QIE Sentinel 2.7 local Foundry-only authorization report.

Runs unit tests using the explicit Foundry binary and writes a JSON summary.
Does not deploy externally, broadcast, contact RPC, or use production keys.
"""
from __future__ import annotations
import argparse
import datetime as dt
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
EXPECTED = (
    "testV27IndependentUsersReceiveDistinctOwnershipAndGuards",
    "testV27IndependentOwnerConsentAndExecutorPerformOnlyScopedTransfer",
    "testV27AIAgentOrUnauthorizedCallerCannotSubmitSignedPayment",
    "testV27WrongOwnerSignatureRejectedWithNoStateChange",
    "testV27SignatureForAliceVaultCannotAuthorizeBobVault",
    "testV27OwnerRevocationPreventsExecutionOfPreviouslyValidSignature",
    "testV27OwnerPausesToBlockEvenCorrectlySignedIntent",
    "testV27BudgetLimitBlocksAdditionalPaymentWithoutConsumingNonce",
    "testV27ExpiredIntentFailsWithNoNonceConsumption",
    "testV27RotatingExecutorInvalidatesOldExecutorPermission",
    "testV27OutsiderCannotManageAnotherOwnerVault",
)

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("/mnt/c/Users/VPS/Downloads/sentinel-v27-local-authorization-report.json"),
        help="Absolute path for local JSON report (default: Windows Downloads)",
    )
    args = parser.parse_args()
    forge = Path.home() / ".foundry" / "bin" / "forge"
    if not forge.is_file() or not os.access(forge, os.X_OK):
        print(f"[STOP] Foundry binary not installed at {forge}", file=sys.stderr)
        return 2
    ver = subprocess.run([str(forge), "--version"], cwd=ROOT, capture_output=True, text=True)
    if ver.returncode or not ver.stdout.startswith("forge Version:"):
        print("[STOP] Binary is not Foundry forge", file=sys.stderr)
        return 2
    branch = subprocess.run(
        ["git", "branch", "--show-current"], cwd=ROOT, capture_output=True, text=True, check=True
    ).stdout.strip()
    if branch != "feat/v2-owner-approval":
        print("[STOP] Expected v2 development branch, not main", file=sys.stderr)
        return 2

    cmd = [
        str(forge), "test", "--match-contract", "SentinelV27LifecycleTest", "-vv",
    ]
    result = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    output = result.stdout + "\n" + result.stderr
    found = {
        name: status for status, name in re.findall(
            r"\[(PASS|FAIL)(?:[^\]]*)\]\s+(testV27[A-Za-z0-9_]+)\(", output
        )
    }
    failures = [name for name in EXPECTED if found.get(name) != "PASS"]
    extra = sorted(set(found).difference(EXPECTED))
    passed = result.returncode == 0 and not failures and not extra
    sha = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True, check=True
    ).stdout.strip()
    report = {
        "schema": "qie-sentinel-v27-local-authorization-tests-v1",
        "status": "PASSED_LOCAL_SIMULATION" if passed else "FAILED_LOCAL_SIMULATION",
        "repoCommit": sha,
        "createdUtc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "foundryVersion": ver.stdout.strip().splitlines()[0],
        "command": "forge test --match-contract SentinelV27LifecycleTest -vv",
        "network": "LOCAL_FOUNDRY_EVM_ONLY",
        "simulatedChainId": 1990,
        "suite": "SentinelV27LifecycleTest",
        "expectedTests": len(EXPECTED),
        "passedTests": sorted(k for k, v in found.items() if v == "PASS"),
        "missingOrFailedTests": failures,
        "unexpectedTests": extra,
        "exitCode": result.returncode,
        "realWalletKeysUsed": False,
        "mainnetBroadcast": False,
        "realFundsMoved": False,
        "testScenarioNotice": (
            "Local EVM state transitions use disposable deterministic keys and mock QUSDC. "
            "A successful local signed payment is NOT a live QIE Mainnet transaction."
        ),
        "disclaimer": (
            "The JSON was generated locally and is not cryptographically attested; "
            "verify the git commit, test source, tool version and CI results independently."
        ),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"[{'PASS' if passed else 'FAIL'}] {len(report['passedTests'])}/{len(EXPECTED)} local lifecycle tests")
    print(f"[REPORT] {args.output}")
    if not passed:
        print(output[-6500:], file=sys.stderr)
        return 1
    return 0

if __name__ == "__main__":
    sys.exit(main())
