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
import "@openzeppelin/contracts/security/Pausable.sol";
import {console2} from "forge-std/console2.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/TokenTimelock.sol";

contract xPERP is ERC20, Ownable, Pausable, ReentrancyGuard {

    // 1 Million is totalsuppy
    uint256 public constant oneMillion = 1_000_000 * 1 ether;

    // 1% of total supply, max tranfer amount possible
    uint256 public constant onePercentOfSupply = 10_000 * 1 ether;

    // Taxation
    uint256 public totalTax = 500;
    uint256 public teamWalletTax = 200;
    bool public isTaxActive = true;

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
    uint256 public swapTaxCollectedTotalXPERP;

    // revenue sharing tax collected, completely distributed among token holders
    uint256 public revenueSharesCollectedSinceLastEpochXPERP;

    // revenue sharing tax collected, completely distributed among token holders
    uint256 public tradingRevenueDistributedTotalETH;

    // revenue sharing tax collected, completely distributed among token holders
    uint256 public liquidityPairTaxCollectedNotYetInjectedXPERP;

    // 2% of the tax goes to the team

    // Revenue sharing distribution info
    struct EpochInfo {
        // Snapshot time
        uint256 epochTimestamp;
        // Snapshot supply
        uint256 epochTotalSupply;
        // ETH collected for rewards for re-investors
        uint256 epochRevenueFromSwapTaxCollectedXPERP;
        // Same swapped to ETH
        uint256 epochRevenueFromSwapTaxCollectedETH;
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
    event SwappedToXperp(uint256 amount, uint256 ethAmount);
    event Claimed(address indexed user, uint256 amount);
    event LiquidityAdded(uint256 amountToken, uint256 amountETH, uint256 liquidity);
    event ReceivedEther(address indexed from, uint256 amount);

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

    function setTax(uint256 _tax, uint256 _teamWalletTax) external onlyOwner {
        require(_tax >= 0 && _tax <= 1000 && _teamWalletTax >= 0 && _teamWalletTax <= 1000, "Invalid tax");
        totalTax = _tax;
        teamWalletTax = _teamWalletTax;
    }

    function setTaxActive(bool _isTaxActive) external onlyOwner {
        isTaxActive = _isTaxActive;
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

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ========== ERC20 Overrides ==========

    function transfer(address to, uint256 amount) public override returns (bool) {
        address from = msg.sender;
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
        if (isTaxActive && (from == uniswapV2Pair || to == uniswapV2Pair) && msg.sender != address(uniswapV2Router)) {
            if (amount > onePercentOfSupply) {
                // owner() is an exception to fund the liquidity pair
                require(from == owner() || to == owner(), "Transfer amount exceeds 10000 tokens.");
            }
            // 5% total tax on xperp traded (1% to LP, 2% to revenue share, 2% to team and operating expenses).
            uint256 taxAmount = (amount * totalTax) / 10000;
            amountAfterTax -= taxAmount;
            swapTaxCollectedTotalXPERP += taxAmount;

            // 2% to team and operating expenses
            uint256 teamShare = (amount * teamWalletTax) / 10000;
            _transfer(from, teamWallet, teamShare);

            // the rest 3% goes to the contract balance for revenue sharing and liquidity injeciton
            _transfer(from, address(this), taxAmount - teamShare);
            // 1% to LP
            uint256 lp = (amount * totalTax) / 50000;
            liquidityPairTaxCollectedNotYetInjectedXPERP += lp;
            // 2% revenue share (the rest to avoid rounding errors)
            revenueSharesCollectedSinceLastEpochXPERP += taxAmount - teamShare - lp;
        }
        return super.transfer(to, amountAfterTax);
    }

    // ========== Revenue Sharing ==========

    // Function called by the revenue distribution bot to snapshot the state
    function snapshot() external payable botOrOwner nonReentrant {
        epochs.push();
        EpochInfo storage epoch = epochs[epochs.length - 1];
        epoch.epochTimestamp = block.timestamp;
        epoch.epochTotalSupply = totalSupply();
        epoch.epochRevenueFromSwapTaxCollectedXPERP = revenueSharesCollectedSinceLastEpochXPERP;
        epoch.epochTradingRevenueETH = msg.value;
        tradingRevenueDistributedTotalETH += msg.value;
        uint256 ethAmount = revenueSharesCollectedSinceLastEpochXPERP > 0 ? swapXPERPToETH(revenueSharesCollectedSinceLastEpochXPERP) : 0;
        revenueSharesCollectedSinceLastEpochXPERP = 0;
        epoch.epochRevenueFromSwapTaxCollectedETH = ethAmount;
        emit Snapshot(epochs.length, totalSupply(), ethAmount, msg.value);
    }

    function claimAll() public nonReentrant {
        require(epochs.length > 0, "No epochs yet");
        uint256 holderShare = 0;
        console2.log("lastClaimedEpochs[msg.sender]", lastClaimedEpochs[msg.sender]);
        console2.log("epochs.length", epochs.length);
        for (uint256 i = lastClaimedEpochs[msg.sender]; i < epochs.length; i++) {
            holderShare += getClaimable(i);
            console2.log("epoch: ", i);
            console2.log("total holderShare", holderShare);
        }
        console2.log("holderShare", holderShare);
        console2.log("balance(this)", address(this).balance);
        lastClaimedEpochs[msg.sender] = epochs.length - 1;
        require(address(this).balance >= holderShare, "Insufficient contract balance to transfer share");
        payable(msg.sender).transfer(holderShare);
        console2.log("msg.sender", msg.sender);
        emit Claimed(msg.sender, holderShare);
    }

    // ========== Liquidity Injection ==========
    /// @dev this function uses 1% LP tax token collected from swaps, swaps tokens for ETH and adds this to liquidity pair.
    /// @dev There's also an option to transfer additional tokens and ETH to the contract, which will be used for liquidity injection
    /// @dev This function can be called by anyone
    function injectLiquidity(uint256 tokenAmount) external payable {
        require(balanceOf(address(this)) >= liquidityPairTaxCollectedNotYetInjectedXPERP, "Not enough tokens");
        transfer(address(this), tokenAmount);

        // Tokens eligible for injection
        uint256 amountTokenToUse = (liquidityPairTaxCollectedNotYetInjectedXPERP + tokenAmount) / 2;

        //Swap TokenForEth
        uint256 ethAmount = swapXPERPToETH(amountTokenToUse);

        // Add liquidity using all the received tokens and remaining ETH
        (uint amountToken, uint amountETH, uint liquidity) = uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            amountTokenToUse,
            0,
            0,
            address(this),
            block.timestamp
        );
        liquidityPairTaxCollectedNotYetInjectedXPERP = 0;
        emit LiquidityAdded(amountToken, amountETH, liquidity);
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

    // ========== Fallbacks ==========


    receive() external payable {
        emit ReceivedEther(msg.sender, msg.value);
    }
    // ========== View functions ==========

    function getBalanceForEpoch(uint256 _epoch) public view returns (uint256) {
        console2.log("=== getBalanceForEpoch _epoch", _epoch);
        if (_epoch >= epochs.length) return 0;
        uint256 currentBalance = balanceOf(msg.sender);
        console2.log("currentBalance", currentBalance);
        if (epochs.length > 1) {
            uint256 e = epochs.length - 1;
            while (true) {
                console2.log("epoch", e);
                console2.log("depositedInEpoch", epochs[e].depositedInEpoch[msg.sender]);
                console2.log("withdrawnInEpoch", epochs[e].withdrawnInEpoch[msg.sender]);
                currentBalance += epochs[e].withdrawnInEpoch[msg.sender];
                currentBalance -= epochs[e].depositedInEpoch[msg.sender];
                console2.log("currentBalance", currentBalance);
                if (e == _epoch || e == 0) {
                    break;
                }
                e--;
            }
        }
        console2.log("returning currentBalance", currentBalance);
        return currentBalance;
    }

    function getClaimable(uint256 _epoch) public view returns (uint256) {
        console2.log("=============getClaimable _epoch", _epoch);
        if (epochs.length == 0 || epochs.length <= _epoch) return 0;
        EpochInfo storage epoch = epochs[_epoch];
        console2.log("epoch.epochRevenueFromSwapTaxCollectedETH", epoch.epochRevenueFromSwapTaxCollectedETH);
        console2.log("epoch.epochTradingRevenueETH", epoch.epochTradingRevenueETH);
        console2.log("epoch.epochTotalSupply", epoch.epochTotalSupply);
        console2.log("epoch.getBalanceForEpoch(_epoch) ", getBalanceForEpoch(_epoch));
//        console2.log(" getBalanceForEpoch(_epoch) * (epoch.epochRevenueFromSwapTaxCollectedETH + epoch.epochTradingRevenueETH)", getBalanceForEpoch(_epoch) * (epoch.epochRevenueFromSwapTaxCollectedETH + epoch.epochTradingRevenueETH);
        if (_epoch <= lastClaimedEpochs[msg.sender])
            return 0;
        else
            return getBalanceForEpoch(_epoch) * (epoch.epochRevenueFromSwapTaxCollectedETH + epoch.epochTradingRevenueETH) / epoch.epochTotalSupply;
    }


}
