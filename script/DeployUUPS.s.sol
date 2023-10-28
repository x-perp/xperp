// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.21;

import "@std/console.sol";
import "@std/Script.sol";

import "../src/XPERP.sol";
import "../src/UUPSProxy.sol";

contract DeployUUPS is Script {
    UUPSProxy proxy;
    XPERP wrappedProxy;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        XPERP implementation = new XPERP();

        // deploy proxy contract and point it to implementation
        proxy = new UUPSProxy(address(implementation), "");
        // wrap in ABI to support easier calls
        wrappedProxy = XPERP(payable(address(proxy)));
        wrappedProxy.initialize(payable(0x13e15FBf296248116729A47093C316d3209E95a1));
        wrappedProxy.initPair();
        vm.stopBroadcast();
        console2.log("wrappedProxy", address(wrappedProxy));
        console2.log("proxy", address(proxy));
        console2.log("implementation", address(implementation));
        console2.log("this", address(this));
    }

    function upgrade() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        wrappedProxy = XPERP(payable(address(0x64323d606CfCB1b50998636A182334Ad97637987)));
        vm.startBroadcast(deployerPrivateKey);
        XPERP implementation = new XPERP();
        wrappedProxy.upgradeToAndCall(address(implementation),"");
        vm.stopBroadcast();
        console2.log("wrappedProxy", address(wrappedProxy));
        console2.log("proxy", address(proxy));
        console2.log("implementation", address(implementation));
        console2.log("this", address(this));
    }

}
