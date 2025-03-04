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
        
    }
}
