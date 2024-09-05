import { Wallet } from 'ethers'
import { ethers } from 'hardhat'
import { AutoListingsRegistry, Dex223AutoListing, TestERC20 } from '../typechain-types/'
import { Dex223Factory } from '../typechain-types/'
import { TokenStandardConverter } from '../typechain-types/'
import { expect } from 'chai'

import { listingFixture } from './shared/fixtures'

import { FeeAmount } from './shared/utilities'
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";

const feeAmount = FeeAmount.MEDIUM

describe('AutoListing', () => {
    let wallet: Wallet, other: Wallet

    let token0: TestERC20
    let token1: TestERC20
    let token2: TestERC20
    let token3: string
    let token4: string
    let token5: string
    let factory: Dex223Factory
    let converter: TokenStandardConverter
    let pool0: string
    let pool1: string

    let registry: AutoListingsRegistry
    let listing: Dex223AutoListing

    before('create fixture loader', async () => {
        ;[wallet, other] = await (ethers as any).getSigners()
    })

    beforeEach('deploy first fixture', async () => {
        ;({ token0, token1, token2, registry, listing, factory, converter } = await loadFixture(listingFixture));

        token3 = await converter.predictWrapperAddress(token0.target, true);
        token4 = await converter.predictWrapperAddress(token1.target, true);
        token5 = await converter.predictWrapperAddress(token2.target, true);

        await factory.createPool(
            token0.target.toString(), token1.target.toString(),
            token3, token4,
            feeAmount
        );

        await factory.createPool(
            token1.target.toString(), token2.target.toString(),
            token4, token5,
            feeAmount
        );

        pool0 = await factory.getPool(token0, token1, feeAmount);
        pool1 = await factory.getPool(token1, token2, feeAmount);

    })

    it('constructor initializes immutables', async () => {
        expect(await listing.getRegistry()).to.eq(registry.target.toString())
        expect(await listing.getFactory()).to.eq(factory.target.toString())
    })

    describe('lists add', () => {

        it('add list', async () => {
            // NOTE list with payment
            await expect(listing.list(pool0, feeAmount, pool0))
                .to.emit(registry, 'TokenListed')
                .withArgs(listing.target.toString(), token0.target.toString(), token3)
                .to.emit(listing, 'TokenListed')
                .to.emit(registry, 'TokenListed')
                .withArgs(listing.target.toString(), token1.target.toString(), token4)
                .to.emit(listing, 'TokenListed')
                .to.emit(listing, 'PairListed')
                .withArgs(token0.target.toString(), token3, token1.target.toString(), token4, pool0, feeAmount);

            expect(await listing.name()).to.eq('AutoTest listing');
            expect(await listing.url()).to.eq('none');
            expect(await listing.isListed(token0.target.toString())).to.eq(true);
            expect(await listing.isListed(token1.target.toString())).to.eq(true);

            expect(await listing.isListed(token2.target.toString())).not.to.eq(true);
            expect(await listing.isListed(token5)).not.to.eq(true);

            await expect(listing.list(pool0, feeAmount, pool0 ))
                .not.to.emit(registry, 'TokenListed')
                .not.to.emit(listing, 'TokenListed')
                .not.to.emit(listing, 'TokenListed');
                // .withArgs(pool1.target.toString(), wallet.address, 100n)

            await expect(listing.list(pool1, feeAmount, pool1))
                .to.emit(registry, 'TokenListed')
                .to.emit(listing, 'TokenListed')
                .to.emit(listing, 'PairListed');

            expect(await listing.isListed(token0.target.toString())).to.eq(true);
            expect(await listing.isListed(token1.target.toString())).to.eq(true);
            expect(await listing.isListed(token2.target.toString())).to.eq(true);
            expect(await listing.isListed(token3)).to.eq(true);
            expect(await listing.isListed(token4)).to.eq(true);
            expect(await listing.isListed(token5)).to.eq(true);

            expect(await listing.getToken(1)).to.deep.eq([token0.target.toString(), token3]);
            expect(await listing.getToken(2)).to.deep.eq([token1.target.toString(), token4]);
            expect(await listing.getToken(3)).to.deep.eq([token2.target.toString(), token5]);

        })

    })
})
