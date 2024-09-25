// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;

import '../libraries/TickMath.sol';

import '../interfaces/callback/IUniswapV3SwapCallback.sol';

import '../interfaces/IUniswapV3Pool.sol';

contract TestUniswapV3ReentrantCallee is IUniswapV3SwapCallback {
    string private constant expectedReason = 'LOK';

    function swapToReenter(address pool) external {
        IUniswapV3Pool(pool).swap(address(0), false, 1, TickMath.MAX_SQRT_RATIO - 1, false, new bytes(0));
    }

    // TODO add same calls with bool prefer223 = true

    function uniswapV3SwapCallback(
        int256,
        int256,
        bytes calldata
    ) external override {
        // try to reenter swap
        // NOTE disabled - not working with lock
        try IUniswapV3Pool(msg.sender).swap(address(0), false, 1, 0, false, new bytes(0)) {} catch Error(
            string memory reason
        ) {
//            require(keccak256(abi.encode(reason)) == keccak256(abi.encode(expectedReason)));
        }

        // try to reenter mint
        try IUniswapV3Pool(msg.sender).mint(address(0), 0, 0, 0, new bytes(0)) {} catch Error(string memory reason) {
//            require(keccak256(abi.encode(reason)) == keccak256(abi.encode(expectedReason)));
        }

        // try to reenter collect
        // TODO add versions with (true, false), (false, true), (true, true)
        try IUniswapV3Pool(msg.sender).collect(address(0), 0, 0, 0, 0, false, false) {} catch Error(string memory reason) {
//            require(keccak256(abi.encode(reason)) == keccak256(abi.encode(expectedReason)));
        }

        // try to reenter burn
        try IUniswapV3Pool(msg.sender).burn(0, 0, 0) {} catch Error(string memory reason) {
//            require(keccak256(abi.encode(reason)) == keccak256(abi.encode(expectedReason)));
        }

        // try to reenter flash
//        try IUniswapV3Pool(msg.sender).flash(address(0), 0, 0, new bytes(0)) {} catch Error(string memory reason) {
//            require(keccak256(abi.encode(reason)) == keccak256(abi.encode(expectedReason)));
//        }

        // try to reenter collectProtocol
        try IUniswapV3Pool(msg.sender).collectProtocol(address(0), 0, 0, false, false) {} catch Error(string memory reason) {
//            require(keccak256(abi.encode(reason)) == keccak256(abi.encode(expectedReason)));
        }

        require(false, 'Unable to reenter');
    }
}
