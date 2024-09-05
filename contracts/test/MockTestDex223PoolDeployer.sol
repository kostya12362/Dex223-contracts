// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;

import '../interfaces/IUniswapV3PoolDeployer.sol';

import './MockTestDex223Pool.sol';

contract MockTestDex223PoolDeployer is IUniswapV3PoolDeployer {
    struct Parameters {
        address factory;
        address token0_erc20;
        address token1_erc20;
        uint24 fee;
        int24 tickSpacing;
    }

    Parameters public override parameters;

    event PoolDeployed(address pool);

    function deploy(
        address factory,
        address token0_erc20,
        address token1_erc20,
        uint24 fee,
        int24 tickSpacing
    ) external returns (address pool) {
        parameters = Parameters({factory: factory, token0_erc20: token0_erc20, token1_erc20: token1_erc20,  fee: fee, tickSpacing: tickSpacing});
        pool = address(new MockTestDex223Pool{salt: keccak256(abi.encode(token0_erc20, token1_erc20, fee))}());
        emit PoolDeployed(pool);
        delete parameters;
    }
}
