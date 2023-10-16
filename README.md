# xperp token

[![Compile & Test Pass](https://github.com/x-perp/xperp/actions/workflows/ci.yml/badge.svg)](https://github.com/x-perp/xperp/actions/workflows/ci.yml)

https://twitter.com/xperptech

https://xperp.tech

```shell
  xperp Token
   ____  _____ ____  ____
   __  _|  _ \| ____|  _ \|  _ \
   \ \/ / |_) |  _| | |_) | |_) |
    >  <|  __/| |___|  _ <|  __/
   /_/\_\_|   |_____|_| \_\_|
 Go long or short with leverage on @friendtech keys via Telegram
 ==============================================================
// - Tokenomics: 35% in LP, 10% to Team, 5% to Collateral Partners, 49% for future airdrops
// - Partnership: 1% has been sold to Handz of Gods.
// - Supply: 1M tokens
// - Tax: 3.5% tax on xperp traded (0.5% burned, 1.5% to revenue share, 1.5% to team and operating expenses).
// - Revenue Sharing: 30% of trading revenue goes to holders.
// - Eligibility: Holders of xperp tokens are entitled to revenue sharing.
```

Foundry-based Solidity smart contract.

## Deployed Contract

Mainnet:
[0x0D7e2Ba85fF3604D6ae5C56d1A5df334D9883725](https://etherscan.io/address/0x0D7e2Ba85fF3604D6ae5C56d1A5df334D9883725)

Goerli testnet:
[0x966E9031c06C09445625ced68a653582fbB18a73](https://goerli.etherscan.io/address/0x966E9031c06C09445625ced68a653582fbB18a73)

# Upgradable

The contract is a UUPS proxy implemented using an ERC1967Proxy.

By default, the upgrade functionality included in UUPSUpgradeable contains a security mechanism that will prevent any
upgrades to a non UUPS compliant implementation. This prevents upgrades to an implementation contract that wouldn’t
contain the necessary upgrade mechanism, as it would lock the upgradeability of the proxy forever. This security
mechanism can be bypassed by either of:

- Adding a flag mechanism in the implementation that will disable the upgrade function when triggered.
- Upgrading to an implementation that features an upgrade mechanism without the additional security check, and then
  upgrading again to another implementation without the upgrade mechanism.

The current implementation of this security mechanism uses EIP1822 to detect the storage slot used by the
implementation.

# Deploying

```sh
# this runs the deploy script on a local network, to run for real you'll need to broadcast.
# See forge scripting for more info.
forge script DeployUUPS
```

## Deployment procedure

1. Deploy the xperp token contract setting the team wallet.
2. Configure revsharebot address.
3. Run `init()` to initialize epochs and the LP.
4. Sending the dedicated owner 1M tokens which is a fixed totalsupply (before 5**!**).
5. Ownership transfer to the launcher.
6. The launcher puts xperp along with ETH to the liquidity pair.
6. Executing`EnableTradingOnUniswap` function.

## Addresses

- revsharebot: 0x87d71b3756A1e9c3117eEc8a79380926f66b80C3
- owner: 0x11eD88f6eE21F5808EB4B37D8292c57dc3Cc5e19
- team: 0x1746CF93F3368B4326423a82734A0ECC65D57bC5

## Liquidity Pair xperp/WETH

Mainnnet:
https://etherscan.io/address/0xE1e92c70617C86Ac10b3bc50F65b2fA752153d46

## What's Inside

- [Forge](https://github.com/foundry-rs/foundry/blob/master/forge): compile, test, fuzz, format, and deploy smart
  contracts
- [Forge Std](https://github.com/foundry-rs/forge-std): collection of helpful contracts and cheatcodes for testing
- [PRBTest](https://github.com/PaulRBerg/prb-test): modern collection of testing assertions and logging utilities
- [Prettier](https://github.com/prettier/prettier): code formatter for non-Solidity files
- [Solhint Community](https://github.com/solhint-community/solhint-community): linter for Solidity code

## Usage

```sh
$ pnpm install # install Solhint, Prettier, and other Node.js deps
$ forge test --fork-url  YOUR_MAINNET_NODE_URL -vvvv --gas-report
```

All tests should pass, and you should see a gas report at the end.
Test are executed against a mainnet fork to keep a real uniswap pair mirror, and to test the revenue sharing feature.

## More Information

https://linktr.ee/xperptech

## License

This project is licensed under MIT.
