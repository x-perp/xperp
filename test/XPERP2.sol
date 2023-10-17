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
// - Tokenomics: 35% in LP, 10% to Team, 5% to Collateral Partners, 49% for future airdrops
// - Partnership: 1% has been sold to Handz of Gods.
// - Supply: 1M tokens
// - Tax: 3.5% tax on xperp traded (0.5% to LP, 1.5% to revenue share, 1.5% to team and operating expenses).
// - Revenue Sharing: 30% of trading revenue goes to holders.
// - Eligibility: Holders of xperp tokens are entitled to revenue sharing.

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

import "@oz-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import "@oz-upgradeable/utils/PausableUpgradeable.sol";
import "@oz-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@oz-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@oz-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "forge-std/console2.sol";

contract UUPSProxy is ERC1967Proxy {
    constructor(address _implementation, bytes memory _data)
    ERC1967Proxy(_implementation, _data)
    {}
}

contract XPERP2 is ERC20Upgradeable, PausableUpgradeable, AccessControlEnumerableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {

    // 1 Million is totalsuppy
    uint256 public constant oneMillion = 1_000_000 * 1 ether;
    // precision mitigation value, 100x100
    uint256 public constant hundredPercent = 10_000;
    IUniswapV2Router02 public constant uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    // 1% of total supply, max tranfer amount possible
    uint256 public walletBalanceLimit;
    uint256 public sellLimit;

    // Taxation
    uint256 public totalTax;
    uint256 public teamWalletTax;
    bool public isTaxActive;

    // Claiming vs Airdropping
    bool public isAirDropActive;

    // address of the uniswap pair
    address public uniswapV2Pair;

    // team wallet
    address payable public teamWallet;

    // switched on post launch
    bool public isTradingEnabled;

    // total swap tax collected, completely distributed among token holders, for analytical purposes only
    uint256 public swapTaxCollectedTotalXPERP;

    // revenue sharing tax collected for the distribution in the current snapshot (total tax less liquidity shares)
    uint256 public revShareAndTeamCurrentEpochXPERP;

    // revenue sharing tax collected, completely distributed among token holders, for analytical purposes only
    uint256 public tradingRevenueDistributedTotalETH;

    // Revenue sharing distribution info, 1 is the first epoch.
    struct EpochInfo {
        // Snapshot time
        uint256 epochTimestamp;
        // Snapshot supply
        uint256 epochCirculatingSupply;
        // ETH collected for rewards for re-investors
        uint256 epochRevenueFromSwapTaxCollectedXPERP;
        // Same in ETH
        uint256 epochSwapRevenueETH;
        // Injected 30% revenue from trading
        uint256 epochTradingRevenueETH;
        // Used to calculate holder balances at the time of snapshot
        mapping(address => uint256) depositedInEpoch;
        mapping(address => uint256) withdrawnInEpoch;
    }

    // Epochs array, each epoch contains the snapshot info,
    // 1 is the first epoch,
    // the current value (length-1) is the epoch currently in progress - not snapshotted yet
    // the previous value (length-2) is the last snapshotted epoch
    EpochInfo[] public epochs;

    // Claimed Epochs
    mapping(address => uint256) public lastClaimedEpochs;

    // ========== Events ==========
    event TradingOnUniSwapEnabled();
    event TradingOnUniSwapDisabled();
    event Snapshot(uint256 epoch, uint256 circulatingSupply, uint256 swapTaxCollected, uint256 tradingRevenueCollected);
    event SwappedToEth(uint256 amount, uint256 ethAmount);
    event SwappedToXperp(uint256 amount, uint256 ethAmount);
    event Claimed(address indexed user, uint256 amount);
    event ReceivedEther(address indexed from, uint256 amount);
    event TaxChanged(uint256 tax, uint256 teamWalletTax);
    event TaxActiveChanged(bool isActive);

    // =========== Constants =======
    /// @notice Admin role for upgrading, fees, and paused state
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    /// @notice Snapshot role for taking snapshots
    bytes32 public constant SNAPSHOT_ROLE = keccak256("SNAPSHOT_ROLE");
    /// @notice Rescue role for rescuing tokens and Eth from the contract
    bytes32 public constant RESCUE_ROLE = keccak256("RESCUE_ROLE");
    /// @notice WhiteList role for listing vesting and other addresses that should be excluded from circulaing supply to not lower the revenue share for participants
    bytes32 public constant EXCLUDED_ROLE = keccak256("EXCLUDED_ROLE");

    // =========== Errors ==========
    /// @dev Zero address
    error ZeroAddress();

    // ========== Proxy ==========

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address payable _teamWallet) public initializer {
        if (_teamWallet == address(0)) revert ZeroAddress();
        __ERC20_init("xperp", "xperp");
        __AccessControlEnumerable_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        teamWallet = _teamWallet;
        totalTax = 350;
        teamWalletTax = 150;
        isTaxActive = true;
        isTradingEnabled = false;
        walletBalanceLimit = 10_000 * 1 ether;
        sellLimit = 10_000 * 1 ether;
        isAirDropActive = false;

        // Grant admin role to owner
        _setRoleAdmin(DEFAULT_ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(EXCLUDED_ROLE, ADMIN_ROLE);
        _setRoleAdmin(SNAPSHOT_ROLE, SNAPSHOT_ROLE);
        _setRoleAdmin(RESCUE_ROLE, ADMIN_ROLE);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(EXCLUDED_ROLE, msg.sender);
        _grantRole(SNAPSHOT_ROLE, msg.sender);
        _grantRole(RESCUE_ROLE, msg.sender);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        epochs.push();
        epochs.push();
        _mint(msg.sender, oneMillion);
    }

    function initPair() public onlyRole(ADMIN_ROLE) {
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(
            address(this),
            uniswapV2Router.WETH()
        );
        // approving uniswap router to spend xperp on behalf of the contract
        _approve(address(this), address(uniswapV2Router), type(uint256).max);
    }

    function pause() public onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    function _authorizeUpgrade(address newImplementation)
    internal
    override
    onlyRole(DEFAULT_ADMIN_ROLE)
    {}

    // ========== Configuration ==========

    function setTax(uint256 _tax, uint256 _teamWalletTax) external onlyRole(ADMIN_ROLE) {
        require(_tax <= 10000 && _teamWalletTax >= 0 && _teamWalletTax <= 10000, "Invalid tax");
        totalTax = _tax;
        teamWalletTax = _teamWalletTax;
        emit TaxChanged(_tax, _teamWalletTax);
    }

    function setTaxActive(bool _isTaxActive) external onlyRole(ADMIN_ROLE) {
        isTaxActive = _isTaxActive;
        emit TaxActiveChanged(_isTaxActive);
    }

    function setWalletBalanceLimit(uint256 _walletBalanceLimit) external onlyRole(ADMIN_ROLE) {
        require(_walletBalanceLimit >= 0 && _walletBalanceLimit <= oneMillion, "Invalid wallet balance limit");
        walletBalanceLimit = _walletBalanceLimit;
    }

    function setSellLimit(uint256 _sellLimit) external onlyRole(ADMIN_ROLE) {
        require(_sellLimit >= 0 && _sellLimit <= oneMillion, "Invalid sell balance limit");
        sellLimit = _sellLimit;
    }

    function updateTeamWallet(address payable _teamWallet) external onlyRole(ADMIN_ROLE) {
        require(_teamWallet != address(0), "Invalid team wallet");
        teamWallet = _teamWallet;
    }

    function EnableTradingOnUniSwap() external onlyRole(ADMIN_ROLE) {
        isTradingEnabled = true;
        emit TradingOnUniSwapEnabled();
    }

    function DisableTradingOnUniSwap() external onlyRole(ADMIN_ROLE) {
        isTradingEnabled = false;
        emit TradingOnUniSwapDisabled();
    }

    function toggleAirDrop() external onlyRole(SNAPSHOT_ROLE) {
        isAirDropActive = !isAirDropActive;
    }

    // ========== ERC20 Overrides ==========
    /// @dev overriden ERC20 transfer to tax on transfers to and from the uniswap pair, xperp is swapped to ETH and prepared for snapshot distribution
    function _update(address from, address to, uint256 amount) internal override {
        console2.log("====_update");
        console2.log("uniswapV2Pair: %s", uniswapV2Pair);
        bool isTradingTransfer =
            (from == uniswapV2Pair || to == uniswapV2Pair) &&
            msg.sender != address(uniswapV2Router) &&
            from != address(this) && to != address(this) &&
            !hasRole(EXCLUDED_ROLE, from) && !hasRole(EXCLUDED_ROLE, to);

        require(isTradingEnabled || !isTradingTransfer, "Trading is not enabled yet");

        // if trading is enabled, only allow transfers to and from the Uniswap pair
        uint256 amountAfterTax = amount;
        // calculate 5% swap tax
        // owner() is an exception to fund the liquidity pair and revenueDistributionBot as well to fund the revenue distribution to holders
        console2.log("isTradingTransfer: %s", isTradingTransfer);
        if (isTradingTransfer) {
            require(isTradingEnabled, "Trading is not enabled yet");
            // Buying tokens
            if (from == uniswapV2Pair && walletBalanceLimit > 0) {
                require(balanceOf(to) + amount <= walletBalanceLimit, "Holding amount after buying exceeds maximum allowed tokens.");
            }
            // Selling tokens
            if (to == uniswapV2Pair && sellLimit > 0) {
                require(amount <= sellLimit, "Selling amount exceeds maximum allowed tokens.");
            }
            // 5% total tax on xperp traded (1% to LP, 2% to revenue share, 2% to team and operating expenses).
            console2.log("isTaxActive: %s", isTaxActive);
            if (isTaxActive) {
                uint256 taxAmountXPERP = (amount * totalTax) / hundredPercent;
                _transfer(from, address(this), taxAmountXPERP);
                amountAfterTax -= taxAmountXPERP;
                swapTaxCollectedTotalXPERP += taxAmountXPERP;
                revShareAndTeamCurrentEpochXPERP += taxAmountXPERP;
            }
        }
        uint256 currentEpoch = epochs.length - 1;
        epochs[currentEpoch].depositedInEpoch[to] += amountAfterTax;
        epochs[currentEpoch].withdrawnInEpoch[from] += amount;
        console2.log("hasRole(EXCLUDED_ROLE, from)", hasRole(EXCLUDED_ROLE, from));
        console2.log("from: %s", from);
        console2.log("to: %s", to);
        console2.log("amount: %s", amount);
        console2.log("amountAfterTax: %s", amountAfterTax);
        super._update(from, to, amountAfterTax);
    }

    // ========== Revenue Sharing ==========

    // Function called by the revenue distribution bot to snapshot the state
    function snapshot() external payable onlyRole(SNAPSHOT_ROLE) nonReentrant {
        EpochInfo storage epoch = epochs[epochs.length - 1];
        epoch.epochTimestamp = block.timestamp;
        uint256 _circulatingSupply = circulatingSupply();
        uint256 xperpToSwap = revShareAndTeamCurrentEpochXPERP;

        console2.log("circulatingSupply: %s", _circulatingSupply);

        require(xperpToSwap > 0 || msg.value > 0, "No tax collected yet and no ETH sent");
        require(balanceOf(address(this)) >= xperpToSwap, "Balance less than required");

        console2.log("balanceOf(address(this): %s", balanceOf(address(this)));
        uint256 revAndTeamETH = xperpToSwap > 0 ? swapXPERPToETH(xperpToSwap) : 0;
        console2.log("totalTax: %s", totalTax);
        // 1.5% to team and operating expenses distributed immediately
        uint256 teamWalletTaxAmountETH = (revAndTeamETH * teamWalletTax) / totalTax;
        uint256 epochSwapRevenueETH = revAndTeamETH - teamWalletTaxAmountETH;
        teamWallet.transfer(teamWalletTaxAmountETH);
        // the rest in ETH is kept on the contract for revenue share distribution
        epoch.epochCirculatingSupply = _circulatingSupply;
        epoch.epochTradingRevenueETH = msg.value;
        epoch.epochRevenueFromSwapTaxCollectedXPERP = xperpToSwap;
        epoch.epochSwapRevenueETH = epochSwapRevenueETH;
        emit Snapshot(epochs.length, _circulatingSupply, epochSwapRevenueETH, msg.value);

        epochs.push();
        revShareAndTeamCurrentEpochXPERP = 0;
    }

    function claimAll() public nonReentrant {
        require(!isAirDropActive, "Airdrop is active instead of claiming");
        uint256 holderShare = getClaimableOf(msg.sender);
        require(holderShare > 0, "Nothing to claim");
        lastClaimedEpochs[msg.sender] = epochs.length - 2;
        require(address(this).balance >= holderShare, "Insufficient contract balance");
        payable(msg.sender).transfer(holderShare);
        emit Claimed(msg.sender, holderShare);
    }

    // ========== Internal Functions ==========

    function swapXPERPToETH(uint256 _amount) internal returns (uint256) {
        if (_amount == 0) return 0;
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

    function rescueETH(uint256 _weiAmount) external onlyRole(RESCUE_ROLE) {
        payable(msg.sender).transfer(_weiAmount);
    }

    function rescueERC20(address _tokenAdd, uint256 _amount) external onlyRole(RESCUE_ROLE) {
        IERC20(_tokenAdd).transfer(msg.sender, _amount);
    }

    // ========== Fallbacks ==========


    receive() external payable {
        emit ReceivedEther(msg.sender, msg.value);
    }
    // ========== View functions ==========

    function getBalanceForEpochOf(address _user, uint256 _epoch) public view returns (uint256) {
        console2.log("===getBalanceForEpochOf: %s", _epoch);
        if (_epoch >= epochs.length) return 0;
        uint256 currentBalance = balanceOf(_user);
        console2.log("currentBalance: %s", currentBalance);
        if (epochs.length >= 1) {
            uint256 e = epochs.length - 1;
            while (true) {
                console2.log("e: %s", e);
                console2.log("epochs[e].withdrawnInEpoch: %s", epochs[e].withdrawnInEpoch[_user]);
                console2.log("epochs[e].depositedInEpoch: %s", epochs[e].depositedInEpoch[_user]);
                currentBalance += epochs[e].withdrawnInEpoch[_user];
                currentBalance -= epochs[e].depositedInEpoch[_user];
                console2.log("currentBalance: %s", currentBalance);
                if (e == _epoch + 1 || e == 0) {
                    break;
                }
                e--;
            }
        }
        console2.log(">>> currentBalance: %s", currentBalance);
        return currentBalance;
    }

    function getBalanceForEpoch(uint256 _epoch) public view returns (uint256) {
        return getBalanceForEpochOf(msg.sender, _epoch);
    }


    function getClaimableOf(address _user) public view returns (uint256)  {
        require(epochs.length > 1, "No epochs yet");
        uint256 holderShare = 0;
        for (uint256 i = lastClaimedEpochs[_user] + 1; i < epochs.length - 1; i++)
            holderShare += getClaimableForEpochOf(_user, i);
        return holderShare;
    }

    function getClaimableForEpochOf(address _user, uint256 _epoch) public view returns (uint256) {
        console2.log("===getClaimableForEpochOf: %s", _epoch);
        if (epochs.length < 1 || epochs.length <= _epoch) return 0;
        EpochInfo storage epoch = epochs[_epoch];
        if (_epoch <= lastClaimedEpochs[_user] || epoch.epochCirculatingSupply == 0)
            return 0;
        else
            return (getBalanceForEpochOf(_user, _epoch) * (epoch.epochSwapRevenueETH + epoch.epochTradingRevenueETH)) / epoch.epochCirculatingSupply;
    }

    function circulatingSupply() public view returns (uint256) {
        uint256 count = getRoleMemberCount(EXCLUDED_ROLE);
        uint256 excludedBalance = 0;
        for (uint256 i = 0; i < count; i++) {
            excludedBalance += balanceOf(getRoleMember(EXCLUDED_ROLE, i));
        }
        excludedBalance += balanceOf(address(this));
        excludedBalance += balanceOf(uniswapV2Pair);
        return totalSupply() - excludedBalance;
    }

    function getEpochsPassed() public view returns (uint256) {
        return epochs.length;
    }

    function getDepositedInEpoch(uint256 epochIndex, address userAddress) public view returns (uint256) {
        require(epochIndex < epochs.length, "Invalid epoch index");
        return epochs[epochIndex].depositedInEpoch[userAddress];
    }

    function getWithdrawnInEpoch(uint256 epochIndex, address userAddress) public view returns (uint256) {
        require(epochIndex < epochs.length, "Invalid epoch index");
        return epochs[epochIndex].withdrawnInEpoch[userAddress];
    }

    function getTestPostUpgradeFunction() public pure returns (string memory) {
        return "test";
    }
}
