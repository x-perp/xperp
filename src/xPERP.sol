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
// - Fair Launch: 97% of the token supply was added to liquidity at launch.
// - Partnership: 3% has been sold to Handz of Gods.
// - Supply: 1M tokens, fully circulating and non-dilutive.
// - Tax: 5% tax on xPERP traded (1% to LP, 2% to revenue share, 2% to team and operating expenses).
// - Revenue Sharing: 30% of trading revenue goes to holders. xPERP earns 2% of all trading volume.
// - Eligibility: Holders of $xPERP tokens are entitled to revenue sharing.

//import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
//import "@openzeppelin/contracts/access/Ownable.sol";

import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";


contract xPERP is ERC20, Ownable, ReentrancyGuard {

    // 1 Million is totalsuppy
    uint256 public constant oneMillion = 1000000 * 1 ether;

    // 1% of total supply, max tranfer amount possible
    uint256 public constant onePercentOfSupply = 10000 * 1 ether;

    // address of the revenue distribution bot
    address public revenueDistributionBot;

    // switched on post launch
    bool public isTradingEnabled = false;

    // swap tax collected, completely distributed among token holders
    uint256 public swapTaxCollectedTotal;
    // swap tax collected, completely distributed among token holders
    uint256 public swapTaxCollectedSinceLastEpoch;

    // Revenue sharing distribution info
    struct EpochInfo {
        // Snapshot time
        uint256 epochTimestamp;
        // Snapshot supply
        uint256 epochTotalSupply;
        // ETH collected for rewards for re-investors
        uint256 epochSwapTaxCollected;
        // Injected 30% revenue from trading
        uint256 epochTradingRevenue;
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

    // ========== Modifiers ==========

    modifier tradingEnabled() {
        require(isTradingEnabled, "Trading is disabled");
        _;
    }

    // ========== ERC20 ==========

    constructor() ERC20("xPERP", "xPERP") {

        _mint(msg.sender, oneMillion);

    }

    // ========== Configuration ==========


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
        super._beforeTokenTransfer(from, to, amount);
        uint256 currentEpoch = epochs.length - 1;
        epochs[currentEpoch].depositedInEpoch[to] += amount;
        epochs[currentEpoch].withdrawnInEpoch[from] += amount;
    }

    // ========== Revenue Sharing ==========

    // Function called by the revenue distribution bot to snapshot the state
    function snapshot() external payable onlyOwner nonReentrant {
        epochs.push();
        EpochInfo storage epoch = epochs[epochs.length - 1];
        epoch.epochTimestamp = block.timestamp;
        epoch.epochTotalSupply = totalSupply();
        epoch.epochSwapTaxCollected = swapTaxCollectedSinceLastEpoch;
        epoch.epochTradingRevenue = msg.value;
        emit Snapshot(epochs.length - 1, totalSupply(), swapTaxCollectedSinceLastEpoch, msg.value);
        swapTaxCollectedSinceLastEpoch = 0;
    }

    function claimAll() public {
        uint256 holderShare = 0;
        for (uint256 i = lastClaimedEpochs[msg.sender]; i < epochs.length; i++) {
            holderShare += getClaimable(i);
        }
        lastClaimedEpochs[msg.sender] = epochs.length - 1;
        payable(msg.sender).transfer(holderShare);
    }


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
            return (getBalanceForEpoch(_epoch) * epoch.epochSwapTaxCollected) / epoch.epochTotalSupply;
    }


}
