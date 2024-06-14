// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

import "./ERC20mod.sol";

contract ERC20Test is ERC20 {
  constructor() ERC20('Test Sep 2', 'TSP2', 6) {}

  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }
}