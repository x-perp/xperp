// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

import {PRBTest} from "@prb/test/PRBTest.sol";
import {console2} from "forge-std/console2.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {xPERP} from "../src/xPERP.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
}

/// @dev If this is your first time with Forge, read this tutorial in the Foundry Book:
/// https://book.getfoundry.sh/forge/writing-tests
contract xPERPTest is PRBTest, StdCheats {
    xPERP internal xperp;

    /// @dev A function invoked before each test case is run.
    function setUp() public virtual {
        // Instantiate the contract-under-test.
        xperp = new xPERP(address(this));
    }

    /// @dev Total Supply check
    function testSupplyCheck() external {
        uint256 balance = xperp.balanceOf(address(this));
        assertEq(balance, 1_000_000e18, "balance mismatch");
    }

    /// @dev Total Supply check
    function testUniswapPairFund() public {
        // depositing 50 ether / 970_000 xperp
        uint256 amountETHToUse = 20e18;
        uint256 amountTokenToUse = 970_000e18;
        xperp.uniswapV2Router().addLiquidityETH{value: amountETHToUse}(
            address(this),
            amountTokenToUse,
            0,
            0,
            address(this),
            block.timestamp
        );
        (uint reserveA, uint reserveB,) = IUniswapV2Pair(xperp.uniswapV2Pair()).getReserves();
        assertEq(reserveA, amountETHToUse, "reserves A are wrong");
        assertEq(reserveB, amountTokenToUse, "reserves B are wrong");
    }

    /// @dev buy on uniswap, sell on uniswap for ether, taxes are correct

    /// @dev transfer to another address, no taxes are paid
    /// @dev trasnfer limitation, 1% of total supply
    /// @dev revenue sharing

    /// @dev Fuzz test that provides random values for an unsigned integer, but which rejects zero as an input.
    /// If you need more sophisticated input validation, you should use the `bound` utility instead.
    /// See https://twitter.com/PaulRBerg/status/1622558791685242880
    function testFuzz_Example(uint256 x) external {
//        vm.assume(x != 0); // or x = bound(x, 1, 100)
//        assertEq(xperp.id(x), x, "value mismatch");
    }

    /// @dev Fork test that runs against an Ethereum Mainnet fork. For this to work, you need to set `API_KEY_ALCHEMY`
    /// in your environment You can get an API key for free at https://alchemy.com.
    function testFork_Example() external {
        // Silently pass this test if there is no API key.
        string memory alchemyApiKey = vm.envOr("API_KEY_ALCHEMY", string(""));
        if (bytes(alchemyApiKey).length == 0) {
            return;
        }

        // Otherwise, run the test against the mainnet fork.
        vm.createSelectFork({urlOrAlias: "mainnet", blockNumber: 16_428_000});
        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address holder = 0x7713974908Be4BEd47172370115e8b1219F4A5f0;
        uint256 actualBalance = IERC20(usdc).balanceOf(holder);
        uint256 expectedBalance = 196_307_713.810457e6;
        assertEq(actualBalance, expectedBalance);
    }
}
