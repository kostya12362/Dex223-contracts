# Dex223 contracts

## Ethereum mainnet deployment

| Name                | Address                                                                                                                    |
| ------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| WETH9               | [0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2](https://etherscan.io/address/0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2#code) |
| TOKEN_CONVERTER     | [0xe7E969012557f25bECddB717A3aa2f4789ba9f9a](https://etherscan.io/address/0xe7E969012557f25bECddB717A3aa2f4789ba9f9a#code) |
| POOL_LIBRARY        | [0xfA5930D2Ef1b6231e220aeDda88E28C4E8F0F3a0](https://etherscan.io/address/0xfA5930D2Ef1b6231e220aeDda88E28C4E8F0F3a0#code) |
| FACTORY             | [0xc0c5511f23a268f041Ad10466a17b719942a8F1f](https://etherscan.io/address/0xc0c5511f23a268f041Ad10466a17b719942a8F1f#code) |
| SWAP_ROUTER         | [0x74BD76Ab5B80A0300b3c989CdaAC34D2984cEBde](https://etherscan.io/address/0x74BD76Ab5B80A0300b3c989CdaAC34D2984cEBde#code) |
| POSITION_DESCRIPTOR | [0xb67aC8E7E4FDad7C63281952d2e3A5a0912f4ca0](https://etherscan.io/address/0xb67aC8E7E4FDad7C63281952d2e3A5a0912f4ca0#code) |
| POSITION_MANAGER    | [0x9cF5612332b49519Aa398F0DE05d0a69D84124F1](https://etherscan.io/address/0x9cF5612332b49519Aa398F0DE05d0a69D84124F1#code) |
| POOL_INIT_CODE_HASH | 0x9966400177a96c358783e5915045e9e9f19d514dadb45a9e599b5f6295cbfd64                                                         |
| POOL_USDC_WETH      | [0x29dC799d9d491CB5D1Cb7f3e385aEDEa0D39f0dD](https://etherscan.io/address/0x29dC799d9d491CB5D1Cb7f3e385aEDEa0D39f0dD#code) |
| CORE_AUTOLISTING    | [0x13ddc6460c705d29d37b18a906c7fe69fa9e711d](https://etherscan.io/address/0x13ddc6460c705d29d37b18a906c7fe69fa9e711d)      |
| FREE_AUTOLISTING    | [0xa7089d8cbcc47543388a346dd6ebf0b05106a477](https://etherscan.io/address/0xa7089d8cbcc47543388a346dd6ebf0b05106a477)      |
| AUTOLISTINGS_REGISTRY | [0x105F43A70aFCEd0493545D04C1d5687DF4b3f48f](https://etherscan.io/address/0x105F43A70aFCEd0493545D04C1d5687DF4b3f48f)    |

## Sepolia testnet deployment

| Name                | Address                                                                                                                       |
|---------------------|-------------------------------------------------------------------------------------------------------------------------------|
| WETH9               | [0xb16F35c0Ae2912430DAc15764477E179D9B9EbEa](https://sepolia.etherscan.io/address/0xb16F35c0Ae2912430DAc15764477E179D9B9EbEa#code) |
| TOKEN_CONVERTER     | [0xe831FDB60Dc18c264f1B45cadAFD5f2f2993EE83](https://sepolia.etherscan.io/address/0xe831FDB60Dc18c264f1B45cadAFD5f2f2993EE83#code) |
| POOL_LIBRARY        | [0x5Aac8Cc2A2EDf140b9c729dAb31496B9F2a4b511](https://sepolia.etherscan.io/address/0x5Aac8Cc2A2EDf140b9c729dAb31496B9F2a4b511#code) |
| FACTORY             | [0x6a17Ec0AC537e6e30c8425DC4C253F7D5926E66B](https://sepolia.etherscan.io/address/0x6a17Ec0AC537e6e30c8425DC4C253F7D5926E66B#code) |
| SWAP_ROUTER         | [0x6d1a12d5921692f240CcDD9d4b7cAc2cCeD1BEd2](https://sepolia.etherscan.io/address/0x6d1a12d5921692f240CcDD9d4b7cAc2cCeD1BEd2#code) |
| POSITION_DESCRIPTOR | [0x9F970c7107140B546AfF595f5Ddd093d5460f131](https://sepolia.etherscan.io/address/0x9F970c7107140B546AfF595f5Ddd093d5460f131#code) |
| POSITION_MANAGER    | [0x091249267d085055fa2f281fa3f6c0cf4bf70bae](https://sepolia.etherscan.io/address/0x091249267d085055fa2f281fa3f6c0cf4bf70bae#code) |
| POOL_INIT_CODE_HASH | 0x9966400177a96c358783e5915045e9e9f19d514dadb45a9e599b5f6295cbfd64                                                        |
| POOL_USDC_WETH      | [0x02e8dc65c81d4064d89ada57f3c6880aa4f83c66](https://sepolia.etherscan.io/address/0x02e8dc65c81d4064d89ada57f3c6880aa4f83c66#code) |


## Helpers

1. Run local virtual node:

```bash
yarn run hardhat:node
```

2. Compile contracts:

```bash
yarn run hardhat:compile
```

or use `force` to re-compile all contratcs

```bash
yarn run hardhat:compile:force
```

3. Prepare JSON files for contract verification.
   Search for output files in `./artifacts/solidity-json` folder

```bash
yarn run hardhat:verify
```

## Contracts tests

1. Run ALL tests:

```bash
yarn run hardhat:test
```

2. Update values for GAS tests:

```bash
yarn run hardhat:test:update
```

3. Run only SwapRouter tests:

```bash
yarn run hardhat:test:router
```

4. Run only SwapRouter GAS tests:

```bash
yarn run hardhat:test:routergas
```

5. Run only Factory tests:

```bash
yarn run hardhat:test:factory
```

6. Run only Pool tests:

```bash
yarn run hardhat:test:pool
```

7. Run only Pool Swaps tests:

```bash
yarn run hardhat:test:poolswaps
```

8. Run only NonfungiblePositionManager tests:

```bash
yarn run hardhat:test:nfpm
```

9. Run only AutoListing tests:

```bash
yarn run hardhat:test:autolist
```
