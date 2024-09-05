import { BaseContract, Wallet, ContractTransactionResponse } from 'ethers'
import { ethers } from 'hardhat'
import { TestUniswapV3Callee, ERC223HybridToken } from '../../typechain-types'
import { TestUniswapV3Router } from '../../typechain-types'
import { MockTimeDex223Pool } from '../../typechain-types'
import { TestERC20 } from '../../typechain-types'
import bn from 'bignumber.js'
// import {TypedContractMethod} from "../../typechain-types/common";

export const MaxUint128 = 2n ** 128n - 1n

export const getMinTick = (tickSpacing: number) => BigInt(Math.ceil(-887272 / tickSpacing) * tickSpacing)
export const getMaxTick = (tickSpacing: number) => BigInt(Math.floor(887272 / tickSpacing) * tickSpacing)
export const getMaxLiquidityPerTick = (tickSpacing: number) =>
  (2n ** 128n - 1n) / ((getMaxTick(tickSpacing) - getMinTick(tickSpacing)) / BigInt(tickSpacing) + 1n)

export const MIN_SQRT_RATIO = BigInt('4295128739')
export const MAX_SQRT_RATIO = BigInt('1461446703485210103287273052203988822378723970342')

export enum FeeAmount {
  LOW = 500,
  MEDIUM = 3000,
  HIGH = 10000,
}

export const TICK_SPACINGS: { [amount in FeeAmount]: number } = {
  [FeeAmount.LOW]: 10,
  [FeeAmount.MEDIUM]: 60,
  [FeeAmount.HIGH]: 200,
}

export function expandTo18Decimals(n: number): bigint {
  return BigInt(n) * (10n ** 18n)
}

export function getCreate2Address(
  factoryAddress: string,
  [tokenA, tokenB]: [string, string],
  fee: number,
  bytecode: string
): string {
  const [token0, token1] = tokenA.toLowerCase() < tokenB.toLowerCase() ? [tokenA, tokenB] : [tokenB, tokenA]
  const constructorArgumentsEncoded = ethers.AbiCoder.defaultAbiCoder().encode(
    ['address', 'address', 'uint24'],
    [token0, token1, fee]
  )
  const create2Inputs = [
    '0xff',
    factoryAddress,
    // salt
    ethers.keccak256(constructorArgumentsEncoded),
    // init code. bytecode + constructor arguments
    ethers.keccak256(bytecode),
  ]
  const sanitizedInputs = `0x${create2Inputs.map((i) => i.slice(2)).join('')}`
  return ethers.getAddress(`0x${ethers.keccak256(sanitizedInputs).slice(-40)}`)
}

bn.config({ EXPONENTIAL_AT: 999999, DECIMAL_PLACES: 40 })

// returns the sqrt price as a 64x96
export function encodePriceSqrt(reserve1: bigint, reserve0: bigint): bigint {
  return  BigInt(
      new bn(reserve1.toString())
          .div(reserve0.toString())
          .sqrt()
          .multipliedBy(new bn(2).pow(96))
          .integerValue(3)
          .toString()
  )
  // return BigInt(Math.round(Math.sqrt(Number(reserve1) / Number(reserve0)) * (2 ** 96)))
}

export function getPositionKey(address: string, lowerTick: bigint, upperTick: bigint): string {
  return ethers.keccak256(ethers.solidityPacked(['address', 'int24', 'int24'], [address, lowerTick, upperTick]))
}

export type SwapFunction = (
  amount: bigint,
  to: Wallet | string,
  sqrtPriceLimitX96?: bigint,
  amountOutMin?: bigint,
  deadline?: bigint
) => Promise<ContractTransactionResponse>
export type SwapToPriceFunction = (sqrtPriceX96: bigint, to: Wallet | string) => Promise<ContractTransactionResponse>
// export type FlashFunction = (
//   amount0: bigint,
//   amount1: bigint,
//   to: Wallet | string,
//   pay0?: bigint,
//   pay1?: bigint
// ) => Promise<ContractTransactionResponse>
export type MintFunction = (
  recipient: string,
  tickLower: bigint,
  tickUpper: bigint,
  liquidity: bigint
) => Promise<ContractTransactionResponse>

