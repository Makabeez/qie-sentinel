// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {SentinelVaultV35} from "../src/SentinelVaultV35.sol";
import {PolicyGuardRolling} from "../src/PolicyGuardRolling.sol";
import {MockQUSDC} from "./mocks/MockQUSDC.sol";

/// @notice Regression tests for the taskforce patches. Each test PASSES when the fix holds.
contract TaskforceFixes is Test {
    uint256 private constant OWNER_KEY = 0xA11CE;
    address private owner;
    address private executor = address(0xE01);
    address private recipient = address(0xCAFE);
    MockQUSDC private token;
    SentinelVaultV35 private vault;

    function setUp() public {
        vm.chainId(1990);
        vm.warp(1_800_000_000);
        owner = vm.addr(OWNER_KEY);
        token = new MockQUSDC();
        vault = new SentinelVaultV35(address(token), owner, executor, 250_000, 400_000);
        token.mint(address(vault), 1_000_000);
    }

    function testFix_F1_RenounceIsDisabled() public {
        vm.expectRevert(SentinelVaultV35.RenounceDisabled.selector);
        vm.prank(owner);
        vault.renounceOwnership();
        assertEq(vault.owner(), owner);
        // Break-glass still works.
        vm.startPrank(owner);
        vault.pause();
        vault.emergencyRecover(owner, 1_000_000);
        vm.stopPrank();
        assertEq(token.balanceOf(owner), 1_000_000);
    }

    function testFix_F1_NonOwnerStillGetsOwnableError() public {
        vm.expectRevert();
        vm.prank(address(0xBAD));
        vault.renounceOwnership();
    }

    function testFix_WrongTokenHasExplicitError() public {
        SentinelVaultV35.Payment memory p = SentinelVaultV35.Payment({
            token: address(0x1234), recipient: recipient, amount: 1, nonce: 1,
            deadline: block.timestamp + 60, executor: executor, ownerEpoch: vault.ownerEpoch(),
            executorEpoch: vault.executorEpoch(), signerEpoch: 0
        });
        vm.expectRevert(abi.encodeWithSelector(SentinelVaultV35.WrongToken.selector, address(0x1234)));
        vm.prank(executor);
        vault.execute(p, "");
    }

    function testFix_F2_RollingGuardBlocksMidnightBurst() public {
        PolicyGuardRolling g = new PolicyGuardRolling(address(this), 400_000, 400_000);
        g.setRecipient(recipient, true);
        uint256 midnight = (block.timestamp / 1 days + 1) * 1 days;
        vm.warp(midnight - 1);
        g.consume(recipient, 400_000);
        vm.warp(midnight);
        vm.expectRevert(); // only ~4 base units have refilled after 1s
        g.consume(recipient, 400_000);
        vm.warp(midnight - 1 + 12 hours);
        g.consume(recipient, 200_000); // half refilled after 12h
        assertEq(g.remainingToday(), 0);
    }

    function testFuzz_F2_RollingGuardNeverExceedsCapacityPlusRefill(uint32 gap1, uint32 gap2) public {
        PolicyGuardRolling g = new PolicyGuardRolling(address(this), 400_000, 400_000);
        g.setRecipient(recipient, true);
        uint256 start = block.timestamp;
        uint256 spent;
        uint256[3] memory gaps = [uint256(0), uint256(gap1 % 2 days), uint256(gap2 % 2 days)];
        for (uint256 i; i < 3; ++i) {
            vm.warp(block.timestamp + gaps[i]);
            uint256 r = g.remainingToday();
            if (r > 0) { g.consume(recipient, r); spent += r; }
        }
        uint256 elapsed = block.timestamp - start;
        assertLe(spent, 400_000 + elapsed * 400_000 / 1 days + 3);
    }
}
