import { ethers } from "hardhat";
import path from "path";
import { BaseContract, Contract } from "ethers";
import { TokenStandardConverter } from "../../typechain-types";
import { loadConfig, saveConfig } from "../utils/config";
import { ERC20 } from "../../typechain-types";
import TOKEN_CONVERTER from "../../artifacts/contracts/converter/TokenConverter.sol/TokenStandardConverter.json";
import ERC20Token from "../../artifacts/contracts/tokens/ERC20mod.sol/ERC20.json";
import coreConfig from "../core/config.json";
import { deployPool, encodePriceSqrt, createPool } from "./deploy";
const provider = ethers.provider;

interface PoolConfig {
  USDC: string;
  WETH: string;
  POOL?: string;
}

async function main() {
  const convertContract = new Contract(
    coreConfig.TOKEN_CONVERTER,
    TOKEN_CONVERTER.abi,
    provider
  ) as BaseContract as TokenStandardConverter;
  const configPath = path.join(__dirname, "config.json");
  const cfg = loadConfig(configPath) as PoolConfig;
  const fee = 3000; // 0.3%
  if (!cfg.USDC || !cfg.WETH) {
    throw new Error("USDC and WETH addresses must be provided in config.json");
  }
  const token0 =
    cfg.WETH.toLowerCase() < cfg.USDC.toLowerCase() ? cfg.WETH : cfg.USDC;
  const token1 = token0 === cfg.WETH ? cfg.USDC : cfg.WETH;

  // 5. Вычисляем адреса их ERC-223 обёрток
  const [wrapper0, wrapper1] = await Promise.all([
    convertContract.predictWrapperAddress(token0, true),
    convertContract.predictWrapperAddress(token1, true),
  ]);
  console.log(`"${token0}" "${wrapper0}" "${token1}" "${wrapper1}"`);
  // 6. Берём децимали обоих токенов
  const [dec0, dec1] = await Promise.all([
    new Contract(token0, ERC20Token.abi, ethers.provider).decimals(),
    new Contract(token1, ERC20Token.abi, ethers.provider).decimals(),
  ]);

  // 7. Строим резервы в виде целых с учётом децималей
  const reserve0 = 10n ** BigInt(dec0); // 1 единица token0
  const reserve1 = 3500n * 10n ** BigInt(dec1); // 3500 единиц token1
  if (cfg.POOL) {
    console.log("Pool already exists at", cfg.POOL);
    return;
  }

  // 8. Подготовка параметров пула
  // const priceX96 = encodePriceSqrt(reserve1, reserve0);

  const poolAddr = await deployPool(
    token0,
    token1,
    wrapper0,
    wrapper1,
    fee,
    encodePriceSqrt(reserve1, reserve0)
    // encodePriceSqrt(2n, 1n)
  );

  console.log("✅ Pool at", poolAddr);
  saveConfig(configPath, {
    ...cfg,
    POOL: poolAddr,
  });
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
// hardhat verify --network sepolia 0x3B2E627DbDd6B8cc2CbA9B71154b32C9bb5Ed5d3 "0x44649c38615ad4426c16cd5d5059e6e74b87234a" "0xb16f35c0ae2912430dac15764477e179d9b9ebea" "0x9df14c01498fba1dc568e9435cd62b18ffd79238" "0xdc31fbf5c6149e612a6a01eb30ce85906866a9da" 3000