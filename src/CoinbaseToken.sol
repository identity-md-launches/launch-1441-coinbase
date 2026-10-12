// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Coinbase (COINBASE)
/// @notice Fixed-supply ERC-20 with 18 decimals and the entire supply minted to its deployer.
contract CoinbaseToken is ERC20 {
    /// @notice One billion tokens, expressed in the smallest token unit.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @dev A factory deployment credits the factory, which is responsible for distribution.
    constructor() ERC20("Coinbase", "COINBASE") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
