// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice TEST-ONLY fee-on-transfer token. Never use as QUSDC.
contract MockV35FeeToken is ERC20 {
    constructor() ERC20("Fee Test Token", "FEE") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @dev A 10% fee is burned. Sender loses amount; receiver gets only 90%.
    function _update(address from, address to, uint256 amount) internal override {
        if (from != address(0) && to != address(0) && amount >= 10) {
            uint256 fee = amount / 10;
            super._update(from, to, amount - fee);
            super._update(from, address(0), fee);
        } else {
            super._update(from, to, amount);
        }
    }
}
