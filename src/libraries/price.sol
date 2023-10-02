// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "v3-core/interfaces/IUniswapV3Factory.sol";
import "v3-core/interfaces/IUniswapV3Pool.sol";

import {IERC20Metadata as IERC20} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

library PriceUtil {
    uint256 constant PRICE_SCALE = 1e18;
    uint256 constant Q96 = 0x1000000000000000000000000;

    function getPrice1(address factory, address token0, address token1, uint24 fee) public view returns (uint256 price) {
        address pool = IUniswapV3Factory(factory).getPool(token0, token1, fee);
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        if (sqrtPriceX96 > Q96) {
            uint256 sqrtP = sqrtPriceX96 * 10 ** IERC20(token0).decimals() / Q96;
            price = sqrtP * sqrtP / 10 ** IERC20(token0).decimals();
        } else {
            uint256 numerator1 = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);
            uint256 numerator2 = 10 ** IERC20(token0).decimals();
            price = numerator1 * numerator2 / (Q96 * Q96);
        }

        price = 10 ** IERC20(token1).decimals() * PRICE_SCALE / price;
    }
}