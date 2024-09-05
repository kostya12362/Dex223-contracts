// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;

import '../dex-periphery/interfaces/INonfungiblePositionManager.sol';

contract NonfungiblePositionManagerPositionsGasTest {
    INonfungiblePositionManager immutable private nonfungiblePositionManager;

    constructor(INonfungiblePositionManager _nonfungiblePositionManager) {
        nonfungiblePositionManager = _nonfungiblePositionManager;
    }

    function getGasCostOfPositions(uint256 tokenId) external view returns (uint256) {
        uint256 gasBefore = gasleft();
        nonfungiblePositionManager.positions(tokenId);
        return gasBefore - gasleft();
    }
}
