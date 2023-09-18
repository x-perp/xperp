// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <=0.9.0;

import {xPERP} from "../src/xPERP.sol";

import {BaseScript} from "./Base.s.sol";

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
contract Deploy is BaseScript {
    function run() public broadcast returns (xPERP deployed) {
        deployed = new xPERP(payable(address(0x05309918A451156C2cE41f3C8dF89672ce83e944)));
    }
}
