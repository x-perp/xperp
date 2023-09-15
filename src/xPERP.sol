// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

// xPERP Token Information
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


contract xPERP is ERC20, Ownable {

    // 1 Million is totalsuppy
    uint256 totalSupply = 1000000 * 1 ether;

    // 1% of total supply, max tranfer amount possible
    uint256 public constant maxTxAmount = 10000 * 1 ether;

    // switched on post launch
    bool public isTradingEnabled = false;



    event TradingEnabled();
    event TradingDisabled();

    constructor() ERC20("xPERP Token", "xPERP") {
        _mint(msg.sender, 1000000 * 1e18);
    }

    modifier tradingEnabled() {
        require(isTradingEnabled, "Trading is disabled");
        _;
    }

    function et() external onlyOwner {
        isTradingEnabled = true;
        emit TradingEnabled();
    }

    function dt() external onlyOwner {
        isTradingEnabled = false;
        emit TradingDisabled();
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override tradingEnabled {
        super._beforeTokenTransfer(from, to, amount);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
