// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {CoinbaseToken} from "../src/CoinbaseToken.sol";

/// @dev Closed set of holders lets the invariant account for every token after arbitrary operations.
contract CoinbaseTokenHandler is Test {
    CoinbaseToken public immutable token;
    address[4] private holders;

    constructor(CoinbaseToken token_, address[4] memory holders_) {
        token = token_;
        holders = holders_;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) public {
        address from = holders[fromSeed % holders.length];
        address to = holders[toSeed % holders.length];
        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);
        amount = bound(amount, 0, fromBefore);

        vm.prank(from);
        assertTrue(token.transfer(to, amount));

        assertEq(token.balanceOf(from), from == to ? fromBefore : fromBefore - amount);
        assertEq(token.balanceOf(to), from == to ? toBefore : toBefore + amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) public {
        address owner = holders[ownerSeed % holders.length];
        address spender = holders[spenderSeed % holders.length];
        uint256 beforeBalance = token.balanceOf(owner);
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(owner, spender), amount);
        assertEq(token.balanceOf(owner), beforeBalance);
    }

    function transferFrom(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 amount) public {
        address from = holders[fromSeed % holders.length];
        address to = holders[toSeed % holders.length];
        address spender = holders[spenderSeed % holders.length];
        uint256 available = token.allowance(from, spender);
        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);
        amount = bound(amount, 0, available < fromBefore ? available : fromBefore);

        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));

        assertEq(token.allowance(from, spender), available == type(uint256).max ? available : available - amount);
        assertEq(token.balanceOf(from), from == to ? fromBefore : fromBefore - amount);
        assertEq(token.balanceOf(to), from == to ? toBefore : toBefore + amount);
    }

    function rejectedTransfer(uint256 fromSeed, uint256 toSeed) public {
        address from = holders[fromSeed % holders.length];
        address to = holders[toSeed % holders.length];
        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);

        vm.prank(from);
        (bool succeeded,) = address(token).call(abi.encodeCall(token.transfer, (to, fromBefore + 1)));

        assertFalse(succeeded);
        assertEq(token.balanceOf(from), fromBefore);
        assertEq(token.balanceOf(to), toBefore);
    }
}

contract CoinbaseTokenInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    CoinbaseToken private token;
    address[4] private holders;

    function setUp() public {
        holders = [makeAddr("holder one"), makeAddr("holder two"), makeAddr("holder three"), makeAddr("holder four")];
        token = new CoinbaseToken();
        assertTrue(token.transfer(holders[0], SUPPLY));
        CoinbaseTokenHandler handler = new CoinbaseTokenHandler(token, holders);

        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        selectors[3] = handler.rejectedTransfer.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_TotalSupplyAndAggregateBalancesStayFixed() public view {
        uint256 aggregate;
        for (uint256 i; i < holders.length; ++i) {
            aggregate += token.balanceOf(holders[i]);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(aggregate, SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function invariant_MetadataStaysFixed() public view {
        assertEq(token.name(), "Coinbase");
        assertEq(token.symbol(), "COINBASE");
        assertEq(token.decimals(), 18);
    }
}
