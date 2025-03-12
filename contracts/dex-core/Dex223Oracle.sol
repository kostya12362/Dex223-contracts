// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "./interfaces/IUniswapV3Pool.sol";

contract Oracle {

    function getSqrtPriceX96(address poolAddress) public view returns(uint160 sqrtPriceX96) {
        IUniswapV3Pool pool;
        pool = IUniswapV3PoolOracle(poolAddress);
        (sqrtPriceX96,,,,,,,) = pool.slot0();
        return sqrtPriceX96;
    }

    function getSpotPriceTick(address poolAddress) public view returns(int24 tick) {
        IUniswapV3Pool pool;
        pool = IUniswapV3PoolOracle(poolAddress);
        (uint160 sqrtPriceX96,, tick,,,,, bool unlocked) = pool.slot0();
        return tick;
    }

    function getPrice() public view returns(uint256 price) {
        int24 tick = getSpotPriceTick();

        int24 absTick = tick >=0 ? tick : -tick;
        uint256 price_ = 10**18;

        for(int24 i = 0; i < absTick; i++) {
            price_ = (price_ * 10001) / 10000;
        }

        if (tick < 0) {
            price = (10**36) / price_;
        } else {
            price = price_;
        }

        return price;
    }
}
