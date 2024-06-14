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

    mapping(address => uint256) public listed_tokens; // Address => ID (the ID will point at to two addresses,
                                                      //                both versions of this tokens in different standards).
    mapping(uint256 => Token)   public tokens;        // ID      => two addresses (ERC-20 ; ERC-223).

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
        return (listed_tokens[_token] != 0);
    }

    function list(address pool, uint24 feeTier) public
    {
        require(checkListingCriteria());
        IDexPool _pool = IDexPool(pool);

        (address _token0_erc20, address _token0_erc223) = _pool.token0();
        (address _token1_erc20, address _token1_erc223) = _pool.token1();

        // Checking if we are listing a token which has a pool at Dex223.
        require(_token0_erc20 != address(0) || _token0_erc223 != address(0), "Token not defined in the pool contract.");
        require(_token1_erc20 != address(0) || _token1_erc223 != address(0), "Token not defined in the pool contract.");
        require(factory.getPool(_token0_erc20, _token1_erc20, feeTier) == pool, "Token pool is not a part of Dex223 factory.");

        if(!isListed(_token0_erc20) || !isListed(_token0_erc223))
        {
            checkListing(_token0_erc20, _token0_erc223);
        }

        if(!isListed(_token1_erc20) || !isListed(_token1_erc223))
        {
            
            checkListing(_token1_erc20, _token1_erc223);
        }

        emit PairListed(_token0_erc20, _token0_erc223, _token1_erc20, _token1_erc223, pool, feeTier);
        last_update = block.timestamp;
    }

    function checkListing(address _token_erc20, address _token_erc223) internal 
    {
        
            // There are two possible scenarios here:
            // 1. We are listing a new token on Dex223.
            // 2. We are adding a version of an already listed token which previously had
            //    only one standard available.
            emit TokenListed(_token_erc20, _token_erc223);
            if(!isListed(_token_erc20) && !isListed(_token_erc223))
            {
                // Listing a new token.
                num_listed_tokens++; // First increase the counter, tokens[0] must be always address(0).
                tokens[num_listed_tokens]     = Token(_token_erc20, _token_erc223);
                listed_tokens[_token_erc20]  = num_listed_tokens;
                listed_tokens[_token_erc223] = num_listed_tokens;
            }
            else
            {
                // Adding a new version (standard) to a previously listed token.
                if(isListed(_token_erc20))
                {
                    // If the token is already listed as ERC-20;
                    tokens[listed_tokens[_token_erc20]] = Token(_token_erc20, _token_erc223);
                    listed_tokens[_token_erc223]        = listed_tokens[_token_erc20];
                }
                else 
                {
                    // Otherwise the token is listed as ERC-223;
                    tokens[listed_tokens[_token_erc223]] = Token(_token_erc20, _token_erc223);
                    listed_tokens[_token_erc20]          = listed_tokens[_token_erc223];
                }
            }
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
