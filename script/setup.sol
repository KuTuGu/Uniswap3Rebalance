// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Script.sol";

import "src/rebalance.sol";
import "src/libraries/address.sol";

contract Setup is Script {
    function run() public {
        vm.startBroadcast();

        new Rebalance(Address.FACTORY, Address.POSITION_MANAGER, Address.ROUTER);

        vm.stopBroadcast();
    }
}