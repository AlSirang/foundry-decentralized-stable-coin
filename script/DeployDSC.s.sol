// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";

import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";

import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    address[] public collateralAddress;
    address[] public priceFeeds;

    function run() public returns (DecentralizedStableCoin dsc, DSCEngine engine, HelperConfig helperConfig) {
        /// deploy helper config to get network configuration
        helperConfig = new HelperConfig();

        /// get network configuration
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            helperConfig.activeNetworkConfig();
        collateralAddress = [weth, wbtc];
        priceFeeds = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);
        /// deploy stable coin contract
        dsc = new DecentralizedStableCoin();

        /// deploy stable coin engine
        engine = new DSCEngine(collateralAddress, priceFeeds, address(dsc));

        /// transfer ownership of DSC to DSCEngine
        dsc.transferOwnership(address(engine));

        vm.stopBroadcast();
    }
}
