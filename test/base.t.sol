// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "src/rebalance.sol";
import "src/libraries/address.sol";

contract BaseTest is Test {
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    Rebalance public rebalance;

    function setUp() virtual public {
        vm.createSelectFork("https://rpc.ankr.com/eth");

        rebalance = new Rebalance(Address.FACTORY, Address.POSITION_MANAGER, Address.ROUTER);
    }

    function testToken0OutMin() public {
        assertEq(rebalance.token0OutMin(USDC, WETH, 1, 1600, 5, 1e18), 1599.2e6);
    }

    function testToken1OutMin() public {
        assertEq(rebalance.token1OutMin(USDC, WETH, 1, 1600, 5, 1600e6), 0.9995e18);
    }

    function testTokensAreSentToOwner() public {
        deal(address(this), 0);
        deal(address(rebalance), 1 ether);
        deal(USDC, address(rebalance), 1 ether);
        deal(WETH, address(rebalance), 1 ether);
        address other = makeAddr("Others");
        vm.startPrank(other);

        address[] memory tokens = new address[](2);
        tokens[0] = USDC;
        tokens[1] = WETH;
        uint256[] memory tokenIds = new uint256[](0);
        rebalance.withdraw(tokens, tokenIds);

        assertEq(address(other).balance, 0);
        assertEq(IERC20(USDC).balanceOf(other), 0);
        assertEq(IERC20(WETH).balanceOf(other), 0);
        assertEq(address(this).balance, 1 ether);
        assertEq(IERC20(USDC).balanceOf(address(this)), 1 ether);
        assertEq(IERC20(WETH).balanceOf(address(this)), 1 ether);
    }

    receive() external payable {}
}