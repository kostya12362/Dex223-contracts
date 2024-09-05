// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;

import '../interfaces/IERC20Minimal.sol';

import '../interfaces/callback/IUniswapV3SwapCallback.sol';
import '../interfaces/IUniswapV3Pool.sol';

interface IDex223Pool {
    function token0() external view returns (address, address);
    function token1() external view returns (address, address);
}

contract TestUniswapV3SwapPay is IUniswapV3SwapCallback {
    function swap(
        address pool,
        address recipient,
        bool zeroForOne,
        uint160 sqrtPriceX96,
        int256 amountSpecified,
        uint256 pay0,
        uint256 pay1
    ) external {
        IUniswapV3Pool(pool).swap(
            recipient,
            zeroForOne,
            amountSpecified,
            sqrtPriceX96,
            false, // TODO add same calls with bool prefer223 = true
            abi.encode(msg.sender, pay0, pay1)
        );
    }

    function uniswapV3SwapCallback(
        int256,
        int256,
        bytes calldata data
    ) external override {
        (address sender, uint256 pay0, uint256 pay1) = abi.decode(data, (address, uint256, uint256));

        if (pay0 > 0) {
            (address _token0_erc20, address _token0_erc223) = IDex223Pool(msg.sender).token0();
            IERC20Minimal(_token0_erc20).transferFrom(sender, msg.sender, uint256(pay0));
        } else if (pay1 > 0) {
            (address _token1_erc20, address _token1_erc223) = IDex223Pool(msg.sender).token1();
            IERC20Minimal(_token1_erc20).transferFrom(sender, msg.sender, uint256(pay1));
        }
    }
}
