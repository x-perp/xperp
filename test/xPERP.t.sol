// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

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
    address constant teamTestWallet = 0x282e0D30DF3C7Ecb58430d31c1A28De4f9ee7F44;
    IUniswapV2Pair internal uniswapV2Pair;
    IUniswapV2Router02 internal uniswapV2Router;
    address internal weth;

    /// @dev A function invoked before each test case is run.
    function setUp() public virtual {
        // Instantiate the contract-under-test.
        xperp = new xPERP(teamTestWallet);
    }

    /// @dev Total Supply check
    function testSupplyCheck() external {
        uint256 balance = xperp.balanceOf(address(this));
        assertEq(balance, 1_000_000e18, "balance mismatch");
    }

    function fundPair(uint256 amountETHToUse, uint256 amountTokenToUse) public {
        uniswapV2Pair = IUniswapV2Pair(xperp.uniswapV2Pair());
        uniswapV2Router = IUniswapV2Router02(xperp.uniswapV2Router());
        weth = uniswapV2Router.WETH();
        xperp.approve(address(uniswapV2Router), 1_000_000e18);
        uniswapV2Router.addLiquidityETH{value: amountETHToUse}(
            address(xperp),
            amountTokenToUse,
            0,
            0,
            address(this),
            block.timestamp
        );
    }

    /// @dev Total Supply check
    function testUniswapPairFund() public {
        // depositing 50 ether / 990_000 xperp
        uint256 amountETHToUse = 30e18;
        uint256 amountTokenToUse = 990_000e18;
        fundPair(amountETHToUse, amountTokenToUse);
        (uint reserveA, uint reserveB,) = uniswapV2Pair.getReserves();
        assertEq(reserveA, amountTokenToUse, "reserves A (XPERP) are wrong");
        assertEq(reserveB, amountETHToUse, "reserves B (ETH) are wrong");
    }

    /// @dev buy on uniswap, sell on uniswap for ether, taxes are correct
    function testSwap() public {
        //fund the pair
        uint256 amountETHToUse = 10e18;
        uint256 amountTokenToUse = 990_000e18;
        fundPair(amountETHToUse, amountTokenToUse);

        xperp.EnableTradingOnUniSwap();

        amountETHToUse = 1e18;
        uint256 balanceBeforeETH = address(this).balance;
        uint256 balanceBeforeXPERP = xperp.balanceOf(address(this));
        address[] memory path = new address[](2);
        path[0] = weth;
        path[1] = address(xperp);

        // Fetch reserves
        (uint reserveA, uint reserveB,) = uniswapV2Pair.getReserves();
        // Make sure reserveA corresponds to ETH and reserveB to XPERP
        address token0 = uniswapV2Pair.token0();
        if (token0 == address(xperp)) {
            (reserveA, reserveB) = (reserveB, reserveA);
        }

        // Calculate expected XPERP
        uint256 amountInWithFee = amountETHToUse * 997;  // 0.3% fee is subtracted
        uint256 numerator = amountInWithFee * reserveB;
        uint256 denominator = reserveA * 1000 + amountInWithFee;  // 0.3% fee is added
        uint256 expectedXPERP = numerator / denominator;

        // Apply 5% tax, the formula is  expectedXPERPAfterTax = (expectedXPERP * 9500) / 10000;
        uint256 expectedXPERPAfterTax = (numerator * 950) / (1000 * denominator);

        uint256 contractBalanceBeforeSwap = xperp.balanceOf(address(xperp));
        // buy 1 ether worth of xperp
        uniswapV2Router.swapExactETHForTokens{value: amountETHToUse}(
            0,
            path,
            address(this),
            block.timestamp
        );
        assertEq(address(this).balance, balanceBeforeETH - amountETHToUse, "ETH balance mismatch");
        assertEq(expectedXPERPAfterTax, xperp.balanceOf(address(this)) - balanceBeforeXPERP, "XPERP balance mismatch");

        //check taxes, team wallet gets 2%
        assertEq(xperp.balanceOf(teamTestWallet), expectedXPERP * 20 / 1000, "team wallet balance mismatch");
        //the contract gets 1% (revshare distribution) + 2%
        assertEq(xperp.balanceOf(address(xperp)), contractBalanceBeforeSwap + expectedXPERP * 30 / 1000, "contract balance mismatch");
        // check distribution 1% to the liquidity pair
        assertEq(xperp.liquidityPairTaxCollectedNotYetInjectedXPERP(), expectedXPERP * 10 / 1000, "liquidityPairTaxCollectedNotYetInjected mismatch");
        // 2% revenue share (the rest to avoid rounding errors)
        assertEq(xperp.revenueSharesCollectedSinceLastEpochXPERP(), expectedXPERP * 20 / 1000, "liquidityPairTaxCollectedNotYetInjected mismatch");
    }

    function testInjectLiquidity() public {
        // depositing 20 eth and 990K xperp in the pair
        uint256 amountETHToUse = 20e18;
        uint256 amountTokenToUse = 990_000e18;
        fundPair(amountETHToUse, amountTokenToUse);
        xperp.EnableTradingOnUniSwap();

        // swap tokens to generate lp share 1%
        address[] memory path = new address[](2);
        path[0] = weth;
        path[1] = address(xperp);
        uniswapV2Router.swapExactETHForTokens{value: 1e18}(
            0,
            path,
            address(this),
            block.timestamp
        );

        // checking the amount of xperp that is a 1% lp tax
        uint lpShare = xperp.liquidityPairTaxCollectedNotYetInjectedXPERP();


        (uint reserveA, uint reserveB,) = IUniswapV2Pair(xperp.uniswapV2Pair()).getReserves();
        console2.log("liquidityPairTaxCollectedNotYetInjectedXPERP", lpShare);
        console2.log("xperp balance on the contract", xperp.balanceOf(address(xperp)));
        console2.log("reserveA", reserveA);
        console2.log("reserveB", reserveB);

        //fund the pair
        console2.log("eth on the contract before injection", address(xperp).balance);
        console2.log("token on the contract before injection", xperp.balanceOf(address(xperp)));

        xperp.injectLiquidity(0);
//        xperp.injectLiquidity{value: 1 ether}();
        console2.log("eth on the contract", address(xperp).balance);
        console2.log("token on the contract", xperp.balanceOf(address(xperp)));

        (reserveA, reserveB,) = IUniswapV2Pair(xperp.uniswapV2Pair()).getReserves();
        console2.log("reserveA", reserveA);
        console2.log("reserveB", reserveB);

        //fund the pair
        console2.log("eth on the contract after injection", address(xperp).balance);
        console2.log("token on the contract after injection", xperp.balanceOf(address(xperp)));
//        assertEq(xperp.balanceOf(address(xperp)), 0, "contract balance mismatch");

    }

    function testSnapshot() public {
        // depositing 20 eth and 990K xperp in the pair
        uint256 amountETHToUse = 20e18;
        uint256 amountTokenToUse = 990_000e18;
        fundPair(amountETHToUse, amountTokenToUse);
        xperp.EnableTradingOnUniSwap();

        //several users
        address user1 = address(0x13);
        address user2 = address(0x14);

        //fund these wallet with xperp tokens
        xperp.transfer(user1, 2000e18);
        xperp.transfer(user2, 4000e18);

        //swap to cgereate apair
        // swap tokens to generate lp share 1%
        address[] memory path = new address[](2);
        path[0] = weth;
        path[1] = address(xperp);
        uniswapV2Router.swapExactETHForTokens{value: 1e18}(
            0,
            path,
            address(this),
            block.timestamp
        );

        //make snapshot
        uint256 tv = 10e18;
        xperp.snapshot{value: tv}();

//        xperp.transfer(user1, 1e18);
        uniswapV2Router.swapExactETHForTokens{value: 1e18}(
            0,
            path,
            address(this),
            block.timestamp
        );
        uint256 tradingVolume = 10e18;
        xperp.snapshot{value: tradingVolume}();

        uint balanceBefore = xperp.balanceOf(user1);
        xperp.claimAll();
        uint balanceAfter = xperp.balanceOf(user1);

    }

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

    receive() external payable {}
}