export interface PoolFunctions {
  swapToLowerPrice: SwapToPriceFunction
  swapToHigherPrice: SwapToPriceFunction
  swapExact0For1: SwapFunction
  swap0ForExact1: SwapFunction
  swapExact1For0: SwapFunction
  swap1ForExact0: SwapFunction
  swapExact1For0_223: SwapFunction
  swapExact0For1_223: SwapFunction
  swapToHigherPrice_223: SwapFunction
  swapToLowerPrice_223: SwapFunction
  // flash: FlashFunction
  mint: MintFunction
  mint223: MintFunction
  mintMixed: MintFunction
}
export function createPoolFunctions({
  swapTarget,
  token0,
  token1,
  token0_223,
  token1_223,
  pool,
}: {
  swapTarget: TestUniswapV3Callee
  token0: TestERC20
  token1: TestERC20
  token0_223: ERC223HybridToken
  token1_223: ERC223HybridToken
  pool: MockTimeDex223Pool
}): PoolFunctions {
  async function swapToSqrtPrice(
    inputToken: BaseContract,
    targetPrice: bigint,
    to: Wallet | string
  ): Promise<ContractTransactionResponse> {
    const method = inputToken === (token0 as BaseContract) ? swapTarget.swapToLowerSqrtPrice : swapTarget.swapToHigherSqrtPrice

    // @ts-ignore
    await inputToken.approve(swapTarget.target, ethers.MaxUint256)

    const toAddress = typeof to === 'string' ? to : to.address

    return method(pool.target, targetPrice, toAddress)
  }

  async function swap(
    inputToken: BaseContract,
    [amountIn, amountOut]: [bigint, bigint],
    to: Wallet | string,
    sqrtPriceLimitX96?: bigint
  ): Promise<ContractTransactionResponse> {
    const exactInput = amountOut === 0n

    const method =
      inputToken === (token0 as BaseContract)
        ? exactInput
          ? swapTarget.swapExact0For1
          : swapTarget.swap0ForExact1
        : exactInput
        ? swapTarget.swapExact1For0
        : swapTarget.swap1ForExact0

    if (typeof sqrtPriceLimitX96 === 'undefined') {
      if (inputToken === (token0 as BaseContract)) {
        sqrtPriceLimitX96 = MIN_SQRT_RATIO + 1n
      } else {
        sqrtPriceLimitX96 = MAX_SQRT_RATIO - (1n)
      }
    }

    // @ts-ignore
    await inputToken.approve(swapTarget.target, ethers.MaxUint256)

    const toAddress = typeof to === 'string' ? to : to.address

    return method(pool.target, exactInput ? amountIn : amountOut, toAddress, sqrtPriceLimitX96)
  }

  async function swap223(
    inputToken: BaseContract,
    [amountIn, amountOut]: [bigint, bigint],
    to: Wallet | string,
    sqrtPriceLimitX96?: bigint,
    amountOutMin: bigint = 0n,
    deadline: bigint = 1601916400n
  ): Promise<ContractTransactionResponse> {
    // const exactInput = amountOut === 0n

    const toAddress = typeof to === 'string' ? to : to.address;
    if (typeof sqrtPriceLimitX96 === 'undefined') {
      if (inputToken === (token0_223 as BaseContract)) {
        sqrtPriceLimitX96 = MIN_SQRT_RATIO + 1n
      } else {
        sqrtPriceLimitX96 = MAX_SQRT_RATIO - (1n)
      }
    }
    // const values = [pool.target.toString(), exactInput ? amountIn : amountOut, toAddress, sqrtPriceLimitX96];
    const encoded  = ethers.AbiCoder.defaultAbiCoder().encode(
        ['address'],
        [toAddress]
    )
    const swapValues =
        [toAddress, inputToken.target == token0_223.target, amountIn, amountOutMin, sqrtPriceLimitX96, true, encoded, deadline];

    // @ts-ignore
    const data = pool.interface.encodeFunctionData('swapExactInput', swapValues);
    const bytes = ethers.getBytes(data)
    return await (inputToken as ERC223HybridToken)['transfer(address,uint256,bytes)'](pool.target, amountIn /*ethers.MaxUint256 / 4n - 1n */, bytes);
  }

  const swapToLowerPrice: SwapToPriceFunction = (sqrtPriceX96, to) => {
    return swapToSqrtPrice(token0 , sqrtPriceX96, to)
  }

  const swapToLowerPrice_223: SwapToPriceFunction = (sqrtPriceX96, to) => {
    const val = ethers.MaxInt256 - 1n;
    return swap223(token0_223 , [val, 0n], to, sqrtPriceX96);
  }

  const swapToHigherPrice: SwapToPriceFunction = (sqrtPriceX96, to) => {
    return swapToSqrtPrice(token1, sqrtPriceX96, to)
  }

  const swapToHigherPrice_223: SwapToPriceFunction = (sqrtPriceX96, to) => {
    const val = ethers.MaxInt256 - 1n;
    return swap223(token1_223 , [val, 0n], to, sqrtPriceX96);
  }

  const swapExact0For1: SwapFunction = (amount, to, sqrtPriceLimitX96) => {
    return swap(token0, [amount, 0n], to, sqrtPriceLimitX96)
  }

  const swapExact0For1_223: SwapFunction = (amount, to, sqrtPriceLimitX96, amountOutMin = undefined, deadline = undefined) => {
    return swap223(token0_223, [amount, 0n], to, sqrtPriceLimitX96, amountOutMin, deadline);
  }

  const swap0ForExact1: SwapFunction = (amount, to, sqrtPriceLimitX96) => {
    return swap(token0, [0n, amount], to, sqrtPriceLimitX96)
  }

  const swapExact1For0: SwapFunction = (amount, to, sqrtPriceLimitX96) => {
    return swap(token1, [amount, 0n], to, sqrtPriceLimitX96)
  }

  const swapExact1For0_223: SwapFunction = (amount, to, sqrtPriceLimitX96, amountOutMin = undefined, deadline = undefined) => {
    return swap223(token1_223, [amount, 0n], to, sqrtPriceLimitX96, amountOutMin, deadline);
  }

  const swap1ForExact0: SwapFunction = (amount, to, sqrtPriceLimitX96) => {
    return swap(token1, [0n, amount], to, sqrtPriceLimitX96)
  }

  const mint: MintFunction = async (recipient, tickLower, tickUpper, liquidity) => {
    await token0.approve(swapTarget.target, ethers.MaxUint256);
    await token1.approve(swapTarget.target, ethers.MaxUint256);
    return swapTarget.mint(pool.target, recipient, tickLower, tickUpper, liquidity);
  }

  const mint223: MintFunction = async (recipient, tickLower, tickUpper, liquidity) => {
    // NOTE: how not to transfer max ?
    await token0_223['transfer(address,uint256,bytes)'](swapTarget.target, ethers.MaxUint256 / 6n - 1n, new Uint8Array());
    const data = swapTarget.interface.encodeFunctionData('mint',
        [pool.target.toString(), recipient, tickLower, tickUpper, liquidity]);
    const bytes = ethers.getBytes(data)
    return await token1_223['transfer(address,uint256,bytes)'](swapTarget.target, ethers.MaxUint256 / 6n - 1n, bytes);
  }

  const mintMixed: MintFunction = async (recipient, tickLower, tickUpper, liquidity) => {
    await token0_223['transfer(address,uint256,bytes)'](swapTarget.target, ethers.MaxUint256 / 6n - 1n, new Uint8Array());
    await token1.approve(swapTarget.target, ethers.MaxUint256);
    return swapTarget.mint(pool.target, recipient, tickLower, tickUpper, liquidity);
  }

  // const flash: FlashFunction = async (amount0, amount1, to, pay0?: bigint, pay1?: bigint) => {
  //   const fee = await pool.fee()
  //   if (typeof pay0 === 'undefined') {
  //     pay0 = BigNumber.from(amount0)
  //       .mul(fee)
  //       .add(1e6 - 1)
  //       .div(1e6)
  //       .add(amount0)
  //   }
  //   if (typeof pay1 === 'undefined') {
  //     pay1 = BigNumber.from(amount1)
  //       .mul(fee)
  //       .add(1e6 - 1)
  //       .div(1e6)
  //       .add(amount1)
  //   }
  //   return swapTarget.flash(pool.address, typeof to === 'string' ? to : to.address, amount0, amount1, pay0, pay1)
  // }

  return {
    swapToLowerPrice,
    swapToHigherPrice,
    swapExact0For1,
    swap0ForExact1,
    swapExact1For0,
    swap1ForExact0,
    mint,
    mint223,
    mintMixed,
    swapExact0For1_223,
    swapExact1For0_223,
    swapToLowerPrice_223,
    swapToHigherPrice_223
    // flash,
  }
}

