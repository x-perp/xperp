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
 - Fair Launch: 99% of the token supply was added to liquidity at launch.
 - Partnership: 1% has been sold to Handz of Gods.
 - Supply: 1M tokens, fully circulating and non-dilutive.
 - Tax: 5% tax on xperp traded (1% to LP, 2% to revenue share, 2% to team and operating expenses).
 - Revenue Sharing: 30% of trading revenue goes to holders. xperp earns 2% of all trading volume.
 - Eligibility: Holders of xperp tokens are entitled to revenue sharing.
```

Foundry-based Solidity smart contract.

## Deployed Contract

Mainnet:
[0xeec8bfa44e68bd9d4f2dd548346207bf1d8bbd0d](https://etherscan.io/address/0xeec8bfa44e68bd9d4f2dd548346207bf1d8bbd0d)

Goerli testnet:
[0x0ba4AA1005eA9376d1d3430Dd69dB5fF77055a74](https://goerli.etherscan.io/address/0x0ba4AA1005eA9376d1d3430Dd69dB5fF77055a74)

## Deployment procedure

1. Deploy the xperp token contract setting the team wallet.
2. Configure revsharebot address.
3. Run `init()` to initialize epochs and the LP.
4. Sending the dedicated owner 1M tokens which is a fixed totalsupply (before 5**!**).
5. Ownership transfer to the launcher.
6. The launcher puts xperp along with ETH to the liquidity pair.
6. Executing`EnableTradingOnUniswap` function.

Guillaume, [16 Sep 2023 15:52:55]:
yep

## Addresses

- revsharebot: 0x87d71b3756A1e9c3117eEc8a79380926f66b80C3
- owner: 0x01C993013d761E513e0A30F99058A4d11783694b
- team: 0x636595fA76b914462AC62A3fA2e0393F932BF9c4

## Liquidity Pair xperp/WETH

Mainnnet:
https://v2.info.uniswap.org/pair/0xf4b213439cd3e86d0939d3fc6c46fd7a4ea579e4

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

## License

This project is licensed under MIT.
