// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IDex223Autolisting {
    event TokenListed(address indexed token_erc20, address indexed token_erc223);
    event PairListed(address indexed token0_erc20, address token0_erc223, address indexed token1_erc20, address token1_erc223, address indexed pool, uint256 feeTier);

    function getFactory() external view returns (address);
    function getRegistry() external view returns (address);
    function getName() external view returns (string memory);
    function getURL() external view returns (string memory);
    function isListed(address _token) external view returns (bool);

    function list(address pool, uint24 feeTier) external;
    function getToken(uint256 index) external view returns (address _erc20, address _erc223);
}
