// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

//  xPERP Token
//   ____  _____ ____  ____
//   __  _|  _ \| ____|  _ \|  _ \
//   \ \/ / |_) |  _| | |_) | |_) |
//    >  <|  __/| |___|  _ <|  __/
//   /_/\_\_|   |_____|_| \_\_|
// Go long or short with leverage on @friendtech keys via Telegram
// =====================================
// https://twitter.com/xperptech
// https://xperp.tech
// =====================================
// - Fair Launch: 99% of the token supply was added to liquidity at launch.
// - Partnership: 1% has been sold to Handz of Gods.
// - Supply: 1M tokens, fully circulating and non-dilutive.
// - Tax: 5% tax on xperp traded (1% to LP, 2% to revenue share, 2% to team and operating expenses).
// - Revenue Sharing: 30% of trading revenue goes to holders. xperp earns 2% of all trading volume.
// - Eligibility: Holders of xperp tokens are entitled to revenue sharing.

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

contract xPERP is ERC20, Ownable, ReentrancyGuard {

    // 1 Million is totalsuppy
    uint256 public constant oneMillion = 1_000_000 * 1 ether;

    // 1% of total supply, max tranfer amount possible
    uint256 public constant onePercentOfSupply = 10_000 * 1 ether;

    IUniswapV2Router02 public constant uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    // address of the uniswap pair
    address public uniswapV2Pair;

    // address of the revenue distribution bot
    address public revenueDistributionBot;

    // team wallet
    address public teamWallet;

    // switched on post launch
    bool public isTradingEnabled = false;

    // total swap tax collected, completely distributed among token holders
    uint256 public swapTaxCollectedTotal;

    // revenue sharing tax collected, completely distributed among token holders
    uint256 public revenueSharesCollectedSinceLastEpoch;

    // revenue sharing tax collected, completely distributed among token holders
    uint256 public tradingRevenueDistributedTotalETH;

    // revenue sharing tax collected, completely distributed among token holders
    uint256 public liquidityPairTaxCollectedNotYetInjected;

    // 2% of the tax goes to the team

    // Revenue sharing distribution info
    struct EpochInfo {
        // Snapshot time
        uint256 epochTimestamp;
        // Snapshot supply
        uint256 epochTotalSupply;
        // ETH collected for rewards for re-investors
        uint256 epochRevenueFromSwapTaxCollectedXPERP;
        // Injected 30% revenue from trading
        uint256 epochTradingRevenueETH;
        // Used to calculate holder balances at the time of snapshot
        mapping(address => uint256) depositedInEpoch;
        mapping(address => uint256) withdrawnInEpoch;
    }

    // Epochs array
    EpochInfo[] public epochs;

    // Claimed Epochs
    mapping(address => uint256) public lastClaimedEpochs;

    // ========== Events ==========
    event TradingOnUniSwapEnabled();
    event TradingOnUniSwapDisabled();
    event Snapshot(uint256 epoch, uint256 totalSupply, uint256 swapTaxCollected, uint256 tradingRevenue);
    event SwappedToEth(uint256 amount, uint256 ethAmount);
    event Claimed(address indexed user, uint256 amount);
    event LiquidityAdded(uint256 amountToken, uint256 amountETH);

    // ========== Modifiers ==========


    modifier botOrOwner() {
        require(msg.sender == revenueDistributionBot || msg.sender == owner(), "Not authorized");
        _;
    }

    // ========== ERC20 ==========

    constructor(address _teamWallet) ERC20("xperp", "") {
        require(_teamWallet != address(0), "Invalid team wallet");
        teamWallet = _teamWallet;
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(
            address(this),
            uniswapV2Router.WETH()
        );
        _approve(address(this), address(uniswapV2Router), type(uint256).max);
        _mint(msg.sender, oneMillion);
    }

    // ========== Configuration ==========

    function setRevenueDistributionBot(address _revenueDistributionBot) external onlyOwner {
        require(_revenueDistributionBot != address(0), "Invalid bot address");
        revenueDistributionBot = _revenueDistributionBot;
    }

    function updateTeamWallet(address _teamWallet) external onlyOwner {
        require(_teamWallet != address(0), "Invalid team wallet");
        teamWallet = _teamWallet;
    }

    function EnableTradingOnUniSwap() external onlyOwner {
        isTradingEnabled = true;
        emit TradingOnUniSwapEnabled();
    }

    function DisableTradingOnUniSwap() external onlyOwner {
        isTradingEnabled = false;
        emit TradingOnUniSwapDisabled();
    }

    // ========== ERC20 Overrides ==========

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        if (from == uniswapV2Pair && to != address(uniswapV2Router) && to != address(uniswapV2Pair)) {
            require(isTradingEnabled, "Trading is not enabled yet");
        }

        if (epochs.length > 0) {
            uint256 currentEpoch = epochs.length - 1;
            epochs[currentEpoch].depositedInEpoch[to] += amount;
            epochs[currentEpoch].withdrawnInEpoch[from] += amount;
        }

        uint256 amountAfterTax = amount;
        // calculate 5% swap tax
        if (from == uniswapV2Pair || to == uniswapV2Pair) {
            if (amount > onePercentOfSupply) {
                // owner() is an exception to fund the liquidity pair
                require(from == owner() || to == owner(), "Transfer amount exceeds 10000 tokens.");
            }
            // 5% total tax on xperp traded (1% to LP, 2% to revenue share, 2% to team and operating expenses).
            uint256 taxAmount = (amount * 50) / 1000;
            amountAfterTax -= taxAmount;
            swapTaxCollectedTotal += taxAmount;

            // 2% to team and operating expenses: 2/10 of the taxAmount
            uint256 teamShare = (amount * 20) / 1000;
            _transfer(from, teamWallet, teamShare);

            // the rest 3% goes to the contract balance for revenue sharing and liquidity injeciton
            _transfer(from, address(this), taxAmount - teamShare);
            // 1% to LP
            uint256 lp = (amount * 10) / 1000;
            liquidityPairTaxCollectedNotYetInjected += lp;
            // 2% revenue share (the rest to avoid rounding errors)
            revenueSharesCollectedSinceLastEpoch += taxAmount - teamShare - lp;
        }
        super._beforeTokenTransfer(from, to, amountAfterTax);
    }

    // ========== Revenue Sharing ==========

    // Function called by the revenue distribution bot to snapshot the state
    function snapshot() external payable botOrOwner nonReentrant {
        epochs.push();
        EpochInfo storage epoch = epochs[epochs.length - 1];
        epoch.epochTimestamp = block.timestamp;
        epoch.epochTotalSupply = totalSupply();
        epoch.epochRevenueFromSwapTaxCollectedXPERP = revenueSharesCollectedSinceLastEpoch;
        epoch.epochTradingRevenueETH = msg.value;
        tradingRevenueDistributedTotalETH += msg.value;
        uint256 ethAmount = swapXPERPToETH(revenueSharesCollectedSinceLastEpoch);
        revenueSharesCollectedSinceLastEpoch = 0;
        emit Snapshot(epochs.length - 1, totalSupply(), ethAmount, msg.value);
    }

    function claimAll() public {
        uint256 holderShare = 0;
        for (uint256 i = lastClaimedEpochs[msg.sender]; i < epochs.length; i++) {
            holderShare += getClaimable(i);
        }
        lastClaimedEpochs[msg.sender] = epochs.length - 1;
        payable(msg.sender).transfer(holderShare);
        emit Claimed(msg.sender, holderShare);
    }

    // ========== Liquidity Injection ==========

    function injectLiquidity(bool useContractEth) external payable botOrOwner {
        uint256 totalETH = msg.value;
        if (useContractEth) {
            totalETH -= address(this).balance;
        }
        uint256 totalToken = balanceOf(address(this));
        // Get reserves
        (uint reserveA, uint reserveB,) = IUniswapV2Pair(uniswapV2Pair).getReserves();

        // Calculate the exact amount of tokens and ETH needed based on the reserves
        uint256 amountTokenNeeded = (totalETH * reserveA) / reserveB;
        uint256 amountETHNeeded = (totalToken * reserveB) / reserveA;

        uint256 amountTokenToUse = amountTokenNeeded <= totalToken ? amountTokenNeeded : totalToken;
        uint256 amountETHToUse = amountETHNeeded <= totalETH ? amountETHNeeded : totalETH;

        // Add liquidity using all the received tokens and remaining ETH
        uniswapV2Router.addLiquidityETH{value: amountETHToUse}(
            address(this),
            amountTokenToUse,
            0,
            0,
            owner(),
            block.timestamp
        );
        emit LiquidityAdded(amountTokenToUse, amountETHToUse);
    }

    function swapXPERPToETH(uint256 _amount) internal returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        uint256 initialETHBalance = address(this).balance;
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            _amount,
            0,
            path,
            address(this),
            block.timestamp
        );
        uint256 finalETHBalance = address(this).balance;
        uint256 ETHReceived = finalETHBalance - initialETHBalance;
        emit SwappedToEth(_amount, ETHReceived);
        return ETHReceived;
    }

    // ========== Rescue Functions ==========

    function rescueETH(uint256 _weiAmount) external {
        payable(owner()).transfer(_weiAmount);
    }

    function rescueERC20(address _tokenAdd, uint256 _amount) external {
        IERC20(_tokenAdd).transfer(owner(), _amount);
    }

    // ========== View functions ==========

    function getBalanceForEpoch(uint256 _epoch) public view returns (uint256) {
        if (_epoch >= epochs.length) return 0;
        uint256 currentBalance = balanceOf(msg.sender);
        if (epochs.length > 1)
            for (uint256 e = epochs.length - 1; e >= _epoch; e--) {
                currentBalance -= epochs[e].depositedInEpoch[msg.sender];
                currentBalance += epochs[e].withdrawnInEpoch[msg.sender];
            }
        return currentBalance;
    }

    function getClaimable(uint256 _epoch) public view returns (uint256) {
        EpochInfo storage epoch = epochs[_epoch];
        if (_epoch <= lastClaimedEpochs[msg.sender])
            return 0;
        else
            return (getBalanceForEpoch(_epoch) * (epoch.epochRevenueFromSwapTaxCollectedXPERP + epoch.epochTradingRevenueETH)) / epoch.epochTotalSupply;
    }


}
