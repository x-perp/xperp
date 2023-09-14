// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract xPERP is ERC20, Ownable {
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
