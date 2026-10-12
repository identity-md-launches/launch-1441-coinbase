// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {CoinbaseToken} from "../src/CoinbaseToken.sol";

/// @dev Closed set of holders lets the invariant account for every token after arbitrary operations.
contract CoinbaseTokenHandler is Test {
    CoinbaseToken public immutable token;
    address[4] private holders;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(CoinbaseToken token_, address[4] memory holders_, uint256 initialBalance) {
        token = token_;
        holders = holders_;
        // Seed the ledger from the intended distribution, never from balanceOf.
        for (uint256 i; i < holders.length; ++i) {
            expectedBalance[holders[i]] = initialBalance;
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) public {
        address from = holders[fromSeed % holders.length];
        address to = holders[toSeed % holders.length];
        uint256 fromBefore = expectedBalance[from];
        uint256 toBefore = expectedBalance[to];
        amount = bound(amount, 0, fromBefore);

        vm.prank(from);
        assertTrue(token.transfer(to, amount));

        assertEq(token.balanceOf(from), from == to ? fromBefore : fromBefore - amount);
        assertEq(token.balanceOf(to), from == to ? toBefore : toBefore + amount);
        _moveExpectedBalance(from, to, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) public {
        address owner = holders[ownerSeed % holders.length];
        address spender = holders[spenderSeed % holders.length];
        _approve(owner, spender, amount);
        assertEq(token.balanceOf(owner), expectedBalance[owner]);
    }

    function transferFrom(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 amount) public {
        address from = holders[fromSeed % holders.length];
        address to = holders[toSeed % holders.length];
        address spender = holders[spenderSeed % holders.length];
        uint256 available = expectedAllowance[from][spender];
        uint256 fromBefore = expectedBalance[from];
        uint256 toBefore = expectedBalance[to];
        amount = bound(amount, 0, available < fromBefore ? available : fromBefore);

        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));

        assertEq(token.allowance(from, spender), available == type(uint256).max ? available : available - amount);
        assertEq(token.balanceOf(from), from == to ? fromBefore : fromBefore - amount);
        assertEq(token.balanceOf(to), from == to ? toBefore : toBefore + amount);
        if (available != type(uint256).max) expectedAllowance[from][spender] -= amount;
        _moveExpectedBalance(from, to, amount);
    }

    function rejectedTransfer(uint256 fromSeed, uint256 toSeed) public {
        address from = holders[fromSeed % holders.length];
        address to = holders[toSeed % holders.length];
        uint256 fromBefore = expectedBalance[from];
        uint256 toBefore = expectedBalance[to];
        _expectFailure(
            from,
            abi.encodeCall(token.transfer, (to, fromBefore + 1)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, fromBefore, fromBefore + 1)
        );
        assertEq(token.balanceOf(from), fromBefore);
        assertEq(token.balanceOf(to), toBefore);
    }

    function transferFullBalance(uint256 fromSeed, uint256 toSeed) public {
        transfer(fromSeed, toSeed, expectedBalance[holders[fromSeed % holders.length]]);
    }

    function approveMaximum(uint256 ownerSeed, uint256 spenderSeed) public {
        approve(ownerSeed, spenderSeed, type(uint256).max);
    }

    function revoke(uint256 ownerSeed, uint256 spenderSeed) public {
        approve(ownerSeed, spenderSeed, 0);
    }

    function rejectedTransferFromAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) public {
        address owner = holders[ownerSeed % holders.length];
        address spender = holders[spenderSeed % holders.length];
        // Include revocation and exact exhaustion; the balance can also be insufficient.
        uint256 allowed = bound(amount, 0, expectedBalance[owner]);
        _approve(owner, spender, allowed);
        _expectFailure(
            spender,
            abi.encodeCall(token.transferFrom, (owner, spender, allowed + 1)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, allowed + 1)
        );
    }

    function rejectedTransferFromBalance(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) public {
        address owner = holders[ownerSeed % holders.length];
        address spender = holders[spenderSeed % holders.length];
        uint256 held = expectedBalance[owner];
        amount = bound(amount, held + 1, type(uint256).max);
        _approve(owner, spender, amount);
        // Allowance validation succeeds, but the whole operation must roll back on balance failure.
        _expectFailure(
            spender,
            abi.encodeCall(token.transferFrom, (owner, spender, amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, held, amount)
        );
    }

    function rejectedZeroAddress(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, uint8 operation) public {
        address owner = holders[ownerSeed % holders.length];
        address spender = holders[spenderSeed % holders.length];
        if (operation % 3 == 0) {
            _expectFailure(
                owner,
                abi.encodeCall(token.approve, (address(0), amount)),
                abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
            );
        } else if (operation % 3 == 1) {
            _expectFailure(
                owner,
                abi.encodeCall(token.transfer, (address(0), amount)),
                abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
            );
        } else {
            amount = bound(amount, 0, expectedBalance[owner]);
            _approve(owner, spender, amount);
            _expectFailure(
                spender,
                abi.encodeCall(token.transferFrom, (owner, address(0), amount)),
                abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
            );
        }
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
        assertEq(token.allowance(owner, spender), amount);
    }

    function _moveExpectedBalance(address from, address to, uint256 amount) private {
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function _expectFailure(address caller, bytes memory data, bytes memory expectedError) private {
        vm.prank(caller);
        (bool succeeded, bytes memory result) = address(token).call(data);
        assertFalse(succeeded, "invalid operation succeeded");
        assertEq(result, expectedError, "unexpected failure reason");
        // No ghost update: the invariants must see every balance and allowance unchanged.
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 96
/// forge-config: default.invariant.fail-on-revert = true
contract CoinbaseTokenInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    CoinbaseToken private token;
    address[4] private holders;
    CoinbaseTokenHandler private handler;

    function setUp() public {
        holders = [makeAddr("holder one"), makeAddr("holder two"), makeAddr("holder three"), makeAddr("holder four")];
        token = new CoinbaseToken();
        for (uint256 i; i < holders.length; ++i) {
            assertTrue(token.transfer(holders[i], SUPPLY / holders.length));
        }
        handler = new CoinbaseTokenHandler(token, holders, SUPPLY / holders.length);
        // Give the campaign spendable finite allowances before it starts exploring replacements.
        for (uint256 i; i < holders.length; ++i) {
            handler.approve(i, (i + 1) % holders.length, SUPPLY / holders.length);
        }

        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        selectors[3] = handler.rejectedTransfer.selector;
        selectors[4] = handler.transferFullBalance.selector;
        selectors[5] = handler.approveMaximum.selector;
        selectors[6] = handler.revoke.selector;
        selectors[7] = handler.rejectedTransferFromAllowance.selector;
        selectors[8] = handler.rejectedTransferFromBalance.selector;
        selectors[9] = handler.rejectedZeroAddress.selector;
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
        assertEq(token.balanceOf(address(handler)), 0);
    }

    function invariant_EveryBalanceAndAllowanceMatchesTheLedger() public view {
        for (uint256 i; i < holders.length; ++i) {
            address owner = holders[i];
            assertEq(token.balanceOf(owner), handler.expectedBalance(owner), "holder balance diverged");
            assertEq(token.allowance(owner, address(0)), 0, "zero spender received approval");
            assertEq(token.allowance(address(0), owner), 0, "zero owner received approval");
            for (uint256 j; j < holders.length; ++j) {
                address spender = holders[j];
                assertEq(
                    token.allowance(owner, spender),
                    handler.expectedAllowance(owner, spender),
                    "allowance changed outside its owner's grant or spender's spend"
                );
            }
        }
    }

    function invariant_MetadataStaysFixed() public view {
        assertEq(token.name(), "Coinbase");
        assertEq(token.symbol(), "COINBASE");
        assertEq(token.decimals(), 18);
    }

    function afterInvariant() public {
        // Each holder must still be able to move its entire balance after an arbitrary history.
        // Walking the ring consolidates all tokens at holder zero without privileged intervention.
        for (uint256 i; i < holders.length; ++i) {
            handler.transferFullBalance(i, (i + 1) % holders.length);
        }
        assertEq(token.balanceOf(holders[0]), SUPPLY);
        for (uint256 i = 1; i < holders.length; ++i) {
            assertEq(token.balanceOf(holders[i]), 0);
        }
        invariant_TotalSupplyAndAggregateBalancesStayFixed();
        invariant_EveryBalanceAndAllowanceMatchesTheLedger();
        invariant_MetadataStaysFixed();
    }
}
