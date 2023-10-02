// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Script.sol";

import "src/rebalance.sol";
import "src/libraries/price.sol";
import "src/libraries/address.sol";

contract Goerli is Script {
    address payable constant REBALANCE = payable(0x7102E934Ba4C963b5083E3879046Ac80f93BC907);
    address constant WETH = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
    address constant USDC = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    uint24 constant FEE = 0.05e4;
    int24 constant TICK_OFFSET = 5;
    uint24 constant SWAP_OFFSET = 0.05e4;
    uint256 constant SWAP_PROPORTION = 0.5e4;
    uint256 constant SLIPPAGE = 0.0005e4;
    uint256 constant TOKEN_ID = 1072275;

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privateKey);

        uint256 price1 = PriceUtil.getPrice1(Address.FACTORY, USDC, WETH, FEE);

        INonfungiblePositionManager(Address.POSITION_MANAGER).safeTransferFrom(
            vm.addr(privateKey),
            REBALANCE,
            TOKEN_ID,
            abi.encode(
                Rebalance.Instruction(
                    0,
                    0,
                    SWAP_PROPORTION,
                    PriceUtil.PRICE_SCALE,
                    price1,
                    SLIPPAGE,
                    block.timestamp + 3 minutes
                )
            )
        );

        Rebalance(REBALANCE).mint(
            Rebalance.MintParam(
                USDC,
                WETH,
                FEE,
                TICK_OFFSET,
                SWAP_OFFSET,
                PriceUtil.PRICE_SCALE,
                price1,
                SLIPPAGE,
                block.timestamp + 3 minutes
            )
        );

        vm.stopBroadcast();
    }
}