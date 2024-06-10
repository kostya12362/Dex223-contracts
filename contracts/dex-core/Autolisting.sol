// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

//import './interfaces/IUniswapV3Pool.sol';
import './interfaces/IDex223Factory.sol';

contract IDexPool
{
    struct Token
    {
        address erc20;
        address erc223;
    }

    Token public token0;
    Token public token1;
}

contract Dex223AutoListing {
    IDex223Factory factory;

    constructor(address _factory)
    {
        factory = IDex223Factory(_factory);
    }

    struct Token
    {
        address erc20;
        address erc223;
    }

    mapping(address => bool)  public listed_tokens;
    mapping(uint256 => Token) public tokens;

    event TokenListed(address indexed token_erc20, address indexed token_erc223);
    event PairListed(address indexed token0_erc20, address token0_erc223, address indexed token1_erc20, address token1_erc223, address indexed pool, uint256 feeTier);

    struct TradeablePair
    {
        address token1_erc20;
        address token2_erc20;
        address token1_erc223;
        address token2_erc223;
        mapping (uint24 => address) pools; // fee tier => pool address
    }

    uint256 public last_update;
    uint256 public num_listed_tokens;

    mapping(uint256 => TradeablePair) public pairs; // index => pair

    function isListed(address _token) public view returns (bool)
    {
        return listed_tokens[_token];
    }

    function list(address pool, uint24 feeTier) public
    {
        require(checkListingCriteria());
        IDexPool _pool = IDexPool(pool);

        (address _token0_erc20, address _token0_erc223) = _pool.token0();
        (address _token1_erc20, address _token1_erc223) = _pool.token1();

        require(_token0_erc20 != address(0) || _token0_erc223 != address(0), "Token not defined in the pool contract.");
        require(_token1_erc20 != address(0) || _token1_erc223 != address(0), "Token not defined in the pool contract.");
        require(factory.getPool(_token0_erc20, _token1_erc20, feeTier) == pool, "Token pool is not a part of Dex223 factory.");

        if(!isListed(_token0_erc20) || !isListed(_token0_erc223))
        {
            emit TokenListed(_token0_erc20, _token0_erc223);
            tokens[num_listed_tokens] = Token(_token0_erc20, _token0_erc223);
            num_listed_tokens++;
        }

        if(!isListed(_token1_erc20) || !isListed(_token1_erc223))
        {
            emit TokenListed(_token1_erc20, _token1_erc223);
            tokens[num_listed_tokens] = Token(_token1_erc20, _token1_erc223);
            num_listed_tokens++;
        }

        emit PairListed(_token0_erc20, _token0_erc223, _token1_erc20, _token1_erc223, pool, feeTier);
        last_update = block.timestamp;
    }

    function checkListingCriteria() internal view returns (bool)
    {
        // This function implements custom logic of listing an asset
        // in this exact contract.
        // It may require payments or some liquidity criteria.

        // Free-listing contract does not require anything so it will automatically pass.

        return true;
    }

    function getToken(uint256 index) public view returns (address _erc20, address _erc223)
    {
        return (tokens[index].erc20, tokens[index].erc223);
    }
}
