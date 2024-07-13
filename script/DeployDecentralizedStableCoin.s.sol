// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";

import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";

contract DeployDecentralizedStableCoin is Script {
    function run()
        public
        returns (DecentralizedStableCoin decentralizedStableCoin)
    {
        vm.startBroadcast();
        decentralizedStableCoin = new DecentralizedStableCoin();
        vm.stopBroadcast();
    }
}
