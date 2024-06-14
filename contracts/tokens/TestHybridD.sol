pragma solidity >=0.7.0 <0.8.20;

import "./ERC223Hybrid.sol";

/**
 * @title Reference implementation of the ERC223 standard token.
 */
contract ERC223Token is ERC223HybridToken {

    constructor() ERC223HybridToken('Test Token D', 'TTD', 18) {
    }

}