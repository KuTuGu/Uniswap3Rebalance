// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "v3-core/libraries/TickMath.sol";
import "v3-periphery/libraries/LiquidityAmounts.sol";

import "src/rebalance.sol";
import "src/libraries/price.sol";
import "src/libraries/address.sol";

import "./base.t.sol";

contract IntegrationtTest is BaseTest {
    uint24 constant FEE = 0.05e4;
    int24 constant TICK_OFFSET = 1;
    uint24 constant SWAP_OFFSET = 0.05e4;
    uint256 constant SWAP_PROPORTION = 1e4;
    uint256 constant SLIPPAGE = 0.005e4;

    function setUp() override public {
        BaseTest.setUp();
    }

    function testRebalance() public {
        uint256 tokenId = _mintLP(address(this));
        assertEq(INonfungiblePositionManager(Address.POSITION_MANAGER).ownerOf(tokenId), address(this));
        _logAmount(tokenId);
        
        address people = makeAddr("Others");
        vm.startPrank(people);
        uint256 hugeAmount = 1e12;
        deal(USDC, people, hugeAmount);
        IERC20(USDC).approve(Address.ROUTER, type(uint256).max);
        ISwapRouter(Address.ROUTER).exactInputSingle(ISwapRouter.ExactInputSingleParams(
            USDC,
            WETH,
            FEE,
            people,
            block.timestamp,
            hugeAmount,
            0,
            0
        ));
        vm.stopPrank();
        _logAmount(tokenId);

        INonfungiblePositionManager(Address.POSITION_MANAGER).safeTransferFrom(
            address(this),
            address(rebalance),
            tokenId,
            abi.encode(
                Rebalance.Instruction(
                    0,
                    0,
                    SWAP_PROPORTION,
                    PriceUtil.PRICE_SCALE,
                    PriceUtil.getPrice1(Address.FACTORY, USDC, WETH, FEE),
                    SLIPPAGE,
                    block.timestamp
                )
            )
        );
        _logAmount(0);
    }

    function _logAmount(uint256 tokenId) internal view {
        if (tokenId > 0) {
            address pool = IUniswapV3Factory(Address.FACTORY).getPool(USDC, WETH, FEE);
            (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
            (,,,,, int24 tickLower, int24 tickUpper, uint128 liquidity,,,,) = INonfungiblePositionManager(Address.POSITION_MANAGER).positions(tokenId);
            (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtPriceX96,
                TickMath.getSqrtRatioAtTick(tickLower),
                TickMath.getSqrtRatioAtTick(tickUpper),
                liquidity
            );
            console2.log("LP Amount:", amount0, amount1);
        }

        console2.log("Contract Amount:", IERC20(USDC).balanceOf(address(rebalance)), IERC20(WETH).balanceOf(address(rebalance)));
    }

    function _mintLP(address user) internal returns (uint256 tokenId) {
        uint256 price1 = PriceUtil.getPrice1(Address.FACTORY, USDC, WETH, FEE);
        uint256 amount0 = price1 * 10 ** IERC20(USDC).decimals() / PriceUtil.PRICE_SCALE;
        deal(USDC, user, amount0);
        vm.startPrank(user);
        IERC20(USDC).transfer(address(rebalance), amount0);

        tokenId = rebalance.mint(
            Rebalance.MintParam(
                USDC,
                WETH,
                FEE,
                TICK_OFFSET,
                SWAP_OFFSET,
                PriceUtil.PRICE_SCALE,
                price1,
                SLIPPAGE,
                block.timestamp
            )
        );
    }
}