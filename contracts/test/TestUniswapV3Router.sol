// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;

import '../libraries/SafeCast.sol';
import '../libraries/TickMath.sol';

import '../interfaces/IERC20Minimal.sol';
import '../interfaces/callback/IUniswapV3SwapCallback.sol';
import '../interfaces/IUniswapV3Pool.sol';

interface IDex223Pool {
    function token0() external view returns (address, address);
    function token1() external view returns (address, address);
}

contract TestUniswapV3Router is IUniswapV3SwapCallback {
    using SafeCast for uint256;

    // flash swaps for an exact amount of token0 in the output pool
    function swapForExact0Multi(
        address recipient,
        address poolInput,
        address poolOutput,
        uint256 amount0Out
    ) external {
        address[] memory pools = new address[](1);
        pools[0] = poolInput;
        IUniswapV3Pool(poolOutput).swap(
            recipient,
            false,
            -amount0Out.toInt256(),
            TickMath.MAX_SQRT_RATIO - 1,
            false,  
            abi.encode(pools, msg.sender)
        );
    }

    // flash swaps for an exact amount of token1 in the output pool
    function swapForExact1Multi(
        address recipient,
        address poolInput,
        address poolOutput,
        uint256 amount1Out
    ) external {
        address[] memory pools = new address[](1);
        pools[0] = poolInput;
        IUniswapV3Pool(poolOutput).swap(
            recipient,
            true,
            -amount1Out.toInt256(),
            TickMath.MIN_SQRT_RATIO + 1,
            false,  
            abi.encode(pools, msg.sender)
        );
    }

    event SwapCallback(int256 amount0Delta, int256 amount1Delta);

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) public override {
        emit SwapCallback(amount0Delta, amount1Delta);

        (address[] memory pools, address payer) = abi.decode(data, (address[], address));

        (address _token0_erc20, address _token0_erc223) = IDex223Pool(msg.sender).token0();
        (address _token1_erc20, address _token1_erc223) = IDex223Pool(msg.sender).token1();

        if (pools.length == 1) {
            // get the address and amount of the token that we need to pay
            address tokenToBePaid =
                amount0Delta > 0 ? _token0_erc20 : _token1_erc20;
            int256 amountToBePaid = amount0Delta > 0 ? amount0Delta : amount1Delta;

            (address _token1_0_erc20, address _token1_0_erc223) = IDex223Pool(pools[0]).token1();
            bool zeroForOne = tokenToBePaid == _token1_0_erc20;
            bytes memory encoded = abi.encode(new address[](0), payer);
            IUniswapV3Pool(pools[0]).swap(
                msg.sender,
                zeroForOne,
                -amountToBePaid,
                zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
                false,  
                encoded
            );
        } else {
            if (amount0Delta > 0) {
                IERC20Minimal(_token0_erc20).transferFrom(
                    payer,
                    msg.sender,
                    uint256(amount0Delta)
                );
            } else {
                IERC20Minimal(_token1_erc20).transferFrom(
                    payer,
                    msg.sender,
                    uint256(amount1Delta)
                );
            }
        }
    }
}
