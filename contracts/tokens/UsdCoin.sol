// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

import "./ERC20mod.sol";

contract UsdCoin is ERC20 {
  constructor() ERC20('UsdCoin', 'USDC', 6) {}

  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }
}