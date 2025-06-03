import hre from "hardhat";
import path from "path";
import { AutoListingConfig } from "./deploy";
import { loadConfig } from "../utils/config";

async function main() {
  const configPath = path.join(__dirname, "config.json");
  const cfg = loadConfig(configPath) as AutoListingConfig;

  if (!cfg.FACTORY_ADDRESS || !cfg.AUTO_LISTING_REGISTRY) {
    throw new Error("config.json don't have ORACLE_ADDRESS or MARGIN_ADDRESS");
  }

  console.log("Verifying AUTO_LISTING_REGISTRY at", cfg.AUTO_LISTING_REGISTRY);
  await hre.run("verify:verify", {
    address: cfg.AUTO_LISTING_REGISTRY,
    constructorArguments: [],
    contract: "contracts/dex-core/Autolisting.sol:AutoListingsRegistry",
  });

  const url = "test-app.dex223.io";
  const nameCore = "Dex223 Core Autolisting";
  console.log(`Verifying ${nameCore} at`, cfg.DEX223_AUTO_LISTING_CORE);
  await hre.run("verify:verify", {
    address: cfg.DEX223_AUTO_LISTING_CORE,
    constructorArguments: [
      cfg.FACTORY_ADDRESS,
      cfg.AUTO_LISTING_REGISTRY,
      nameCore,
      url,
    ],
    contract: "contracts/dex-core/Autolisting.sol:Dex223AutoListing",
  });

  const nameFree = "Dex223 Free Autolisting";
  console.log(`Verifying ${nameFree} at`, cfg.DEX223_AUTO_LISTING_FREE);
  await hre.run("verify:verify", {
    address: cfg.DEX223_AUTO_LISTING_FREE,
    constructorArguments: [
      cfg.FACTORY_ADDRESS,
      cfg.AUTO_LISTING_REGISTRY,
      nameFree,
      url,
    ],
    contract: "contracts/dex-core/Autolisting.sol:Dex223AutoListing",
  });

  console.log("✅ Verification complete");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
