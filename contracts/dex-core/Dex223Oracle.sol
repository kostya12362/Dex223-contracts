// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.7.6;

import "./interfaces/IUniswapV3Pool.sol";

interface IUniswapV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

interface IDex223PoolQuotable
{
    function quoteSwap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bool prefer223,
        bytes memory data
    ) external returns (int256 delta);
}

contract Oracle {
    uint256 public pricePrecisionDecimals = 5;

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
    /*
    function getAmountOut(
        //address poolAddress,
        address sell,
        address buy,
        uint256 quantity
    ) public returns(uint256 amountForBuy) {
        (address poolAddress,,) = findPoolWithHighestLiquidity(buy, sell);
        
        uint256 result = uint256(-(IDex223Pool(poolAddress).quoteSwap(
            address(this),
            sell < buy,
            int256(quantity),
            0,
            false,
            ""
        )));
    }
    */
        // out = buy, in = sell
    function getAmountOutIntrospection(
        address buy,
        address sell,
        uint256 amountToSell
    ) public view returns(uint256 amountBought, uint256 _slashed_zeros, uint256 _tmp_sum) {
        (address _pool, uint128 liquidity, uint24 fee) = findPoolWithHighestLiquidity(buy, sell);

        //amountBought = uint256(getSqrtPriceX96(_pool))**2 * amountToSell / 2**192;  <<< This is a true formula

        uint256 slashed_zeros;
        uint256 tmp_sum;
        if(amountToSell > 10**pricePrecisionDecimals)
        {
            // Slash *precision* decimals and calculate the prices
            // based on the leftmost digits.
            uint256 sum = amountToSell;
            // for (int i=0, i<10, i++)
            //      do
            /*
            for (_calculatedPrecision = 0; sum != 0; _calculatedPrecision++)
            {
                sum = sum / 10;
            }
            amountToSell = amountToSell / 10**(_calculatedPrecision - pricePrecisionDecimals); // Expose only the first 5 digits to the calculations

            amountBought = (uint256(getSqrtPriceX96(_pool))**2 * amountToSell / 2**192) * 10**(_calculatedPrecision - pricePrecisionDecimals);
            */
            for (slashed_zeros = 0; sum > 10**pricePrecisionDecimals; slashed_zeros++)
            {
                sum = sum / 10;
            }

            amountBought = sum;
            tmp_sum = sum;
            amountBought = uint256(getSqrtPriceX96(_pool))**2 * sum / 2**192;
            amountBought = amountBought * 10**slashed_zeros;
        }
        else
        {
            amountBought = uint256(getSqrtPriceX96(_pool))**2 * amountToSell / 2**192;
        }

        if(sell > buy)
        {
            amountBought = amountToSell * amountToSell / amountBought;
        }
        return (amountBought, slashed_zeros, tmp_sum); // Slashes down decimals significantly but provides rough price prediction.
    }

    function getAmountOut(
        address buy,
        address sell,
        uint256 amountToSell
    ) public view returns(uint256 amountBought) {
        (address _pool, uint128 liquidity, uint24 fee) = findPoolWithHighestLiquidity(buy, sell);

        //amountBought = uint256(getSqrtPriceX96(_pool))**2 * amountToSell / 2**192;  <<< This is a true formula

        uint256 slashed_zeros;
        if(amountToSell > 10**pricePrecisionDecimals)
        {
            // Slash *precision* decimals and calculate the prices
            // based on the leftmost digits.
            uint256 sum = amountToSell;
            // for (int i=0, i<10, i++)
            //      do
            /*
            for (_calculatedPrecision = 0; sum != 0; _calculatedPrecision++)
            {
                sum = sum / 10;
            }
            amountToSell = amountToSell / 10**(_calculatedPrecision - pricePrecisionDecimals); // Expose only the first 5 digits to the calculations

            amountBought = (uint256(getSqrtPriceX96(_pool))**2 * amountToSell / 2**192) * 10**(_calculatedPrecision - pricePrecisionDecimals);
            */
            for (slashed_zeros = 0; sum > 10**pricePrecisionDecimals; slashed_zeros++)
            {
                sum = sum / 10;
            }
            amountBought = uint256(getSqrtPriceX96(_pool))**2 * sum / 2**192;
            amountBought = amountBought * 10**slashed_zeros;
        }
        else
        {
            amountBought = uint256(getSqrtPriceX96(_pool))**2 * amountToSell / 2**192;
        }

        if(sell > buy)
        {
            amountBought = amountToSell * amountToSell / amountBought;
        }
        return (amountBought); // Slashes down decimals significantly but provides rough price prediction.
    }

    IUniswapV3Factory public factory;

    uint24[] public feeTiers = [500, 3000, 10000];

    constructor (address _factory) {
        factory = IUniswapV3Factory(_factory);
    }

    function findPoolWithHighestLiquidity(
        address tokenA,
        address tokenB
    ) public view returns (address poolAddress, uint128 liquidity, uint24 fee) {
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
