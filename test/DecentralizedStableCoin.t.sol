// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";

import {DeployDecentralizedStableCoin} from "../script/DeployDecentralizedStableCoin.s.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";

contract DecentralizedStableCoinTest is Test {
    DeployDecentralizedStableCoin private deployer;
    DecentralizedStableCoin private decentralizedStableCoin;

    address owner;
    address userOne = makeAddr("userOne");

    uint256 INITIAL_USER_BALANCE = 10 ether;

    function setUp() public {
        deployer = new DeployDecentralizedStableCoin();
        decentralizedStableCoin = deployer.run();

        owner = decentralizedStableCoin.owner();
    }

    function testNameAndSymbol() public view {
        assert(
            keccak256(abi.encodePacked(decentralizedStableCoin.name())) ==
                keccak256("DecentralizedStableCoin")
        );
        assert(
            keccak256(abi.encodePacked(decentralizedStableCoin.symbol())) ==
                keccak256("DSC")
        );
    }

    function testMint() public {
        vm.prank(owner);
        decentralizedStableCoin.mint(userOne, INITIAL_USER_BALANCE);

        assert(
            decentralizedStableCoin.balanceOf(userOne) == INITIAL_USER_BALANCE
        );
    }
}
