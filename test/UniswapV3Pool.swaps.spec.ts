import { Decimal } from 'decimal.js'
import { ContractTransactionResponse, Wallet} from 'ethers'
import { ethers } from 'hardhat'
import {ERC223HybridToken, MockTimeDex223Pool} from '../typechain-types/'
import { TestERC20 } from '../typechain-types/'

import { TestUniswapV3Callee } from '../typechain-types/'
import { expect, use } from 'chai'
import { poolFixture } from './shared/fixtures'
import { formatPrice, formatTokenAmount } from './shared/format'
import {
  createPoolFunctions,
  encodePriceSqrt,
  expandTo18Decimals,
  FeeAmount,
  getMaxLiquidityPerTick,
  getMaxTick,
  getMinTick,
  MAX_SQRT_RATIO,
  MaxUint128,
  MIN_SQRT_RATIO,
  TICK_SPACINGS,
} from './shared/utilities'
import {
  loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";

import { jestSnapshotPlugin } from 'mocha-chai-jest-snapshot'

use(jestSnapshotPlugin());

Decimal.config({ toExpNeg: -500, toExpPos: 500 })

// const createFixtureLoader = waffle.createFixtureLoader
// const { constants } = ethers

interface BaseSwapTestCase {
  zeroForOne: boolean
  sqrtPriceLimit?: bigint
}
interface SwapExact0For1TestCase extends BaseSwapTestCase {
  zeroForOne: true
  exactOut: false
  amount0: bigint
  sqrtPriceLimit?: bigint
}
interface SwapExact1For0TestCase extends BaseSwapTestCase {
  zeroForOne: false
  exactOut: false
  amount1: bigint
  sqrtPriceLimit?: bigint
}
interface Swap0ForExact1TestCase extends BaseSwapTestCase {
  zeroForOne: true
  exactOut: true
  amount1: bigint
  sqrtPriceLimit?: bigint
}
interface Swap1ForExact0TestCase extends BaseSwapTestCase {
  zeroForOne: false
  exactOut: true
  amount0: bigint
  sqrtPriceLimit?: bigint
}
interface SwapToHigherPrice extends BaseSwapTestCase {
  zeroForOne: false
  sqrtPriceLimit: bigint
}
interface SwapToLowerPrice extends BaseSwapTestCase {
  zeroForOne: true
  sqrtPriceLimit: bigint
}
type SwapTestCase =
  | SwapExact0For1TestCase
  | Swap0ForExact1TestCase
  | SwapExact1For0TestCase
  | Swap1ForExact0TestCase
  | SwapToHigherPrice
  | SwapToLowerPrice

function swapCaseToDescription(testCase: SwapTestCase): string {
  const priceClause = testCase?.sqrtPriceLimit ? ` to price ${formatPrice(testCase.sqrtPriceLimit)}` : ''
  if ('exactOut' in testCase) {
    if (testCase.exactOut) {
      if (testCase.zeroForOne) {
        return `swap token0 for exactly ${formatTokenAmount(testCase.amount1)} token1${priceClause}`
      } else {
        return `swap token1 for exactly ${formatTokenAmount(testCase.amount0)} token0${priceClause}`
      }
    } else {
      if (testCase.zeroForOne) {
        return `swap exactly ${formatTokenAmount(testCase.amount0)} token0 for token1${priceClause}`
      } else {
        return `swap exactly ${formatTokenAmount(testCase.amount1)} token1 for token0${priceClause}`
      }
    }
  } else {
    if (testCase.zeroForOne) {
      return `swap token0 for token1${priceClause}`
    } else {
      return `swap token1 for token0${priceClause}`
    }
  }
}

type PoolFunctions = ReturnType<typeof createPoolFunctions>

// can't use address zero because the ERC20 token does not allow it
const SWAP_RECIPIENT_ADDRESS = ethers.ZeroAddress.slice(0, -1) + '1'
const POSITION_PROCEEDS_OUTPUT_ADDRESS = ethers.ZeroAddress.slice(0, -1) + '2'

async function executeSwap(
  // pool: MockTimeDex223Pool,
  testCase: SwapTestCase,
  poolFunctions: PoolFunctions,
  swapErc223: boolean
): Promise<ContractTransactionResponse | undefined> {
  let swap: ContractTransactionResponse
  if ('exactOut' in testCase) {
    if (testCase.exactOut) {
      if (swapErc223) {
        return undefined;
      }
      if (testCase.zeroForOne) {
        swap = await poolFunctions.swap0ForExact1(testCase.amount1, SWAP_RECIPIENT_ADDRESS, testCase.sqrtPriceLimit)
      } else {
        swap = await poolFunctions.swap1ForExact0(testCase.amount0, SWAP_RECIPIENT_ADDRESS, testCase.sqrtPriceLimit)
      }
    } else {
      if (testCase.zeroForOne) {
        if (swapErc223) {
          swap = await poolFunctions.swapExact0For1_223(testCase.amount0, SWAP_RECIPIENT_ADDRESS, testCase.sqrtPriceLimit);
        } else {
          swap = await poolFunctions.swapExact0For1(testCase.amount0, SWAP_RECIPIENT_ADDRESS, testCase.sqrtPriceLimit);
        }
      } else {
        if (swapErc223) {
          swap = await poolFunctions.swapExact1For0_223(testCase.amount1, SWAP_RECIPIENT_ADDRESS, testCase.sqrtPriceLimit);
        } else {
          swap = await poolFunctions.swapExact1For0(testCase.amount1, SWAP_RECIPIENT_ADDRESS, testCase.sqrtPriceLimit);
        }
      }
    }
  } else {
    if (testCase.zeroForOne) {
      if (swapErc223) {
        swap = await poolFunctions.swapToLowerPrice_223(testCase.sqrtPriceLimit, SWAP_RECIPIENT_ADDRESS);
      } else {
        swap = await poolFunctions.swapToLowerPrice(testCase.sqrtPriceLimit, SWAP_RECIPIENT_ADDRESS);
      }
    } else {
      if (swapErc223) {
        swap = await poolFunctions.swapToHigherPrice_223(testCase.sqrtPriceLimit, SWAP_RECIPIENT_ADDRESS);
      } else {
        swap = await poolFunctions.swapToHigherPrice(testCase.sqrtPriceLimit, SWAP_RECIPIENT_ADDRESS);
      }
    }
  }
  return swap
}

const DEFAULT_POOL_SWAP_TESTS: SwapTestCase[] = [
  // swap large amounts in/out
  {
    zeroForOne: true,
    exactOut: false,
    amount0: expandTo18Decimals(1),
  },
  {
    zeroForOne: false,
    exactOut: false,
    amount1: expandTo18Decimals(1),
  },
  {
    zeroForOne: true,
    exactOut: true,
    amount1: expandTo18Decimals(1),
  },
  {
    zeroForOne: false,
    exactOut: true,
    amount0: expandTo18Decimals(1),
  },
  // swap large amounts in/out with a price limit
  {
    zeroForOne: true,
    exactOut: false,
    amount0: expandTo18Decimals(1),
    sqrtPriceLimit: encodePriceSqrt(50n, 100n),
  },
  {
    zeroForOne: false,
    exactOut: false,
    amount1: expandTo18Decimals(1),
    sqrtPriceLimit: encodePriceSqrt(200n, 100n),
  },
  {
    zeroForOne: true,
    exactOut: true,
    amount1: expandTo18Decimals(1),
    sqrtPriceLimit: encodePriceSqrt(50n, 100n),
  },
  {
    zeroForOne: false,
    exactOut: true,
    amount0: expandTo18Decimals(1),
    sqrtPriceLimit: encodePriceSqrt(200n, 100n),
  },
  // swap small amounts in/out
  {
    zeroForOne: true,
    exactOut: false,
    amount0: 1000n,
  },
  {
    zeroForOne: false,
    exactOut: false,
    amount1: 1000n,
  },
  {
    zeroForOne: true,
    exactOut: true,
    amount1: 1000n,
  },
  {
    zeroForOne: false,
    exactOut: true,
    amount0: 1000n,
  },
  // swap arbitrary input to price
  {
    sqrtPriceLimit: encodePriceSqrt(5n, 2n),
    zeroForOne: false,
  },
  {
    sqrtPriceLimit: encodePriceSqrt(2n, 5n),
    zeroForOne: true,
  },
  {
    sqrtPriceLimit: encodePriceSqrt(5n, 2n),
    zeroForOne: true,
  },
  {
    sqrtPriceLimit: encodePriceSqrt(2n, 5n),
    zeroForOne: false,
  },
]

interface Position {
  tickLower: number
  tickUpper: number
  liquidity: bigint
}

interface PoolTestCase {
  description: string
  feeAmount: number
  tickSpacing: number
  startingPrice: bigint
  positions: Position[]
  swapTests?: SwapTestCase[]
}

const TEST_POOLS: PoolTestCase[] = [
  {
    description: 'low fee, 1:1 price, 2e18 max range liquidity',
    feeAmount: FeeAmount.LOW,
    tickSpacing: TICK_SPACINGS[FeeAmount.LOW],
    startingPrice: encodePriceSqrt(1n, 1n),
    positions: [
      {
        tickLower: Number(getMinTick(TICK_SPACINGS[FeeAmount.LOW])),
        tickUpper: Number(getMaxTick(TICK_SPACINGS[FeeAmount.LOW])),
        liquidity: expandTo18Decimals(2),
      },
    ],
  },
  {
    description: 'medium fee, 1:1 price, 2e18 max range liquidity',
    feeAmount: FeeAmount.MEDIUM,
    tickSpacing: TICK_SPACINGS[FeeAmount.MEDIUM],
    startingPrice: encodePriceSqrt(1n, 1n),
    positions: [
      {
        tickLower: Number(getMinTick(TICK_SPACINGS[FeeAmount.MEDIUM])),
        tickUpper: Number(getMaxTick(TICK_SPACINGS[FeeAmount.MEDIUM])),
        liquidity: expandTo18Decimals(2),
      },
    ],
  },
  {
    description: 'high fee, 1:1 price, 2e18 max range liquidity',
    feeAmount: FeeAmount.HIGH,
    tickSpacing: TICK_SPACINGS[FeeAmount.HIGH],
    startingPrice: encodePriceSqrt(1n, 1n),
    positions: [
      {
        tickLower: Number(getMinTick(TICK_SPACINGS[FeeAmount.HIGH])),
        tickUpper: Number(getMaxTick(TICK_SPACINGS[FeeAmount.HIGH])),
        liquidity: expandTo18Decimals(2),
      },
    ],
  },
  {
    description: 'medium fee, 10:1 price, 2e18 max range liquidity',
    feeAmount: FeeAmount.MEDIUM,
    tickSpacing: TICK_SPACINGS[FeeAmount.MEDIUM],
    startingPrice: encodePriceSqrt(10n, 1n),
    positions: [
      {
        tickLower: Number(getMinTick(TICK_SPACINGS[FeeAmount.MEDIUM])),
        tickUpper: Number(getMaxTick(TICK_SPACINGS[FeeAmount.MEDIUM])),
        liquidity: expandTo18Decimals(2),
      },
    ],
  },
  {
    description: 'medium fee, 1:10 price, 2e18 max range liquidity',
    feeAmount: FeeAmount.MEDIUM,
    tickSpacing: TICK_SPACINGS[FeeAmount.MEDIUM],
    startingPrice: encodePriceSqrt(1n, 10n),
    positions: [
      {
        tickLower: Number(getMinTick(TICK_SPACINGS[FeeAmount.MEDIUM])),
        tickUpper: Number(getMaxTick(TICK_SPACINGS[FeeAmount.MEDIUM])),
        liquidity: expandTo18Decimals(2),
      },
    ],
  },
  {
    description: 'medium fee, 1:1 price, 0 liquidity, all liquidity around current price',
    feeAmount: FeeAmount.MEDIUM,
    tickSpacing: TICK_SPACINGS[FeeAmount.MEDIUM],
    startingPrice: encodePriceSqrt(1n, 1n),
    positions: [
      {
        tickLower: Number(getMinTick(TICK_SPACINGS[FeeAmount.MEDIUM])),
        tickUpper: Number(-TICK_SPACINGS[FeeAmount.MEDIUM]),
        liquidity: expandTo18Decimals(2),
      },
      {
        tickLower: Number(TICK_SPACINGS[FeeAmount.MEDIUM]),
        tickUpper: Number(getMaxTick(TICK_SPACINGS[FeeAmount.MEDIUM])),
        liquidity: expandTo18Decimals(2),
      },
    ],
  },
  {
    description: 'medium fee, 1:1 price, additional liquidity around current price',
    feeAmount: FeeAmount.MEDIUM,
    tickSpacing: TICK_SPACINGS[FeeAmount.MEDIUM],
    startingPrice: encodePriceSqrt(1n, 1n),
    positions: [
      {
        tickLower: Number(getMinTick(TICK_SPACINGS[FeeAmount.MEDIUM])),
        tickUpper: Number(getMaxTick(TICK_SPACINGS[FeeAmount.MEDIUM])),
        liquidity: expandTo18Decimals(2),
      },
      {
        tickLower: Number(getMinTick(TICK_SPACINGS[FeeAmount.MEDIUM])),
        tickUpper: Number(-TICK_SPACINGS[FeeAmount.MEDIUM]),
        liquidity: expandTo18Decimals(2),
      },
      {
        tickLower: Number(TICK_SPACINGS[FeeAmount.MEDIUM]),
        tickUpper: Number(getMaxTick(TICK_SPACINGS[FeeAmount.MEDIUM])),
        liquidity: expandTo18Decimals(2),
      },
    ],
  },
  {
    description: 'low fee, large liquidity around current price (stable swap)',
    feeAmount: FeeAmount.LOW,
    tickSpacing: TICK_SPACINGS[FeeAmount.LOW],
    startingPrice: encodePriceSqrt(1n, 1n),
    positions: [
      {
        tickLower: Number(-TICK_SPACINGS[FeeAmount.LOW]),
        tickUpper: Number(TICK_SPACINGS[FeeAmount.LOW]),
        liquidity: expandTo18Decimals(2),
      },
    ],
  },
  {
    description: 'medium fee, token0 liquidity only',
    feeAmount: FeeAmount.MEDIUM,
    tickSpacing: Number(TICK_SPACINGS[FeeAmount.MEDIUM]),
    startingPrice: encodePriceSqrt(1n, 1n),
    positions: [
      {
        tickLower: 0,
        tickUpper: 2000 * TICK_SPACINGS[FeeAmount.MEDIUM],
        liquidity: expandTo18Decimals(2),
      },
    ],
  },
  {
    description: 'medium fee, token1 liquidity only',
    feeAmount: FeeAmount.MEDIUM,
    tickSpacing: TICK_SPACINGS[FeeAmount.MEDIUM],
    startingPrice: encodePriceSqrt(1n, 1n),
    positions: [
      {
        tickLower: -2000 * TICK_SPACINGS[FeeAmount.MEDIUM],
        tickUpper: 0,
        liquidity: expandTo18Decimals(2),
      },
    ],
  },
  {
    description: 'close to max price',
    feeAmount: FeeAmount.MEDIUM,
    tickSpacing: TICK_SPACINGS[FeeAmount.MEDIUM],
    startingPrice: encodePriceSqrt(2n ** 127n, 1n),
    positions: [
      {
        tickLower: Number(getMinTick(TICK_SPACINGS[FeeAmount.MEDIUM])),
        tickUpper: Number(getMaxTick(TICK_SPACINGS[FeeAmount.MEDIUM])),
        liquidity: expandTo18Decimals(2),
      },
    ],
  },
  {
    description: 'close to min price',
    feeAmount: FeeAmount.MEDIUM,
    tickSpacing: TICK_SPACINGS[FeeAmount.MEDIUM],
    startingPrice: encodePriceSqrt(1n, 2n ** 127n),
    positions: [
      {
        tickLower: Number(getMinTick(TICK_SPACINGS[FeeAmount.MEDIUM])),
        tickUpper: Number(getMaxTick(TICK_SPACINGS[FeeAmount.MEDIUM])),
        liquidity: expandTo18Decimals(2),
      },
    ],
  },
  {
    description: 'max full range liquidity at 1:1 price with default fee',
    feeAmount: FeeAmount.MEDIUM,
    tickSpacing: TICK_SPACINGS[FeeAmount.MEDIUM],
    startingPrice: encodePriceSqrt(1n, 1n),
    positions: [
      {
        tickLower: Number(getMinTick(TICK_SPACINGS[FeeAmount.MEDIUM])),
        tickUpper: Number(getMaxTick(TICK_SPACINGS[FeeAmount.MEDIUM])),
        liquidity: getMaxLiquidityPerTick(TICK_SPACINGS[FeeAmount.MEDIUM]),
      },
    ],
  },
  {
    description: 'initialized at the max ratio',
    feeAmount: FeeAmount.MEDIUM,
    tickSpacing: TICK_SPACINGS[FeeAmount.MEDIUM],
    startingPrice: MAX_SQRT_RATIO - (1n),
    positions: [
      {
        tickLower: Number(getMinTick(TICK_SPACINGS[FeeAmount.MEDIUM])),
        tickUpper: Number(getMaxTick(TICK_SPACINGS[FeeAmount.MEDIUM])),
        liquidity: expandTo18Decimals(2),
      },
    ],
  },
  {
    description: 'initialized at the min ratio',
    feeAmount: FeeAmount.MEDIUM,
    tickSpacing: TICK_SPACINGS[FeeAmount.MEDIUM],
    startingPrice: MIN_SQRT_RATIO,
    positions: [
      {
        tickLower: Number(getMinTick(TICK_SPACINGS[FeeAmount.MEDIUM])),
        tickUpper: Number(getMaxTick(TICK_SPACINGS[FeeAmount.MEDIUM])),
        liquidity: expandTo18Decimals(2),
      },
    ],
  },
]

describe('UniswapV3Pool swap tests', () => {
  let wallet: Wallet, other: Wallet

  before('create fixture loader', async () => {
    ;[wallet, other] = await (ethers as any).getSigners()
  })

  for (let i = 0; i < 2; i++) {
    let description = (i > 0) ? 'ERC223 swap tests' : 'ERC20 swap tests';

    describe(description, () => {
    for (const poolCase of TEST_POOLS) {
      describe(poolCase.description, () => {
        const poolCaseFixture = async () => {
          const {createPool, converter, token0, token1, swapTargetCallee: swapTarget} = await poolFixture()

          await token0.approve(converter.target.toString(), ethers.MaxUint256 / 2n);
          await token1.approve(converter.target.toString(), ethers.MaxUint256 / 2n);

          await converter.wrapERC20toERC223(token0.target, ethers.MaxUint256 / 2n);
          await converter.wrapERC20toERC223(token1.target, ethers.MaxUint256 / 2n);

          const TokenFactory = await ethers.getContractFactory('ERC223HybridToken');
          let tokenAddress = await converter.predictWrapperAddress(token0.target, true);
          const token0_223 = TokenFactory.attach(tokenAddress) as ERC223HybridToken;
          tokenAddress = await converter.predictWrapperAddress(token1.target, true);
          const token1_223 = TokenFactory.attach(tokenAddress) as ERC223HybridToken;

          const pool = await createPool(poolCase.feeAmount, poolCase.tickSpacing)
          const poolFunctions = createPoolFunctions({
            swapTarget, token0, token1, pool, token0_223, token1_223
          })
          await pool.initialize(poolCase.startingPrice);

          // mint all positions
          let mintFn = (i > 0) ? poolFunctions.mint223 : poolFunctions.mint;
          for (const position of poolCase.positions) {
            await mintFn(wallet.address, BigInt(position.tickLower), BigInt(position.tickUpper), BigInt(position.liquidity))
          }

          const [balance0, balance1, balance0_223, balance1_223] = await Promise.all([
            token0.balanceOf(pool.target),
            token1.balanceOf(pool.target),
            token0_223.balanceOf(pool.target),
            token1_223.balanceOf(pool.target),
          ])

          const poolBalance0 = balance0 + balance0_223;
          const poolBalance1 = balance1 + balance1_223;

          return {token0, token1, token0_223, token1_223, pool, poolFunctions, poolBalance0, poolBalance1, swapTarget}
        }

        let token0: TestERC20
        let token1: TestERC20
        let token0_223: ERC223HybridToken
        let token1_223: ERC223HybridToken

        let poolBalance0: bigint
        let poolBalance1: bigint

        let pool: MockTimeDex223Pool
        let swapTarget: TestUniswapV3Callee
        let poolFunctions: PoolFunctions

        // first cycle - use ERC20, second - ERC223
        let tokenOut0_223 = false;
        let tokenOut1_223 = false;
        let swapErc223 = false;
        let eventName = 'Transfer';
        let eventToken0: TestERC20 | ERC223HybridToken;
        let eventToken1: TestERC20 | ERC223HybridToken;
        let swapTargetAddress: string;
        let walletTarget: string;

        beforeEach('load fixture', async () => {
          ;({
            token0,
            token1,
            token0_223,
            token1_223,
            pool,
            poolFunctions,
            poolBalance0,
            poolBalance1,
            swapTarget
          } = await loadFixture(
              poolCaseFixture
          ));

          if (i > 0) {
            eventToken0 = token0_223;
            eventToken1 = token1_223;
            swapTargetAddress = wallet.address;
            walletTarget = wallet.address;
            // poolTarget = swapTarget.target.toString();
            // poolTarget = pool.target.toString();
          } else {
            eventToken0 = token0;
            eventToken1 = token1;
            walletTarget = wallet.address;
            swapTargetAddress = swapTarget.target.toString();
            // poolTarget = pool.target.toString();
          }

          // console.log(`pool: ${pool.target}`);
          // console.log(`swapHelper: ${swapTarget.target}`);
          // console.log(`wallet: ${wallet.address}`);
          // console.log(`token0: ${token0.target}`);
          // console.log(`token1: ${token1.target}`);
          // console.log(`token0_223 ${token0_223.target}`);
          // console.log(`token1_223 ${token1_223.target}`);
        })

        if (i > 0) {
          tokenOut0_223 = true;
          tokenOut1_223 = true;
          swapErc223 = true;
          eventName = 'Transfer(address,address,uint256)';
        }

        afterEach('check can burn positions', async () => {
          for (const {liquidity, tickUpper, tickLower} of poolCase.positions) {
            await pool.burn(tickLower, tickUpper, liquidity)
            // collect in different tokens based on cycle config
            await pool.collect(POSITION_PROCEEDS_OUTPUT_ADDRESS, BigInt(tickLower), BigInt(tickUpper), MaxUint128, MaxUint128, tokenOut0_223, tokenOut1_223);
          }
        })

        for (const testCase of poolCase.swapTests ?? DEFAULT_POOL_SWAP_TESTS) {
          it(swapCaseToDescription(testCase), async () => {
            const slot0 = await pool.slot0()
            // NOTE swapErc223 - to change swap between ERC20 / ERC223 based on cycle config
            const tx = executeSwap(testCase, poolFunctions, swapErc223);

            try {
              const res = await tx;
              if (!res) {
                // NOTE: skipping reverse test
                return;
              }
            } catch (error) {
              expect({
                swapError: (error as any).message,
                poolBalance0: poolBalance0.toString(),
                poolBalance1: poolBalance1.toString(),
                poolPriceBefore: formatPrice(slot0.sqrtPriceX96),
                tickBefore: slot0.tick,
              }).to.matchSnapshot('swap error')
              return
            }
            const [
              token0BalanceAfter,
              token1BalanceAfter,
              token0_223BalanceAfter,
              token1_223BalanceAfter,
              slot0After,
              liquidityAfter,
              feeGrowthGlobal0X128,
              feeGrowthGlobal1X128,
            ] = await Promise.all([
              token0.balanceOf(pool.target),
              token1.balanceOf(pool.target),
              token0_223.balanceOf(pool.target),
              token1_223.balanceOf(pool.target),
              pool.slot0(),
              pool.liquidity(),
              pool.feeGrowthGlobal0X128(),
              pool.feeGrowthGlobal1X128(),
            ])

            const poolBalance0After = token0BalanceAfter + token0_223BalanceAfter;
            const poolBalance1After = token1BalanceAfter + token1_223BalanceAfter;

            const poolBalance0Delta = poolBalance0After - (poolBalance0);
            const poolBalance1Delta = poolBalance1After - (poolBalance1);

            // console.log(`pool balance before 0: ${poolBalance0}`);
            // console.log(`pool balance after 0: ${token0BalanceAfter}`);
            // console.log(`pool balance after 0_223: ${token0_223BalanceAfter}`);
            // console.log(`pool balance before 1: ${poolBalance1}`);
            // console.log(`pool balance after 1: ${token1BalanceAfter}`);
            // console.log(`pool balance after 1_223: ${token1_223BalanceAfter}`);

            // check all the events were emitted corresponding to balance changes
            if (poolBalance0Delta === 0n) {
              if (i > 0) {
                // in ERC223 still exists transfer event (at least back transfer of unspent value)
              } else {
                await expect(tx).to.not.emit(eventToken0, eventName);
              }
            } else if (poolBalance0Delta < 0n)
              await expect(tx)
                  .to.emit(eventToken0, eventName)
                  .withArgs(pool.target, SWAP_RECIPIENT_ADDRESS, poolBalance0Delta * (-1n))
            else {
              if (i > 0) {
                // in ERC223 will be no such event
              } else {
                await expect(tx).to.emit(eventToken0, eventName).withArgs(walletTarget, pool.target, poolBalance0Delta);
              }
            }

            if (poolBalance1Delta === 0n) {
              if (i > 0) {
                // in ERC223 still exists transfer event (at least back transfer of unspent value)
              } else {
                await expect(tx).to.not.emit(eventToken1, eventName);
              }
            } else if (poolBalance1Delta < 0n)
              await expect(tx)
                  .to.emit(eventToken1, eventName)
                  .withArgs(pool.target, SWAP_RECIPIENT_ADDRESS, poolBalance1Delta * (-1n))
            else {
              if (i > 0) {
                // in ERC223 will be no such event
              } else {
                await expect(tx).to.emit(eventToken1, eventName).withArgs(walletTarget, pool.target, poolBalance1Delta);
              }
            }

            // check that the swap event was emitted too
            await expect(tx)
                .to.emit(pool, 'Swap')
                .withArgs(
                    swapTargetAddress,
                    SWAP_RECIPIENT_ADDRESS,
                    poolBalance0Delta,
                    poolBalance1Delta,
                    slot0After.sqrtPriceX96,
                    liquidityAfter,
                    slot0After.tick
                )

            const executionPrice = new Decimal(poolBalance1Delta.toString()).div(poolBalance0Delta.toString()).mul(-1)

            expect({
              amount0Before: poolBalance0.toString(),
              amount1Before: poolBalance1.toString(),
              amount0Delta: poolBalance0Delta.toString(),
              amount1Delta: poolBalance1Delta.toString(),
              feeGrowthGlobal0X128Delta: feeGrowthGlobal0X128.toString(),
              feeGrowthGlobal1X128Delta: feeGrowthGlobal1X128.toString(),
              tickBefore: slot0.tick,
              poolPriceBefore: formatPrice(slot0.sqrtPriceX96),
              tickAfter: slot0After.tick,
              poolPriceAfter: formatPrice(slot0After.sqrtPriceX96),
              executionPrice: executionPrice.toPrecision(5),
            }).to.matchSnapshot('balances')
          })
        }
      })
    }
    })
  }


})
