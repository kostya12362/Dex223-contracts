import hre from "hardhat";
import { ethers } from "hardhat";
import path from "path";
import { loadConfig } from "../utils/config";

interface ExchangeConfig {
  POOL_LIBRARY: string;
  TOKEN_CONVERTER: string;
  FACTORY: string;
  SWAP_ROUTER: string;
  NFT_DESCRIPTOR: string;
  POSITION_DESCRIPTOR: string;
  POSITION_MANAGER: string;
  WETH9: string;
  NATIVE_LABEL?: string;
}

async function main() {
  const configPath = path.join(__dirname, "config.json");
  const cfg = loadConfig(configPath) as ExchangeConfig;

  // Ensure all addresses are present
  const keys: (keyof ExchangeConfig)[] = [
    "POOL_LIBRARY",
    "TOKEN_CONVERTER",
    "FACTORY",
    "SWAP_ROUTER",
    // "QUOTER",
    // "NFT_DESCRIPTOR",
    // "POSITION_DESCRIPTOR",
    "POSITION_MANAGER",
  ];
  for (const key of keys) {
    if (!cfg[key]) {
      throw new Error(`Missing address for ${key} in config.json`);
    }
  }

  console.log("🔍 Verifying Dex223PoolLib at", cfg.POOL_LIBRARY);
  await hre.run("verify:verify", {
    address: cfg.POOL_LIBRARY,
    constructorArguments: [],
    contract: "contracts/dex-core/Dex223PoolLib.sol:Dex223PoolLib",
  });

  console.log("🔍 Verifying TokenConverter at", cfg.TOKEN_CONVERTER);
  await hre.run("verify:verify", {
    address: cfg.TOKEN_CONVERTER,
    constructorArguments: [],
    contract: "contracts/converter/TokenConverter.sol:ERC7417TokenConverter",
  });

  console.log("🔍 Verifying Dex223Factory at", cfg.FACTORY);
  await hre.run("verify:verify", {
    address: cfg.FACTORY,
    constructorArguments: [],
    contract: "contracts/dex-core/Dex223Factory.sol:Dex223Factory",
  });

  console.log("🔍 Verifying ERC223SwapRouter at", cfg.SWAP_ROUTER);
  await hre.run("verify:verify", {
    address: cfg.SWAP_ROUTER,
    constructorArguments: [cfg.FACTORY, cfg.WETH9],
    contract: "contracts/dex-periphery/SwapRouter.sol:ERC223SwapRouter",
  });

  // console.log("🔍 Verifying Quoter223 at", cfg.QUOTER);
  // await hre.run("verify:verify", {
  //   address: cfg.QUOTER,
  //   constructorArguments: [cfg.FACTORY],
  //   contract: "contracts/dex-periphery/lens/Quoter223.sol:ERC223Quoter",
  // });

  // console.log("🔍 Verifying NFTDescriptor at", cfg.NFT_DESCRIPTOR);
  // await hre.run("verify:verify", {
  //   address: cfg.NFT_DESCRIPTOR,
  //   constructorArguments: [],
  //   contract: "contracts/dex-periphery/base/NFTDescriptor.sol:NFTDescriptor",
  // });

  // console.log(
  //   "🔍 Verifying NonfungibleTokenPositionDescriptor at",
  //   cfg.POSITION_DESCRIPTOR
  // );
  // await hre.run("verify:verify", {
  //   address: cfg.POSITION_DESCRIPTOR,
  //   constructorArguments: [
  //     cfg.WETH9,
  //     ethers.encodeBytes32String(cfg.NATIVE_LABEL || "WETH"),
  //   ],
  //   contract:
  //     "contracts/dex-periphery/NonfungibleTokenPositionDescriptor.sol:NonfungibleTokenPositionDescriptor",
  // });

  console.log(
    "🔍 Verifying NonfungiblePositionManager at",
    cfg.POSITION_MANAGER
  );
  await hre.run("verify:verify", {
    address: cfg.POSITION_MANAGER,
    constructorArguments: [cfg.FACTORY, cfg.WETH9],
    contract:
      "contracts/dex-periphery/NonfungiblePositionManager.sol:DexaransNonfungiblePositionManager",
  });

  console.log("✅ All contracts verified!");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
