// scripts/margin/deploy-margin.ts
import { ethers } from "hardhat";
import path from "path";
import { loadConfig } from "../utils/config";
import { saveConfig } from "../utils/config";
import type { Oracle, MarginModule } from "../../typechain-types";


export interface MarginConfig {
  FACTORY_ADDRESS: string;
  ROUTER_ADDRESS: string;
  ORACLE_ADDRESS?: string;
  MARGIN_ADDRESS?: string;
}

async function main() {
  const configPath = path.join(__dirname, "config.json");
  const cfg = loadConfig(configPath) as MarginConfig;

  // 1) Deploy Oracle, if doesn't exist
  if (!cfg.ORACLE_ADDRESS) {
    console.log("Deploying Oracle...");
    const OracleFactory = await ethers.getContractFactory(
      "contracts/dex-core/Dex223Oracle.sol:Oracle"
    );
    const oracle = (await OracleFactory.deploy(cfg.FACTORY_ADDRESS)) as Oracle;
    // Wait for the deployment to be mined
    await oracle.waitForDeployment();
    const oracleAddress = await oracle.getAddress();
    cfg.ORACLE_ADDRESS = oracleAddress;
    console.log("Oracle deployed at", oracleAddress);

    saveConfig(configPath, cfg);
    console.log("config.json updated with ORACLE_ADDRESS");
  } else {
    console.log("Oracle already deployed at", cfg.ORACLE_ADDRESS);
  }

  // 2) Deploy MarginModule
  console.log("Deploying MarginModule...");
  const MarginFactory = await ethers.getContractFactory(
    "contracts/dex-core/Dex223MarginModule.sol:MarginModule"
  );
  const margin = (await MarginFactory.deploy(
    cfg.FACTORY_ADDRESS,
    cfg.ORACLE_ADDRESS!,
    cfg.ROUTER_ADDRESS
  )) as MarginModule;
  await margin.waitForDeployment();

  const marginAddress = await margin.getAddress();
  cfg.MARGIN_ADDRESS = marginAddress;
  saveConfig(configPath, cfg);
  console.log("✅ Done. MarginModule at", marginAddress);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
