import { Wallet } from 'ethers'
import { ethers } from 'hardhat'
import {ERC223HybridToken, TestERC20, TokenStandardConverter} from '../typechain-types/'
import { Dex223Factory } from '../typechain-types/'
import { MockTimeDex223Pool } from '../typechain-types/'
import { expect } from 'chai'

import { poolFixture } from './shared/fixtures'

import {
  FeeAmount,
  TICK_SPACINGS,
  createPoolFunctions,
  PoolFunctions,
  createMultiPoolFunctions,
  encodePriceSqrt,
  getMinTick,
  getMaxTick,
  expandTo18Decimals,
} from './shared/utilities'
import { TestUniswapV3Router } from '../typechain-types/'
import { TestUniswapV3Callee } from '../typechain-types/'
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";

const feeAmount = FeeAmount.MEDIUM;
const tickSpacing = TICK_SPACINGS[feeAmount];

// const createFixtureLoader = waffle.createFixtureLoader

type ThenArg<T> = T extends PromiseLike<infer U> ? U : T;

describe('UniswapV3Router', () => {
  let wallet: Wallet, other: Wallet

  let token0: TestERC20
  let token1: TestERC20
  let token2: TestERC20
  let factory: Dex223Factory
  let converter: TokenStandardConverter
  let pool0: MockTimeDex223Pool
  let pool1: MockTimeDex223Pool

  let pool0Functions: PoolFunctions
  let pool1Functions: PoolFunctions

  let minTick: bigint
  let maxTick: bigint

  let swapTargetCallee: TestUniswapV3Callee
  let swapTargetRouter: TestUniswapV3Router

  let createPool: ThenArg<ReturnType<typeof poolFixture>>['createPool'];

  before('create fixture loader', async () => {
    [wallet, other] = await (ethers as any).getSigners();
  });

  beforeEach('deploy first fixture', async () => {
    ({ token0, token1, token2, factory, converter, createPool, swapTargetCallee, swapTargetRouter }
        = await loadFixture( poolFixture ));

    const createPoolWrapped = async (
      amount: number,
      spacing: number,
      firstToken: TestERC20,
      secondToken: TestERC20,
      thirdToken: ERC223HybridToken,
      fourthToken: ERC223HybridToken
    ): Promise<[MockTimeDex223Pool, any]> => {
      const pool = await createPool(amount, spacing, firstToken, secondToken)
      const poolFunctions = createPoolFunctions({
        swapTarget: swapTargetCallee,
        token0: firstToken,
        token1: secondToken,
        token0_223: thirdToken,
        token1_223: fourthToken,
        pool,
      })
      minTick = getMinTick(spacing)
      maxTick = getMaxTick(spacing)
      return [pool, poolFunctions]
    }

    await token0.approve(converter.target.toString(), ethers.MaxUint256 / 2n);
    await token1.approve(converter.target.toString(), ethers.MaxUint256 / 2n);
    await token2.approve(converter.target.toString(), ethers.MaxUint256 / 2n);

    await converter.wrapERC20toERC223(token0.target, ethers.MaxUint256 / 2n);
    await converter.wrapERC20toERC223(token1.target, ethers.MaxUint256 / 2n);
    await converter.wrapERC20toERC223(token2.target, ethers.MaxUint256 / 2n);

    const TokenFactory = await ethers.getContractFactory('ERC223HybridToken');
    let tokenAddress = await converter.predictWrapperAddress(token0.target, true);
    const token0_223 = TokenFactory.attach(tokenAddress) as ERC223HybridToken;
    tokenAddress = await converter.predictWrapperAddress(token1.target, true);
    const token1_223 = TokenFactory.attach(tokenAddress) as ERC223HybridToken;
    tokenAddress = await converter.predictWrapperAddress(token2.target, true);
    const token2_223 = TokenFactory.attach(tokenAddress) as ERC223HybridToken;

    // default to the 30 bips pool
    [pool0, pool0Functions] = await createPoolWrapped(feeAmount, tickSpacing, token0, token1, token0_223, token1_223);
    [pool1, pool1Functions] = await createPoolWrapped(feeAmount, tickSpacing, token1, token2, token1_223, token2_223);
  })

  it('constructor initializes immutables', async () => {
    expect(await pool0.factory()).to.eq(factory.target.toString())
    expect((await pool0.token0())[0]).to.eq(token0.target.toString())
    expect((await pool0.token1())[0]).to.eq(token1.target.toString())
    expect(await pool1.factory()).to.eq(factory.target.toString())
    expect((await pool1.token0())[0]).to.eq(token1.target.toString())
    expect((await pool1.token1())[0]).to.eq(token2.target.toString())
  })

  // NOTE: still no ERC223 version since it not work with exactOutput

  describe('multi-swaps', () => {
    let inputToken: TestERC20
    let outputToken: TestERC20

    beforeEach('initialize both pools', async () => {
      inputToken = token0
      outputToken = token2

      await pool0.initialize(encodePriceSqrt(1n, 1n))
      await pool1.initialize(encodePriceSqrt(1n, 1n))

      await pool0Functions.mint(wallet.address, minTick, maxTick, expandTo18Decimals(1))
      await pool1Functions.mint(wallet.address, minTick, maxTick, expandTo18Decimals(1))
    })

    it('multi-swap', async () => {
      const token0OfPoolOutput = (await pool1.token0())[0]
      const ForExact0 = outputToken.target.toString() === token0OfPoolOutput

      const { swapForExact0Multi, swapForExact1Multi } = createMultiPoolFunctions({
        inputToken: token0,
        swapTarget: swapTargetRouter,
        poolInput: pool0,
        poolOutput: pool1,
      })

      const method = ForExact0 ? swapForExact0Multi : swapForExact1Multi

      await expect(method(100n, wallet.address))
        .to.emit(outputToken, 'Transfer')
        .withArgs(pool1.target.toString(), wallet.address, 100n)
        .to.emit(token1, 'Transfer')
        .withArgs(pool0.target.toString(), pool1.target.toString(), 102n)
        .to.emit(inputToken, 'Transfer')
        .withArgs(wallet.address, pool0.target.toString(), 104n)
    })
  })
})
