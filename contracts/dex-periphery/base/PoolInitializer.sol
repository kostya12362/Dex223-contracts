// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;

import '../../interfaces/IDex223Factory.sol';
import '../../interfaces/IUniswapV3Pool.sol';

import '../interfaces/IPoolInitializer.sol';
import './PeripheryImmutableState.sol';

/// @title Creates and initializes V3 Pools
abstract contract PoolInitializer is IPoolInitializer, PeripheryImmutableState {
    /// @inheritdoc IPoolInitializer
    function createAndInitializePoolIfNecessary(
        address token0_20,
        address token1_20,
        address token0_223,
        address token1_223,
        uint24 fee,
        uint160 sqrtPriceX96
    ) external payable override returns (address pool) {
        require(token0_20 < token1_20);
        pool = IDex223Factory(factory).getPool(token0_20, token1_20, fee);

        if (pool == address(0)) {
            pool = IDex223Factory(factory).createPool(token0_20, token1_20, token0_223, token1_223, fee);
            IUniswapV3Pool(pool).initialize(sqrtPriceX96);
        } else {
            (uint160 sqrtPriceX96Existing, , , , , , ) = IUniswapV3Pool(pool).slot0();
            if (sqrtPriceX96Existing == 0) {
                IUniswapV3Pool(pool).initialize(sqrtPriceX96);
            }
        }
    }
}
