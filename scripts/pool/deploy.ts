import { ethers } from "hardhat";
import { BaseContract, Contract } from "ethers";
import bn from "bignumber.js";

import POSITION_MANAGER from "../../artifacts/contracts/dex-periphery/NonfungiblePositionManager.sol/DexaransNonfungiblePositionManager.json";
import FACTORY from "../../artifacts/contracts/dex-core/Dex223Factory.sol/Dex223Factory.json";
import coreConfig from "../core/config.json";

import {
  Dex223Factory,
  DexaransNonfungiblePositionManager,
} from "../../typechain-types";

const provider = ethers.provider;

export function expandTo18Decimals(n: number): bigint {
  return BigInt(n) * 10n ** 18n;
}

bn.config({ EXPONENTIAL_AT: 999999, DECIMAL_PLACES: 40 });

export function encodePriceSqrt(reserve1: bigint, reserve0: bigint): bigint {
  return BigInt(
    new bn(reserve1.toString())
      .div(reserve0.toString())
      .sqrt()
      .multipliedBy(new bn(2).pow(96))
      .integerValue(3)
      .toString()
  );
  // return BigInt(Math.round(Math.sqrt(Number(reserve1) / Number(reserve0)) * (2 ** 96)))
}

const nonfungiblePositionManager = new Contract(
  coreConfig.POSITION_MANAGER,
  POSITION_MANAGER.abi,
  provider
) as BaseContract as DexaransNonfungiblePositionManager;

const factory = new Contract(
  coreConfig.FACTORY,
  FACTORY.abi,
  provider
) as BaseContract as Dex223Factory;

export async function createPool(
  token0erc20: string,
  token1erc20: string,
  token0erc223: string,
  token1erc223: string,
  fee: number
) {
  const [owner] = await ethers.getSigners();

  const tx = await factory
    .connect(owner)
    .createPool(token0erc20, token1erc20, token0erc223, token1erc223, fee, {
      gasLimit: 15_000_000, //30_000_000
    });
  await tx.wait();
  const poolAddress = await factory
    .connect(owner)
    .getPool(token0erc20, token1erc20, fee);
  return poolAddress;
}

export async function deployPool(
  token0erc20: string,
  token1erc20: string,
  token0erc223: string,
  token1erc223: string,
  fee: number,
  price: bigint
): Promise<string> {
  console.log(
    `Deploy pool: ${token0erc20} | ${token1erc20} | ${token0erc223} | ${token1erc223}`
  );
  const [owner] = await ethers.getSigners();

  const tx = await nonfungiblePositionManager
    .connect(owner)
    .createAndInitializePoolIfNecessary(
      token0erc20,
      token1erc20,
      token0erc223,
      token1erc223,
      fee,
      price,
      {
        gasLimit: 15_000_000, //30_000_000
      }
    );
  await tx.wait();
  // console.log(`pool deployed: ${token0erc20} | ${token1erc20} | ${token0erc223} | ${token1erc223}`);
  const poolAddress = await factory
    .connect(owner)
    .getPool(token0erc20, token1erc20, fee);
  return poolAddress;
}