export interface MultiPoolFunctions {
  swapForExact0Multi: SwapFunction
  swapForExact1Multi: SwapFunction
}

export function createMultiPoolFunctions({
  inputToken,
  swapTarget,
  poolInput,
  poolOutput,
}: {
  inputToken: TestERC20
  swapTarget: TestUniswapV3Router
  poolInput: MockTimeDex223Pool
  poolOutput: MockTimeDex223Pool
}): MultiPoolFunctions {
  async function swapForExact0Multi(amountOut: bigint, to: Wallet | string): Promise<ContractTransactionResponse> {
    const method = swapTarget.swapForExact0Multi
    await inputToken.approve(swapTarget.target, ethers.MaxUint256)
    const toAddress = typeof to === 'string' ? to : to.address
    return method(toAddress, poolInput.target, poolOutput.target, amountOut)
  }

  async function swapForExact1Multi(amountOut: bigint, to: Wallet | string): Promise<ContractTransactionResponse> {
    const method = swapTarget.swapForExact1Multi
    await inputToken.approve(swapTarget.target, ethers.MaxUint256)
    const toAddress = typeof to === 'string' ? to : to.address
    return method(toAddress, poolInput.target, poolOutput.target, amountOut)
  }

  return {
    swapForExact0Multi,
    swapForExact1Multi,
  }
}
