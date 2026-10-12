// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {CoinbaseToken} from "src/CoinbaseToken.sol";

/// @dev Regression and algebraic properties complement the original deployment and transfer suite.
/// forge-config: default.fuzz.runs = 1000
contract CoinbaseTokenAllowanceTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    CoinbaseToken private token;
    address private alice;
    address private bob;
    address private spender;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        token = new CoinbaseToken();
        alice = makeAddr("allowance owner");
        bob = makeAddr("allowance recipient");
        spender = makeAddr("allowance spender");
    }

    function test_OneWeiCanMakeARoundTrip() public {
        assertTrue(token.transfer(alice, 1));
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), 1));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumFiniteAllowanceIsSpentRatherThanTreatedAsInfinite() public {
        assertTrue(token.approve(spender, type(uint256).max - 1));
        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertTrue(token.transferFrom(address(this), bob, 1));
        vm.stopPrank();
        assertEq(token.allowance(address(this), spender), type(uint256).max - 3);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_InfiniteAllowanceCanBeReplacedAndRevokedAfterUse() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        assertTrue(token.approve(spender, 2));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 2));
        _expectAllowanceFailure(address(this), 0, 1);

        assertTrue(token.approve(spender, type(uint256).max));
        assertTrue(token.approve(spender, 0));
        _expectAllowanceFailure(address(this), 0, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 3);
        assertEq(token.balanceOf(alice), 3);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_RefundDoesNotRestoreAnExhaustedAllowance() public {
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        vm.prank(alice);
        assertTrue(token.transfer(address(this), 1));

        _expectAllowanceFailure(address(this), 0, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_RemainingAllowanceSurvivesAnEmptyBalanceAndRefill() public {
        assertTrue(token.transfer(alice, 1));
        vm.prank(alice);
        assertTrue(token.approve(spender, 2));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(alice, spender), 1);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(alice, spender), 1);
        assertTrue(token.transfer(alice, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 2);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
    }

    function test_OwnerSpenderAndRecipientCanAllBeTheSameAccount() public {
        assertTrue(token.approve(address(this), SUPPLY));
        assertTrue(token.transferFrom(address(this), address(this), SUPPLY));
        assertEq(token.allowance(address(this), address(this)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);

        assertTrue(token.approve(address(this), type(uint256).max));
        assertTrue(token.transferFrom(address(this), address(this), SUPPLY));
        assertEq(token.allowance(address(this), address(this)), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroDelegatedTransferEmitsEventAndPreservesFiniteAllowance() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 1);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumTransferAmountFailsWithoutConsumingInfiniteApproval() public {
        bytes memory expected = abi.encodeWithSelector(
            IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
        );
        vm.expectRevert(expected);
        token.transfer(alice, type(uint256).max);

        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(expected);
        vm.prank(spender);
        token.transferFrom(address(this), alice, type(uint256).max);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroSpenderIsInvalidForBothZeroAndMaximumApproval() public {
        bytes memory expected = abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0));
        vm.expectRevert(expected);
        token.approve(address(0), 0);
        vm.expectRevert(expected);
        token.approve(address(0), type(uint256).max);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_ZeroTransferFromToZeroAddressStillReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 0);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferFromZeroCannotMintAtBoundaryAmounts() public {
        _assertZeroSourceReverts(0);
        _assertZeroSourceReverts(1);
        _assertZeroSourceReverts(type(uint256).max);
    }

    function testFuzz_LoweringAllowanceImmediatelyInvalidatesThePreviousGrant(uint256 original, uint256 lower) public {
        original = bound(original, 1, SUPPLY);
        lower = bound(lower, 0, original - 1);
        assertTrue(token.approve(spender, original));
        assertTrue(token.approve(spender, lower));

        _expectAllowanceFailure(address(this), lower, lower + 1);
        assertEq(token.allowance(address(this), spender), lower);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, lower));
        _expectAllowanceFailure(address(this), 0, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - lower);
        assertEq(token.balanceOf(bob), lower);
    }

    function testFuzz_FailedSpendCanBeRetriedAfterFunding(uint256 held, uint256 amount, bool infinite) public {
        held = bound(held, 0, SUPPLY - 1);
        amount = bound(amount, held + 1, SUPPLY);
        assertTrue(token.transfer(alice, held));
        uint256 granted = infinite ? type(uint256).max : amount;
        vm.prank(alice);
        assertTrue(token.approve(spender, granted));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), granted);
        assertEq(token.balanceOf(alice), held);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - held);

        assertTrue(token.transfer(alice, amount - held));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, amount));
        assertEq(token.allowance(alice, spender), infinite ? type(uint256).max : 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_AllowancesAreIsolatedByBothOwnerAndSpender(
        uint256 firstGrant,
        uint256 secondGrant,
        uint256 otherOwnerGrant,
        uint256 amount
    ) public {
        assertTrue(token.transfer(alice, SUPPLY / 2));
        assertTrue(token.approve(spender, firstGrant));
        assertTrue(token.approve(bob, secondGrant));
        vm.prank(alice);
        assertTrue(token.approve(spender, otherOwnerGrant));
        amount = bound(amount, 0, firstGrant < SUPPLY / 2 ? firstGrant : SUPPLY / 2);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, amount));
        assertEq(
            token.allowance(address(this), spender), firstGrant == type(uint256).max ? firstGrant : firstGrant - amount
        );
        assertEq(token.allowance(address(this), bob), secondGrant);
        assertEq(token.allowance(alice, spender), otherOwnerGrant);
        assertEq(token.allowance(alice, bob), 0);
        assertEq(token.allowance(spender, address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY / 2);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY / 2 - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_DelegatedTransferInPartsEqualsOneTransfer(uint256 first, uint256 second, uint256 grant) public {
        first = bound(first, 0, SUPPLY);
        second = bound(second, 0, SUPPLY - first);
        grant = bound(grant, first + second, type(uint256).max);
        CoinbaseToken single = new CoinbaseToken();
        assertTrue(token.approve(spender, grant));
        assertTrue(single.approve(spender, grant));

        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, first));
        assertTrue(token.transferFrom(address(this), alice, second));
        assertTrue(single.transferFrom(address(this), alice, first + second));
        vm.stopPrank();
        assertEq(token.balanceOf(alice), single.balanceOf(alice));
        assertEq(token.balanceOf(address(this)), single.balanceOf(address(this)));
        assertEq(token.allowance(address(this), spender), single.allowance(address(this), spender));
        assertEq(token.balanceOf(alice), first + second);
        assertEq(token.balanceOf(address(this)), SUPPLY - first - second);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(single.totalSupply(), SUPPLY);
    }

    function testFuzz_DirectTransferRoundTripPreservesApprovals(uint256 amount, uint256 grant) public {
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.approve(spender, grant));
        vm.prank(alice);
        assertTrue(token.approve(spender, grant));
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), amount);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), amount));

        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), grant);
        assertEq(token.allowance(alice, spender), grant);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferFromZeroCannotMint(uint256 amount) public {
        _assertZeroSourceReverts(amount);
    }

    function _assertZeroSourceReverts(uint256 amount) private {
        // Zero fails on the invalid owner; positive values fail on its absent approval.
        // Both must revert, and neither may reach the internal mint path.
        vm.expectRevert();
        vm.prank(spender);
        token.transferFrom(address(0), bob, amount);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(0), spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function _expectAllowanceFailure(address owner, uint256 available, uint256 requested) private {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, available, requested)
        );
        vm.prank(spender);
        token.transferFrom(owner, bob, requested);
    }
}
