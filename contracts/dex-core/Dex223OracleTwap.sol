// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

contract Oracle {

    // Returns Time-Weighted Average Price.
    // secondsAgo - The time period in seconds for which we calculate the average price.
    function getTwap(IUniswapV3Pool pool, uint32 secondsAgo) public view returns(uint256 priceX96) {
        require(secondsAgo > 0, "Interval must be > 0");

        uint32[] memory ago = new uint32[](2);
        ago[0] = secondsAgo;
        ago[1] = 0; // now

        (int56[] memory tickCumulatives, ) = pool.observe(ago);

        // calculation of the average tick over a period of time.
        int56 tickDifference = tickCumulatives[1] - tickCumulatives[0];
        int56 averageTick = tickDifference / int56(int32(secondsAgo));

        priceX96 = TickMath.getSqrtRatioAtTick(averageTick);
    }

    function getPrice(uint32 secondsAgo, uint8 decimalsToken0, uint8 decimalsToken1) external view returns (uint256 price) {
        uint256 sqrtPriceX128 = getTwap(secondsAgo);
        uint256 priceX192 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, 1 << 64);

        if (decimalsToken0 >= decimalsToken1) {
            uint256 decimalsFactor = 10 ** (decimalsToken0 - decimalsToken1);
            price = FullMath.mulDiv(priceX192, decimalsFactor, 1 << 128);
        } else {
            uint256 decimalsFactor = 10 ** (decimalsToken1 - decimalsToken0);
            price = FullMath.mulDiv(priceX192, 1, decimalsFactor << 128);
        }
    }
}
