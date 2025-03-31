# Dex223 contracts

## Ethereum mainnet deployment

1. PoolLibrary: 0x55d36836209e91952e33a058c7eaf1ce3ece0ee0
2. Converter: 0xe7E969012557f25bECddB717A3aa2f4789ba9f9a
3. Factory: 0xa146a20b4e9551cc827afe183130061af92db12a
4. hashPoolCode: 0x506a6a31eff8c1887c6ed0374682d0a0e806f5bd8c4b4d5eb96dd3cdc9c99ac3
5. Autolisting Registry (immutable): 0x105f43a70afced0493545d04c1d5687df4b3f48f
7. Autolisting (Dex223 free): 0x39491101f7d46e9f0c3217d2eb91c016f761ad59
8. Autolistign (Dex223 $50 USDT per listing): 0x6a5ff6c7b1ea8e9b9e40da3b162468b61e40584f
9. Non-fungible position manager: 0x1a817a1b78506e2d45f344a4d327614559859993
10. Router: 0xc87c815c03b6cd45880cbd51a90d0a56ecfba9da
11. Quoter223: 0x29c3b2cb7a6249f282264bbc693707a41e773e1e

## Sepolia testnet deployment

1. PoolLibrary:  
https://sepolia.etherscan.io/address/0xDd90b13bcb92950CA9b6b3e0407d439533eA0df2

2. Converter:
https://sepolia.etherscan.io/address/0xe831FDB60Dc18c264f1B45cadAFD5f2f2993EE83

3. Factory: 
https://sepolia.etherscan.io/address/0x9f3118af733Ea3Fe4f9Ed71033F25B6bcF7F49e9

4. PoolAddressHelper:  
https://sepolia.etherscan.io/address/0xcB53086f8D8532CD2253A02052314D07ec8D5B76

5. hashPoolCode:  
0x05d446756e26e69fa77a84a7c38e1e2240da087cdb01dbb71ffd721103c6ee23

6. Autolisting Registry (immutable): 0x4fd0ff10833d6c90f0995ddefd10a1ef03b24790

7. Autolisting (Dex223 free): https://sepolia.etherscan.io/address/0x7333d5141f645b354e1517892a725db88a840436

8. Autolistign (Dex223 payable): https://sepolia.etherscan.io/address/0x87af0fadc21420d0a572b4709b81cf2e368552d7

9. Autolisting (Custom): https://sepolia.etherscan.io/address/0xb83b6a34802bb4149834110c28e3e0e270d804a8

10. NFPM: 
https://sepolia.etherscan.io/address/0x1937f00296267c2bA4Effa1122D944F33de46891

11. Router:  
https://sepolia.etherscan.io/address/0x22cD7407eB4cE475AeC9769fDF229b1046C891C0

12. Quoter:  
https://sepolia.etherscan.io/address/0x4F55aF4162FBA4505D459d3B3Fd1926391F18349


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
