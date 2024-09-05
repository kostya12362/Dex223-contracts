// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;

import '../interfaces/IERC20Minimal.sol';

import '../interfaces/callback/IUniswapV3SwapCallback.sol';
import '../interfaces/IUniswapV3Pool.sol';


interface IDex223Pool {
    function token0() external view returns (address, address);
    function token1() external view returns (address, address);
}


contract UniswapV3PoolSwapTest is IUniswapV3SwapCallback {
    int256 private _amount0Delta;
    int256 private _amount1Delta;

    function getSwapResult(
        address pool,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    )
        external
        returns (
            int256 amount0Delta,
            int256 amount1Delta,
            uint160 nextSqrtRatio
        )
    {
        (amount0Delta, amount1Delta) = IUniswapV3Pool(pool).swap(
            address(0),
            zeroForOne,
            amountSpecified,
            sqrtPriceLimitX96,
            false,  // TODO add same calls with bool prefer223 = true
            abi.encode(msg.sender)
        );

        (nextSqrtRatio, , , , , , ) = IUniswapV3Pool(pool).slot0();
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external override {
        address sender = abi.decode(data, (address));

        if (amount0Delta > 0) {
            (address _token0_erc20, address _token0_erc223) = IDex223Pool(msg.sender).token0();
            IERC20Minimal(_token0_erc20).transferFrom(sender, msg.sender, uint256(amount0Delta));
        } else if (amount1Delta > 0) {
            (address _token1_erc20, address _token1_erc223) = IDex223Pool(msg.sender).token1();
            IERC20Minimal(_token1_erc20).transferFrom(sender, msg.sender, uint256(amount1Delta));
        }
    }
}
