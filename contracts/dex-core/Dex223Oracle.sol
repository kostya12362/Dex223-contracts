// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.7.6;

import "./interfaces/IUniswapV3Pool.sol";

interface IUniswapV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

contract Oracle {

    function getSqrtPriceX96(address poolAddress) public view returns(uint160 sqrtPriceX96) {
        IUniswapV3Pool pool;
        pool = IUniswapV3Pool(poolAddress);
        (sqrtPriceX96,,,,,,) = pool.slot0();
        return sqrtPriceX96;
    }

    function getSpotPriceTick(address poolAddress) public view returns(int24 tick) {
        IUniswapV3Pool pool;
        pool = IUniswapV3Pool(poolAddress);
        (, tick,,,,,) = pool.slot0();
        return tick;
    }

    // sell token1, buy token0
    function getPrice(address poolAddress, address buy, address sell) public view returns(uint256, bool) {
        uint160 sqrtPriceX96 = getSqrtPriceX96(poolAddress);
        uint256 priceX96 = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);

        // if buy token0 rather than token1,  need to invert the price 
        bool needToInverse = sell < buy;

        return (priceX96, needToInverse);
    }

    // out = buy, in = sell
    function getAmountOut(
        address poolAddress,
        address buy,
        address sell,
        uint256 amountForSell
    ) public view returns(uint256 amountForBuy) {

        (uint256 priceX96, bool needToInverse) = getPrice(poolAddress, buy, sell);

        if (needToInverse) {
            amountForBuy = (amountForSell * priceX96) >> 192;
        } else {
            amountForBuy = (amountForSell << 192) / priceX96;
        }

        return amountForBuy;
    }

    IUniswapV3Factory public immutable factory;

    uint24[] public feeTiers = [500, 3000, 10000];

    constructor (address _factory) {
        factory = IUniswapV3Factory(_factory);
    }

    function findPoolWithHighestLiquidity(
        address tokenA,
        address tokenB
    ) external view returns (address poolAddress, uint128 liquidity, uint24 fee) {
        require(tokenA != tokenB);
        require(tokenA != address(0));

        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);

        for (uint i = 0; i < feeTiers.length; i++) {
            address pool = factory.getPool(token0, token1, feeTiers[i]);
            if (pool != address(0)) {
                uint128 currentLiquidity = IUniswapV3Pool(pool).liquidity();
                if (currentLiquidity >= liquidity) {
                    liquidity = currentLiquidity;
                    poolAddress = pool;
                    fee = feeTiers[i];
                }
            }
        }

        require(poolAddress != address(0));
    }
}
