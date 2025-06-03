import { ethers } from "hardhat";
import path from "path";
import { loadConfig, saveConfig } from "../utils/config";
import { AutoListingsRegistry } from "../../typechain-types";

export interface AutoListingConfig {
  FACTORY_ADDRESS: string;
  AUTO_LISTING_REGISTRY?: string;
  DEX223_AUTO_LISTING_CORE?: string;
  DEX223_AUTO_LISTING_FREE?: string;
}


const configPath = path.join(__dirname, "config.json");

async function main() {
  const cfg = loadConfig(configPath) as AutoListingConfig;

  // Ensure WETH9 address is provided in config
  if (!cfg.FACTORY_ADDRESS) {
    throw new Error(
      "FACTORY_ADDRESS address missing in config.json (cfg.WETH9)"
    );
  }
  if (!cfg.AUTO_LISTING_REGISTRY) {
    const RegistryAutolisting = await ethers.getContractFactory(
      "contracts/dex-core/Autolisting.sol:AutoListingsRegistry"
    );
    const registry =
      (await RegistryAutolisting.deploy()) as AutoListingsRegistry;
    // Wait for the deployment to be mined
    await registry.waitForDeployment();
    const registryAddress = await registry.getAddress();
    cfg.AUTO_LISTING_REGISTRY = registryAddress;
    console.log("AutoListingRegistry deployed at", registryAddress);

    saveConfig(configPath, cfg);
    console.log("config.json updated with AutoListingRegistry address");
  }

  if (!cfg.AUTO_LISTING_REGISTRY) {
    throw new Error(
      "AUTO_LISTING_REGISTRY address missing in config.json (cfg.AUTO_LISTING_REGISTRY)"
    );
  }
  const url = "test-app.dex223.io";

  // 2. Деплой Dex223AutoListing (Core)
  console.log("\n2) Deploying Dex223AutoListing (Core)...");
  const AutoListingFactory = await ethers.getContractFactory(
    "contracts/dex-core/Autolisting.sol:Dex223AutoListing"
  );
  const nameCore = "Dex223 Core Autolisting";
  const autoCore = await AutoListingFactory.deploy(
    cfg.FACTORY_ADDRESS,
    cfg.AUTO_LISTING_REGISTRY,
    nameCore,
    url
  );
  await autoCore.waitForDeployment();
  cfg.DEX223_AUTO_LISTING_CORE = await autoCore.getAddress();
  console.log(
    "   › Dex223AutoListing (Core) deployed to:",
    cfg.DEX223_AUTO_LISTING_CORE
  );
  saveConfig(configPath, cfg);

  // 3. Деплой Dex223AutoListing (Free)
  console.log("\n3) Deploying Dex223AutoListing (Free)...");
  const nameFree = "Dex223 Free Autolisting";
  const autoFree = await AutoListingFactory.deploy(
    cfg.FACTORY_ADDRESS,
    cfg.AUTO_LISTING_REGISTRY,
    nameFree,
    url
  );
  await autoFree.waitForDeployment();
  cfg.DEX223_AUTO_LISTING_FREE = await autoFree.getAddress();
  console.log(
    "   › Dex223AutoListing (Free) deployed to:",
    cfg.DEX223_AUTO_LISTING_FREE
  );
  saveConfig(configPath, cfg);

  console.log("\n✅ All contracts deploy!");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
