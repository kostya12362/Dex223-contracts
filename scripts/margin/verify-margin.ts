import hre from "hardhat";
import path from "path";
import { MarginConfig } from "./deploy-margin";
import { loadConfig } from "../utils/config";

async function main() {
  const configPath = path.join(__dirname, "config.json");
  const cfg = loadConfig(configPath) as MarginConfig;

  if (!cfg.ORACLE_ADDRESS || !cfg.MARGIN_ADDRESS) {
    throw new Error("config.json don't have ORACLE_ADDRESS or MARGIN_ADDRESS");
  }

  console.log("Verifying Oracle at", cfg.ORACLE_ADDRESS);
  await hre.run("verify:verify", {
    address: cfg.ORACLE_ADDRESS,
    constructorArguments: [cfg.FACTORY_ADDRESS],
    contract: "contracts/dex-core/Dex223Oracle.sol:Oracle",
  });

  console.log("Verifying MarginModule at", cfg.MARGIN_ADDRESS);
  await hre.run("verify:verify", {
    address: cfg.MARGIN_ADDRESS,
    constructorArguments: [
      cfg.FACTORY_ADDRESS,
      cfg.ORACLE_ADDRESS,
      cfg.ROUTER_ADDRESS,
    ],
    contract: "contracts/dex-core/Dex223MarginModule.sol:MarginModule",
  });

  console.log("✅ Verification complete");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
