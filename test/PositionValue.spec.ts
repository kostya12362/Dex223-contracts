import { ethers } from 'hardhat'
import { Contract } from 'ethers'
import {
  PositionValueTest,
  ERC223SwapRouter,
  MockTimeNonfungiblePositionManager,
  TestERC20,
  Dex223Factory, ERC223HybridToken,
} from '../typechain-types/'
import { FeeAmount, MaxUint128, TICK_SPACINGS } from './shared/constants'
import { getMaxTick, getMinTick, encodePriceSqrt, expandTo18Decimals } from './shared/utilities'
import { encodePath } from './shared/path'
import { computePoolAddress } from './shared/computePoolAddress'
import { completeFixture } from './shared/completeFixture'
import snapshotGasCost from './shared/snapshotGasCost'
import { expect, use } from 'chai'
import { jestSnapshotPlugin } from 'mocha-chai-jest-snapshot'
import { abi as IUniswapV3PoolABI } from '../artifacts/contracts/interfaces/IUniswapV3Pool.sol/IUniswapV3Pool.json'
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";

use(jestSnapshotPlugin());

describe('PositionValue', async () => {
  const [owner] = await ethers.getSigners()
  async function positionValueCompleteFixture(): Promise<{
    positionValue: PositionValueTest
    tokens: (TestERC20 | ERC223HybridToken)[]
    nft: MockTimeNonfungiblePositionManager
    router: ERC223SwapRouter
    factory: Dex223Factory
  }> {
    const { nft, router, tokens, factory } = await completeFixture()
    const positionValueFactory = await ethers.getContractFactory('PositionValueTest')
    const positionValue = (await positionValueFactory.deploy()) as PositionValueTest

    for (let i = 0; i < 3; i++) {
      const token = tokens[i] as TestERC20;
      await token.approve(nft.target.toString(), ethers.MaxUint256)
      await token.connect(owner).approve(nft.target.toString(), ethers.MaxUint256)
      await token.transfer(owner.address, expandTo18Decimals(1000000))
    }

    return {
      positionValue,
      tokens,
      nft,
      router,
      factory,
    }
  }

  let pool: Contract
  let tokens: (TestERC20 | ERC223HybridToken)[]
  let positionValue: PositionValueTest
  let nft: MockTimeNonfungiblePositionManager
  let router: ERC223SwapRouter
  let factory: Dex223Factory
  let amountDesired: bigint

  beforeEach(async () => {
    ;({ positionValue, tokens, nft, router, factory } = await loadFixture(positionValueCompleteFixture))
    await nft.createAndInitializePoolIfNecessary(
      tokens[0].target.toString(),
      tokens[1].target.toString(),
      tokens[3].target.toString(),
      tokens[4].target.toString(),
      FeeAmount.MEDIUM,
      encodePriceSqrt(1n, 1n)
    )

    const poolAddress = computePoolAddress(factory.target.toString(), [tokens[0].target.toString(),
      tokens[1].target.toString()], FeeAmount.MEDIUM)
    pool = new ethers.Contract(poolAddress, IUniswapV3PoolABI, ethers.provider)
  })

  describe('#total', () => {
    let tokenId: number
    let sqrtRatioX96: bigint

    beforeEach(async () => {
      amountDesired = expandTo18Decimals(100000)

      await nft.mint({
        token0: tokens[0].target.toString(),
        token1: tokens[1].target.toString(),
        tickLower: getMinTick(TICK_SPACINGS[FeeAmount.MEDIUM]),
        tickUpper: getMaxTick(TICK_SPACINGS[FeeAmount.MEDIUM]),
        fee: FeeAmount.MEDIUM,
        recipient: owner.address,
        amount0Desired: amountDesired,
        amount1Desired: amountDesired,
        amount0Min: 0,
        amount1Min: 0,
        deadline: 10,
      })

      const swapAmount = expandTo18Decimals(1000)
      await tokens[0].approve(router.target.toString(), swapAmount)
      await tokens[1].approve(router.target.toString(), swapAmount)

      // accmuluate token0 fees
      await router.exactInput({
        recipient: owner.address,
        deadline: 1,
        path: encodePath([tokens[0].target.toString(), tokens[1].target.toString()], [FeeAmount.MEDIUM]),
        amountIn: swapAmount,
        amountOutMinimum: 0,
        prefer223Out: false
      })

      // accmuluate token1 fees
      await router.exactInput({
        recipient: owner.address,
        deadline: 1,
        path: encodePath([tokens[1].target.toString(), tokens[0].target.toString()], [FeeAmount.MEDIUM]),
        amountIn: swapAmount,
        amountOutMinimum: 0,
        prefer223Out: false
      })

      sqrtRatioX96 = (await pool.slot0()).sqrtPriceX96
    })

    it('returns the correct amount', async () => {
      const principal = await positionValue.principal(nft.target.toString(), 1, sqrtRatioX96)
      const fees = await positionValue.fees(nft.target.toString(), 1)
      const total = await positionValue.total(nft.target.toString(), 1, sqrtRatioX96)

      expect(total[0]).to.equal(principal[0] + fees[0])
      expect(total[1]).to.equal(principal[1] + fees[1])
    })

    it('gas', async () => {
      await snapshotGasCost(positionValue.totalGas(nft.target.toString(), 1, sqrtRatioX96))
    })
  })

  describe('#principal', () => {
    let sqrtRatioX96: bigint

    beforeEach(async () => {
      amountDesired = expandTo18Decimals(100000)
      sqrtRatioX96 = (await pool.slot0()).sqrtPriceX96
    })

    it('returns the correct values when price is in the middle of the range', async () => {
      await nft.mint({
        token0: tokens[0].target.toString(),
        token1: tokens[1].target.toString(),
        tickLower: getMinTick(TICK_SPACINGS[FeeAmount.MEDIUM]),
        tickUpper: getMaxTick(TICK_SPACINGS[FeeAmount.MEDIUM]),
        fee: FeeAmount.MEDIUM,
        recipient: owner.address,
        amount0Desired: amountDesired,
        amount1Desired: amountDesired,
        amount0Min: 0,
        amount1Min: 0,
        deadline: 10,
      })

      const principal = await positionValue.principal(nft.target.toString(), 1, sqrtRatioX96)
      expect(principal.amount0).to.equal('99999999999999999999999')
      expect(principal.amount1).to.equal('99999999999999999999999')
    })

    it('returns the correct values when range is below current price', async () => {
      await nft.mint({
        token0: tokens[0].target.toString(),
        token1: tokens[1].target.toString(),
        tickLower: getMinTick(TICK_SPACINGS[FeeAmount.MEDIUM]),
        tickUpper: -60,
        fee: FeeAmount.MEDIUM,
        recipient: owner.address,
        amount0Desired: amountDesired,
        amount1Desired: amountDesired,
        amount0Min: 0,
        amount1Min: 0,
        deadline: 10,
      })

      const principal = await positionValue.principal(nft.target.toString(), 1, sqrtRatioX96)
      expect(principal.amount0).to.equal('0')
      expect(principal.amount1).to.equal('99999999999999999999999')
    })

    it('returns the correct values when range is below current price', async () => {
      await nft.mint({
        token0: tokens[0].target.toString(),
        token1: tokens[1].target.toString(),
        tickLower: 60,
        tickUpper: getMaxTick(TICK_SPACINGS[FeeAmount.MEDIUM]),
        fee: FeeAmount.MEDIUM,
        recipient: owner.address,
        amount0Desired: amountDesired,
        amount1Desired: amountDesired,
        amount0Min: 0,
        amount1Min: 0,
        deadline: 10,
      })

      const principal = await positionValue.principal(nft.target.toString(), 1, sqrtRatioX96)
      expect(principal.amount0).to.equal('99999999999999999999999')
      expect(principal.amount1).to.equal('0')
    })

    it('returns the correct values when range is skewed above price', async () => {
      await nft.mint({
        token0: tokens[0].target.toString(),
        token1: tokens[1].target.toString(),
        tickLower: -6000,
        tickUpper: getMaxTick(TICK_SPACINGS[FeeAmount.MEDIUM]),
        fee: FeeAmount.MEDIUM,
        recipient: owner.address,
        amount0Desired: amountDesired,
        amount1Desired: amountDesired,
        amount0Min: 0,
        amount1Min: 0,
        deadline: 10,
      })

      const principal = await positionValue.principal(nft.target.toString(), 1, sqrtRatioX96)
      expect(principal.amount0).to.equal('99999999999999999999999')
      expect(principal.amount1).to.equal('25917066770240321655335')
    })

    it('returns the correct values when range is skewed below price', async () => {
      await nft.mint({
        token0: tokens[0].target.toString(),
        token1: tokens[1].target.toString(),
        tickLower: getMinTick(TICK_SPACINGS[FeeAmount.MEDIUM]),
        tickUpper: 6000,
        fee: FeeAmount.MEDIUM,
        recipient: owner.address,
        amount0Desired: amountDesired,
        amount1Desired: amountDesired,
        amount0Min: 0,
        amount1Min: 0,
        deadline: 10,
      })

      const principal = await positionValue.principal(nft.target.toString(), 1, sqrtRatioX96)
      expect(principal.amount0).to.equal('25917066770240321655335')
      expect(principal.amount1).to.equal('99999999999999999999999')
    })

    it('gas', async () => {
      await nft.mint({
        token0: tokens[0].target.toString(),
        token1: tokens[1].target.toString(),
        tickLower: getMinTick(TICK_SPACINGS[FeeAmount.MEDIUM]),
        tickUpper: getMaxTick(TICK_SPACINGS[FeeAmount.MEDIUM]),
        fee: FeeAmount.MEDIUM,
        recipient: owner.address,
        amount0Desired: amountDesired,
        amount1Desired: amountDesired,
        amount0Min: 0,
        amount1Min: 0,
        deadline: 10,
      })

      await snapshotGasCost(positionValue.principalGas(nft.target.toString(), 1, sqrtRatioX96))
    })
  })

  describe('#fees', () => {
    let tokenId: number

    beforeEach(async () => {
      amountDesired = expandTo18Decimals(100_000)
      tokenId = 2

      await nft.mint({
        token0: tokens[0].target.toString(),
        token1: tokens[1].target.toString(),
        tickLower: getMinTick(TICK_SPACINGS[FeeAmount.MEDIUM]),
        tickUpper: getMaxTick(TICK_SPACINGS[FeeAmount.MEDIUM]),
        fee: FeeAmount.MEDIUM,
        recipient: owner.address,
        amount0Desired: amountDesired,
        amount1Desired: amountDesired,
        amount0Min: 0,
        amount1Min: 0,
        deadline: 10,
      })
    })

    describe('when price is within the position range', () => {
      beforeEach(async () => {
        await nft.mint({
          token0: tokens[0].target.toString(),
          token1: tokens[1].target.toString(),
          tickLower: TICK_SPACINGS[FeeAmount.MEDIUM] * -1000,
          tickUpper: TICK_SPACINGS[FeeAmount.MEDIUM] * 1000,
          fee: FeeAmount.MEDIUM,
          recipient: owner.address,
          amount0Desired: amountDesired,
          amount1Desired: amountDesired,
          amount0Min: 0,
          amount1Min: 0,
          deadline: 10,
        })

        const swapAmount = expandTo18Decimals(1_000)
        await tokens[0].approve(router.target.toString(), swapAmount)
        await tokens[1].approve(router.target.toString(), swapAmount)

        // accmuluate token0 fees
        await router.exactInput({
          recipient: owner.address,
          deadline: 1,
          path: encodePath([tokens[0].target.toString(), tokens[1].target.toString()], [FeeAmount.MEDIUM]),
          amountIn: swapAmount,
          amountOutMinimum: 0,
          prefer223Out: false
        })

        // accmuluate token1 fees
        await router.exactInput({
          recipient: owner.address,
          deadline: 1,
          path: encodePath([tokens[1].target.toString(), tokens[0].target.toString()], [FeeAmount.MEDIUM]),
          amountIn: swapAmount,
          amountOutMinimum: 0,
          prefer223Out: false
        })
      })

      it('return the correct amount of fees', async () => {
        // TODO add other token Types on output
        const positions = await nft.positions(tokenId);
        const pool = await factory.getPool(positions.token0, positions.token1, positions.fee);
        const feesFromCollect = await nft.collect.staticCall({
          pool,
          tokenId,
          recipient: owner.address,
          amount0Max: MaxUint128,
          amount1Max: MaxUint128,
          tokensOutCode: 0n
        })
        const feeAmounts = await positionValue.fees(nft.target.toString(), tokenId)

        expect(feeAmounts[0]).to.equal(feesFromCollect[0])
        expect(feeAmounts[1]).to.equal(feesFromCollect[1])
      })

      it('returns the correct amount of fees if tokensOwed fields are greater than 0', async () => {
        await nft.increaseLiquidity({
          tokenId: tokenId,
          amount0Desired: 100,
          amount1Desired: 100,
          amount0Min: 0,
          amount1Min: 0,
          deadline: 1,
        })

        const swapAmount = expandTo18Decimals(1_000)
        await tokens[0].approve(router.target.toString(), swapAmount)

        // accmuluate more token0 fees after clearing initial amount
        await router.exactInput({
          recipient: owner.address,
          deadline: 1,
          path: encodePath([tokens[0].target.toString(), tokens[1].target.toString()], [FeeAmount.MEDIUM]),
          amountIn: swapAmount,
          amountOutMinimum: 0,
          prefer223Out: false
        })

        const positions = await nft.positions(tokenId);
        const pool = await factory.getPool(positions.token0, positions.token1, positions.fee);
        const feesFromCollect = await nft.collect.staticCall({
          pool,
          tokenId,
          recipient: owner.address,
          amount0Max: MaxUint128,
          amount1Max: MaxUint128,
          tokensOutCode: 0n
        })
        const feeAmounts = await positionValue.fees(nft.target.toString(), tokenId)
        expect(feeAmounts[0]).to.equal(feesFromCollect[0])
        expect(feeAmounts[1]).to.equal(feesFromCollect[1])
      })

      it('gas', async () => {
        await snapshotGasCost(positionValue.feesGas(nft.target.toString(), tokenId))
      })
    })

    describe('when price is below the position range', async () => {
      beforeEach(async () => {
        await nft.mint({
          token0: tokens[0].target.toString(),
          token1: tokens[1].target.toString(),
          tickLower: TICK_SPACINGS[FeeAmount.MEDIUM] * -10,
          tickUpper: TICK_SPACINGS[FeeAmount.MEDIUM] * 10,
          fee: FeeAmount.MEDIUM,
          recipient: owner.address,
          amount0Desired: expandTo18Decimals(10_000),
          amount1Desired: expandTo18Decimals(10_000),
          amount0Min: 0,
          amount1Min: 0,
          deadline: 10,
        })

        await tokens[0].approve(router.target.toString(), ethers.MaxUint256)
        await tokens[1].approve(router.target.toString(), ethers.MaxUint256)

        // accumulate token1 fees
        await router.exactInput({
          recipient: owner.address,
          deadline: 1,
          path: encodePath([tokens[1].target.toString(), tokens[0].target.toString()], [FeeAmount.MEDIUM]),
          amountIn: expandTo18Decimals(1000),
          amountOutMinimum: 0,
          prefer223Out: false
        })

        // accumulate token0 fees and push price below tickLower
        await router.exactInput({
          recipient: owner.address,
          deadline: 1,
          path: encodePath([tokens[0].target.toString(), tokens[1].target.toString()], [FeeAmount.MEDIUM]),
          amountIn: expandTo18Decimals(50000),
          amountOutMinimum: 0,
          prefer223Out: false
        })
      })

      it('returns the correct amount of fees', async () => {
        const positions = await nft.positions(tokenId);
        const pool = await factory.getPool(positions.token0, positions.token1, positions.fee);
        const feesFromCollect = await nft.collect.staticCall({
          pool,
          tokenId,
          recipient: owner.address,
          amount0Max: MaxUint128,
          amount1Max: MaxUint128,
          tokensOutCode: 0n
        })

        const feeAmounts = await positionValue.fees(nft.target.toString(), tokenId)
        expect(feeAmounts[0]).to.equal(feesFromCollect[0])
        expect(feeAmounts[1]).to.equal(feesFromCollect[1])
      })

      it('gas', async () => {
        await snapshotGasCost(positionValue.feesGas(nft.target.toString(), tokenId))
      })
    })

    describe('when price is above the position range', async () => {
      beforeEach(async () => {
        await nft.mint({
          token0: tokens[0].target.toString(),
          token1: tokens[1].target.toString(),
          tickLower: TICK_SPACINGS[FeeAmount.MEDIUM] * -10,
          tickUpper: TICK_SPACINGS[FeeAmount.MEDIUM] * 10,
          fee: FeeAmount.MEDIUM,
          recipient: owner.address,
          amount0Desired: expandTo18Decimals(10_000),
          amount1Desired: expandTo18Decimals(10_000),
          amount0Min: 0,
          amount1Min: 0,
          deadline: 10,
        })

        await tokens[0].approve(router.target.toString(), ethers.MaxUint256)
        await tokens[1].approve(router.target.toString(), ethers.MaxUint256)

        // accumulate token0 fees
        await router.exactInput({
          recipient: owner.address,
          deadline: 1,
          path: encodePath([tokens[0].target.toString(), tokens[1].target.toString()], [FeeAmount.MEDIUM]),
          amountIn: expandTo18Decimals(1_000),
          amountOutMinimum: 0,
          prefer223Out: false
        })

        // accumulate token1 fees and push price above tickUpper
        await router.exactInput({
          recipient: owner.address,
          deadline: 1,
          path: encodePath([tokens[1].target.toString(), tokens[0].target.toString()], [FeeAmount.MEDIUM]),
          amountIn: expandTo18Decimals(50_000),
          amountOutMinimum: 0,
          prefer223Out: false
        })
      })

      it('returns the correct amount of fees', async () => {
        const positions = await nft.positions(tokenId);
        const pool = await factory.getPool(positions.token0, positions.token1, positions.fee);
        const feesFromCollect = await nft.collect.staticCall({
          pool,
          tokenId,
          recipient: owner.address,
          amount0Max: MaxUint128,
          amount1Max: MaxUint128,
          tokensOutCode: 0n
        })
        const feeAmounts = await positionValue.fees(nft.target.toString(), tokenId)
        expect(feeAmounts[0]).to.equal(feesFromCollect[0])
        expect(feeAmounts[1]).to.equal(feesFromCollect[1])
      })

      it('gas', async () => {
        await snapshotGasCost(positionValue.feesGas(nft.target.toString(), tokenId))
      })
    })
  })
})
