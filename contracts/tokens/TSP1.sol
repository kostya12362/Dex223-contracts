// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

import "./ERC20mod.sol";

contract Tether is ERC20 {
  constructor() ERC20('Test Sep 1', 'TSP1', 18) {
  }

  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }

}