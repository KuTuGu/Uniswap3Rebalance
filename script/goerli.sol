// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Script.sol";

import "src/rebalance.sol";
import "src/libraries/price.sol";
import "src/libraries/address.sol";

contract Goerli is Script {
    address payable constant REBALANCE = payable(0xE5A30C1980D46a2E1a4D615eE68714351A1256Ef);
    address constant WETH = 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6;
    address constant GSU = 0x252D98faB648203AA33310721bBbDdfA8F1b6587;
    uint24 constant FEE = 1e4;
    int24 constant TICK_OFFSET = 5;
    uint24 constant SWAP_OFFSET = 0.05e4;
    uint256 constant SWAP_PROPORTION = 0.5e4;
    uint256 constant SLIPPAGE = 0.05e4;
    uint256 constant TOKEN_ID = 79992;

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privateKey);

        uint256 price1 = PriceUtil.getPrice1(Address.FACTORY, GSU, WETH, FEE);

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
                GSU,
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