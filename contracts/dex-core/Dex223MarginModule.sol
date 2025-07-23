// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.7.6;
pragma abicoder v2;

import './interfaces/IDex223Factory.sol';
import './interfaces/IDex223Autolisting.sol';
import '../interfaces/ITokenConverter.sol';
import '../interfaces/IERC20Minimal.sol';
import '../libraries/Multicall.sol';
import '../interfaces/ISwapRouter.sol';
import '../libraries/TickMath.sol';
import '../tokens/interfaces/IERC223.sol';
import './Dex223Oracle.sol';

// TODO: Add new function that displays Pools for existing assets in a position

abstract contract IERC20 {
    uint8 public decimals;
    function mint(address who, uint256 quantity) external virtual;
    function balanceOf(address account) external view virtual returns (uint256);
    function transfer(address recipient, uint256 amount) external virtual returns (bool);
    function allowance(address owner, address spender) external view virtual returns (uint256);
    function approve(address spender, uint256 amount) external virtual returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external virtual returns (bool);
}

interface IOrderParams
{
    struct OrderParams
    {
        bytes32 whitelistId;
        uint256 interestRate;
        uint256 duration;
        uint256 minLoan;
        uint256 liquidationRewardAmount;
        address liquidationRewardAsset;
        address asset;
        uint32 deadline;
        uint16 currencyLimit;
        uint8 leverage;
        address oracle;
        address[] collateral;
    }
}

interface IDex223Pool
{
    function token0() external view returns (address, address);
    function token1() external view returns (address, address);
    function swapExactInput(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint256 amountOutMinimum,
        uint160 sqrtPriceLimitX96,
        bool prefer223,
        bytes memory data,
        uint256 deadline
    ) external returns (uint256 amountOut);
}


contract IWETH9 
{
    // WETH contract interface valid for https://etherscan.io/address/0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    event  Approval(address indexed src, address indexed guy, uint wad);
    event  Transfer(address indexed src, address indexed dst, uint wad);
    event  Deposit(address indexed dst, uint wad);
    event  Withdrawal(address indexed src, uint wad);

    mapping (address => uint)                       public  balanceOf;

    //function() public payable;   // <-- WETH contract supports a permissive fallback function.
    function deposit() external payable {}
    function withdraw(uint wad) external {}
}

contract WhitelistIDHelper
{
    function calcTokenListsID(address[] calldata tokens, bool isContract) public view returns(bytes32) {
        bytes32 _hash = keccak256(abi.encode(isContract, tokens));
        return _hash;
    }
}

contract PureOracle
{
    
    IUniswapV3Factory public factory;

    uint24[] public feeTiers = [500, 3000, 10000];

    constructor(address _factory)
    {
        factory = IUniswapV3Factory(_factory);
    }

    function findPoolWithHighestLiquidity(
        address tokenA,
        address tokenB
    ) public view returns (address poolAddress, uint128 liquidity, uint24 fee) {
        require(tokenA != tokenB);
        require(tokenA != address(0));

        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);

        for (uint i = 0; i < feeTiers.length; i++) {
            address pool = factory.getPool(token0, token1, feeTiers[i]);
            if (pool != address(0)) {
                uint128 currentLiquidity = IUniswapV3Pool(pool).liquidity();
                if (currentLiquidity >= liquidity) {
                    liquidity = currentLiquidity;
                    poolAddress = pool;
                    fee = feeTiers[i];
                }
            }
        }

        require(poolAddress != address(0));
    }

    function getAmountOut(
        //address poolAddress,
        address asset1,
        address asset2,
        uint256 quantity
    ) public view returns(uint256 amountForBuy) {
        // Always retains 1:4 ratio between two sorted tokens.
        uint256 _result;
        if(asset1 < asset2)
        {
            if(IERC20(asset2).decimals() > IERC20(asset1).decimals())
            {
                _result = quantity * 4 * 10 ** (IERC20(asset2).decimals() - IERC20(asset1).decimals());
            }
            else 
            {
                _result = quantity * 4 / 10 ** (IERC20(asset1).decimals() - IERC20(asset2).decimals());
            }
        }
        else 
        {
            if(IERC20(asset2).decimals() > IERC20(asset1).decimals())
            {
                _result = quantity / 4 * 10 ** (IERC20(asset2).decimals() - IERC20(asset1).decimals());
            }
            else 
            {
                _result = quantity / 4 / 10 ** (IERC20(asset1).decimals() - IERC20(asset2).decimals());
            }
        }

        return _result;
    }
}

interface IMintParams
{
    struct MintParams 
    {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }
}

interface INFPM is IMintParams {
    function createAndInitializePoolIfNecessary(
        address token0_20,
        address token1_20,
        address token0_223,
        address token1_223,
        uint24 fee,
        uint160 sqrtPriceX96
    ) external payable returns (address pool);

    function mint(MintParams calldata params)
    external
    payable
    returns (
        uint256 tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );
}

contract UtilityModuleCfg is IOrderParams, IMintParams
{
    // This contracts serves testing and examinign purposes
    // It can be used to perform basic operations in a batch
    // and automates some workflows related to setting up the margin-module.

    // NOTE: Highly unoptimized
    struct OrderExpiration {
        uint256 liquidationRewardAmount;
        address liquidationRewardAsset;
        uint32 deadline;
    } 
    struct Order {
        address owner;
        uint256 id;
        bytes32 whitelist;
        // interestRate equal 55 means 0,55% or interestRate equal 3500 means 35%
        uint256 interestRate;
        uint256 duration;
        uint256 minLoan; // Protection of liquidation process from overload.
        address baseAsset;
        uint16 currencyLimit;
        uint8 leverage;
        address oracle;
        uint256 balance;
        OrderExpiration expirationData;
        address[] collateralAssets;
    }

    address public margin_module;
    address public creator = msg.sender;
    bytes32 public tokenWlist;
    address public oracle;
    address public factory;
    address public NFPM;

    uint256 public last_order_id;

    address public converter = 0x5847f5C0E09182d9e75fE8B1617786F62fee0D9F; // Standard Sepolian converter.

    address XE_token = address(0x8F5Ea3D9b780da2D0Ab6517ac4f6E697A948794f); // XE
    address HE_token = address(0xEC5aa08386F4B20dE1ADF9Cdf225b71a133FfaBa); // HE

    address public token0;
    address public token1;
    address public liq_token;

    constructor()
    {
        factory = 0x3BD240DC11601223e35F2b803905b832c2798c2c;
        IERC20(XE_token).mint(address(this), 99999999999999 * 10**18);
        IERC20(HE_token).mint(address(this), 99999999999999 * 10**18);

        // Setup defaults,
        // during the full test run it resets at step X0_MakeTokens
        // Otherwise uses XE-HE-HE configuration.
        token0 = XE_token;
        token1 = HE_token;
        liq_token = HE_token;

        oracle = address(new PureOracle(factory));
    }

    function set(address _factory, address _mm, address _oracle, address _converter, address _nfpm) public
    {
        factory = _factory;
        margin_module = _mm;
        oracle        = _oracle;
        converter = _converter;
        NFPM = _nfpm;
    }

    function setDefaults(address _mm) public 
    {
        factory = 0x5D63230470AB553195dfaf794de3e94C69d150f9;
        margin_module = _mm;
        oracle        = 0x5572A0d34E98688B16324f87F849242D050AD8D5;
        converter = 0x5847f5C0E09182d9e75fE8B1617786F62fee0D9F;
        NFPM = 0x068754A9fd1923D5C7B2Da008c56BA0eF0958d7e;
    }

    function x0_MakeTokens() public
    {
        token0    = address(new ERC20Token("Foo Token", "FOO", 18, 133000 * 10**18));
        token1    = address(new ERC20Token("Bar Token", "BAR", 18, 244011 * 10**18));
        liq_token = address(new ERC20Token("Special Token to pay Liquidation rewards", "LIQ", 18, 7590000 * 10**18));

        if (token0 > token1)
        {
            address _tmp = token0;
            token0 = token1;
            token1 = _tmp;
        }

        IERC20Minimal(token0).transfer(msg.sender, 10000 * 10**18);
        IERC20Minimal(token1).transfer(msg.sender, 10000 * 10**18);
    }

    function x1_MakeReservePool() public
    {
        INFPM(NFPM).createAndInitializePoolIfNecessary(
            token0,
            token1,
            ITokenStandardConverter(converter).predictWrapperAddress(token0, true),
            ITokenStandardConverter(converter).predictWrapperAddress(token1, true),
            3000,
            2493578422612728506914605883
        );
    }

    function x1_MakePool10000() public
    {
        INFPM(NFPM).createAndInitializePoolIfNecessary(
            token0,
            token1,
            ITokenStandardConverter(converter).predictWrapperAddress(token0, true),
            ITokenStandardConverter(converter).predictWrapperAddress(token1, true),
            10000,
            2493578422612728506914605883
        );
    }

    function x2_Liquidity() public
    {

        // NOTE: Remix gase estimator fails consistently here
        //       When executing this function
        //       manually increase the amount of allocated gas.
        IERC20(token0).approve(NFPM, 1157920892373161954235709850086879078532699846656405640394575840079131296);
        IERC20(token1).approve(NFPM, 1157920892373161954235709850086879078532699846656405640394575840079131296);

        MintParams memory _mintParams = MintParams(
        token0,
        token1,
        10000,
        -887200,
        887200,
        5000 * 10**18,
        5000 * 10**18,
        0,
        0,
        creator,
        block.timestamp + 10000);
        
        INFPM(NFPM).mint(_mintParams);
    }

    function step0_MakeOracle(address _factory) public
    {
        //address _oracle = deploy PureOracle(_factory);
        oracle = address(new PureOracle(_factory));
    }

    event Step1(bytes32);
    function step1_MakeWhitelist() public
    {
        /*
        address[] memory _tokens = new address[](2);
        _tokens[0] = token0;
        _tokens[1] = token1;
        */

        //0x9368639e0000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000020000000000000000000000008f5ea3d9b780da2d0ab6517ac4f6e697a948794f000000000000000000000000ec5aa08386f4b20de1adf9cdf225b71a133ffaba
        //tokenWlist = margin_module.call("0x9368639e0000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000020000000000000000000000008f5ea3d9b780da2d0ab6517ac4f6e697a948794f000000000000000000000000ec5aa08386f4b20de1adf9cdf225b71a133ffaba");
        
        //tokenWlist = margin_module.call{value: 0}("0x9368639e0000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000020000000000000000000000008f5ea3d9b780da2d0ab6517ac4f6e697a948794f000000000000000000000000ec5aa08386f4b20de1adf9cdf225b71a133ffaba");
        
        address[] memory _tokens = new address[](2);
        _tokens[0] = token0;
        _tokens[1] = token1;
        tokenWlist = MarginModule(margin_module).addTokenlist(_tokens, false);
        emit Step1(tokenWlist);
    }

    function step2_MakeOrder() public 
    {
        OrderExpiration memory _orderDeath = OrderExpiration(103, token0, 4294967290);

/*      bytes32 whitelistId;
        uint256 interestRate;
        uint256 duration;
        uint256 minLoan;
        uint256 liquidationRewardAmount;
        address liquidationRewardAsset;
        address asset;
        uint32 deadline;
        uint16 currencyLimit;
        uint8 leverage;
        address oracle;
        address[] collateral;
        */
        address[] memory _collateralTkn = new address[](1);
        _collateralTkn[0] = token0;
        OrderParams memory _params;
        _params.whitelistId             = tokenWlist;
        _params.interestRate            = 216000000;
        _params.duration                = 4800;
        _params.minLoan                 = 0;
        _params.liquidationRewardAmount = 103;
        _params.liquidationRewardAsset  = liq_token;
        _params.asset                   = token1;
        _params.deadline                = 4294967290; // Infinity.
        _params.currencyLimit           = 4;
        _params.leverage                = 10;         // 10x << Max leverage
        _params.oracle                  = oracle;
        _params.collateral              = _collateralTkn;

        last_order_id = MarginModule(margin_module).createOrder(
            _params
        );

        // ["0x050afabcae45ca12d82e4e72a31b41705e9349d547c5502b13ca38747125a648", "216000000", "4800", "725", "725", "0xb16F35c0Ae2912430DAc15764477E179D9B9EbEa", "0xb16F35c0Ae2912430DAc15764477E179D9B9EbEa", "1949519966", "4", "10", "0xb16F35c0Ae2912430DAc15764477E179D9B9EbEa", ["0x8f5ea3d9b780da2d0ab6517ac4f6e697a948794f", "0xb16F35c0Ae2912430DAc15764477E179D9B9EbEa"]]
    }

    function step3_SupplyOrder() public 
    {
        
        if(IERC20(token0).allowance(address(this), margin_module) <= 100000000000)
        {
            IERC20(token0).approve(margin_module, 1157920892373161954235709850086879078532699846656405640394575840079131296);
            IERC20(token1).approve(margin_module, 1157920892373161954235709850086879078532699846656405640394575840079131296);
            IERC20(liq_token).approve(margin_module, 1157920892373161954235709850086879078532699846656405640394575840079131296);
        }

        MarginModule(margin_module).orderDepositToken(last_order_id, 1500 * 10**18);
    }

    function step3_SupplyOrder(uint256 _id) public 
    {
        if(IERC20(token0).allowance(address(this), margin_module) <= 100000000000)
        {
            IERC20(token0).approve(margin_module, 1157920892373161954235709850086879078532699846656405640394575840079131296);
            IERC20(token1).approve(margin_module, 1157920892373161954235709850086879078532699846656405640394575840079131296);
            IERC20(liq_token).approve(margin_module, 1157920892373161954235709850086879078532699846656405640394575840079131296);
        }

        MarginModule(margin_module).orderDepositToken(_id, 1500 * 10**18);
    }

    function step4_MakePosition() public 
    {
        if(IERC20(token0).allowance(address(this), margin_module) <= 100000000000)
        {
            IERC20(token0).approve(margin_module, 1157920892373161954235709850086879078532699846656405640394575840079131296);
            IERC20(token1).approve(margin_module, 1157920892373161954235709850086879078532699846656405640394575840079131296);
            IERC20(liq_token).approve(margin_module, 1157920892373161954235709850086879078532699846656405640394575840079131296);
        }

        MarginModule(margin_module).takeLoan(
            last_order_id,
            500 * 10**18,
            0,
            250 * 10**18 // 250 -> 750 >>> 3x leverage
        );
    }
}

contract MarginModule is Multicall, IOrderParams
{
    uint256 constant private MAX_UINT8 = 255;
    uint256 constant private MAX_FREEZE_DURATION = 1 hours;
    uint256 constant private INTEREST_RATE_PRECISION = 10000; 
    IDex223Factory public factory;
    ISwapRouter public router;

    mapping (uint256 => Order) public orders;
    mapping (uint256 => OrderStatus) public order_status;
    mapping (uint256 => Position) public positions;
    mapping (address => mapping(address => uint256)) public erc223deposit;
    mapping (bytes32 => Tokenlist) public tokenlists;
    mapping (uint256 => address)  public positionInitialCollateral;

    uint256 internal orderIndex;
    uint256 internal positionIndex;

    event OrderCreated(
        uint256 indexed orderId,
        address indexed owner,
        address indexed baseAsset,
        bytes32 whitelistId,
        uint256 interestRate,
        uint256 duration,
        uint256 minLoan,
        uint8 leverage,
        address oracle
    );

    event OrderModified(
        uint256 indexed orderId,
        address indexed owner,
        address indexed baseAsset,
        bytes32 tokenWhitelist,
        uint256 interestRate,
        uint256 duration,
        uint256 minLoan,
        uint8 leverage,
        address oracle
    );

    event OrderAliveStatus(
        uint256 indexed orderId,
        bool alive
    );

    event OrderDeposit(
        uint256 indexed orderId,
        address indexed asset,
        uint256 amount
    );

    event OrderWithdraw(
        uint256 indexed orderId,
        address indexed asset,
        uint256 amount
    );

    event TokenlistAdded(bytes32 indexed hash, bool is_contract, address[] tokens);

    event PositionOpened(
        uint256 indexed positionId,
        address indexed owner,
        uint256 loanAmount,
        address baseAsset
    );

    event PositionDeposit(
        uint256 indexed positionId,
        address indexed asset,
        uint256 amount
    );

    event PositionFrozen(
        uint256 indexed positionId,
        address indexed liquidator,
        uint256 timestamp
    );
    
    event PositionLiquidated(
        uint256 indexed positionId,
        address indexed liquidator,
        uint256 rewardAmount
    );

    event MarginSwap(
        uint256 indexed positionId,
        address assetIn,
        address assetOut,
        uint256 amountIn,
        uint256 amountOut
    );

    event OrderCollateralsSet(uint256 indexed orderId, address[] collaterals);

    event Liquidation(uint256 indexed positionId,
                      uint256 indexed orderId,
                      address indexed liquidator,
                      address feeReceiver);

    event PositionWithdrawal(uint256 indexed positionId,
                             address indexed asset,
                             uint256 quantity);

    event PositionClosed(uint256 indexed positionId,
                        address  closedBy);
   
    struct Tokenlist {
        bool exists;
        bool isContract;
        address[] tokens;
    }

    // TODO: Rename for better readability
    //       liquidation parameters are not related
    //       to the "end of orders lifecycle".
    struct OrderExpiration {
        uint256 liquidationRewardAmount;
        address liquidationRewardAsset;
        uint32 deadline;
    } 

    struct SwapData {
        address pool;
        address tokenIn;
        address tokenIn223;
        address tokenOut;
        uint24 fee;
        bool zeroForOne;
        bool prefer223Out;
        uint160 sqrtPriceLimitX96;
    }

    struct Order {
        address owner;
        uint256 id;
        bytes32 whitelist;
        // interestRate equal 55 means 0,55% or interestRate equal 3500 means 35%
        uint256 interestRate;
        uint256 duration;
        uint256 minLoan; // Protection of liquidation process from overload.
        address baseAsset;
        uint16 currencyLimit;
        uint8 leverage;
        address oracle;
        uint256 balance;
        OrderExpiration expirationData;
        address[] collateralAssets;
    }

    struct OrderStatus
    {
        bool alive;
        uint8 positions;
    }

    struct Position {
        uint256 orderId;
        address owner;

        address[] assets;
        uint256[] balances;

        uint256 deadline;
        uint256 createdAt;

        uint256 initialBalance;
        uint256 interest;

        uint256 paidDays;
        bool open;
        uint256 frozenTime;
        address liquidator;
    }

    struct SwapCallbackData {
        bytes path;
        address payer;
    }

    struct Token {
        address erc20;
        address erc223;
    }

    modifier onlyOrderOwner(uint256 _orderId)
    {
        require(orders[_orderId].owner == msg.sender);
        _;
    }

    constructor(address _factory, address _router) {
        factory = IDex223Factory(_factory);
        router = ISwapRouter(_router);
    }

    function getPositionActualPools(uint256 _positionId, uint24[] memory _feeTiers) public view returns (address[] memory _pools)
    {
        Position storage position = positions[_positionId];
        address[] storage assets = position.assets;
        Order storage order = orders[position.orderId];
        _pools = new address[](_feeTiers.length * position.assets.length);
        //Oracle oracle = Oracle(order.oracle);

        /*
        for (uint i = 0; i < feeTiers.length; i++) {
            address pool = factory.getPool(token0, token1, feeTiers[i]);
            if (pool != address(0)) {
                uint128 currentLiquidity = IUniswapV3Pool(pool).liquidity();
                if (currentLiquidity >= liquidity) {
                    liquidity = currentLiquidity;
                    poolAddress = pool;
                    fee = feeTiers[i];
                }
            }
        }
        */

        for (uint256 _positionAsset = 0; _positionAsset < position.assets.length; _positionAsset++) {
            for (uint24 _feeTier = 0; _feeTier < _feeTiers.length; _feeTier++) {
                _pools[_positionAsset + _feeTier] = factory.getPool(position.assets[_positionAsset], order.baseAsset, _feeTiers[_feeTier]);
            }
        }
/*
        for (uint256 _positionAsset = 0; _positionAsset < position.assets.length; _positionAsset++) {
            for (uint24 _feeTier = 0; _feeTier < _feeTiers.length; _feeTier++) {
                _pools[_positionAsset + _feeTier] = address(this);
            }
        }
*/
    }

    function getCollaterals(uint256 _orderId) public view returns(address[] memory _collaterals)
    {
        return orders[_orderId].collateralAssets;
    }
    
    function predictTokenListsID(address[] calldata tokens, bool isContract) public pure returns(bytes32) {
        bytes32 _hash = keccak256(abi.encode(isContract, tokens));
        return _hash;
    }

    function addTokenlist(address[] calldata tokens, bool isContract) public returns(bytes32) {
        //tokenlists.push(list);
        bytes32 _hash = keccak256(abi.encode(isContract, tokens));
        if(tokenlists[_hash].exists) { return _hash; }  // No need to waste gas if the same exact list already exists.
        tokenlists[_hash] = Tokenlist(true, isContract, tokens);

        emit TokenlistAdded(_hash, isContract, tokens);
        return _hash;
    }

    function getTokenlist(bytes32 _hash) public view returns(address[] memory _tokens)
    {
        return tokenlists[_hash].tokens;
    }

    function createOrder(
        /*
        bytes32 whitelistId,
        uint256 interestRate,
        uint256 duration,
        uint256 minLoan,
        uint256 liquidationRewardAmount,
        address liquidationRewardAsset,
        address asset,
        uint32 deadline,
        uint16 currencyLimit,
        uint8 leverage,
        address oracle
        */
        OrderParams memory params
    ) public returns (uint256 orderId){

        require(params.leverage > 1);
        require(params.deadline > block.timestamp);

        OrderExpiration memory expirationData = OrderExpiration(
            params.liquidationRewardAmount,
            params.liquidationRewardAsset,
            params.deadline
        );

        orders[orderIndex] = Order(
            msg.sender,
            orderIndex,
            params.whitelistId,
            params.interestRate,
            params.duration,
            params.minLoan,
            params.asset,
            params.currencyLimit,
            params.leverage,
            params.oracle,
            0,
            expirationData,
            params.collateral
        );

        order_status[orderIndex] = OrderStatus(
            true,
            0
        );

        emit OrderCreated(orderIndex, msg.sender, params.asset, params.whitelistId, params.interestRate, params.duration, params.minLoan, params.leverage, params.oracle);
        emit OrderCollateralsSet(orderIndex, params.collateral);
        orderIndex++;
        return orderIndex - 1;
    }

    // ActivateOrder is unnecessary since we can set everything properly with createOrder
    // since the implementation of OrderParams that bypasses stack depth limits.
    /*
    function activateOrder(uint256 _orderId, address[] calldata collateral) public onlyOrderOwner(_orderId) {
        Order storage order = orders[_orderId];
        require(order.collateralAssets.length == 0);
        require(collateral.length > 0);

        order.collateralAssets = collateral;
    }
    */
    
    function orderSetCollaterals(uint256 _orderId, address[] calldata collateral) public onlyOrderOwner(_orderId) {
        Order storage order = orders[_orderId];
        require(order_status[_orderId].positions == 0, "Order has active positions");
        require(collateral.length > 0, "Order must have at least one collateral");

        order.collateralAssets = collateral;
        emit OrderCollateralsSet(_orderId, collateral);
    }

    function setOrderStatus(uint256 _orderId, bool _status) public onlyOrderOwner(_orderId)
    {
        order_status[_orderId].alive = _status;
        emit OrderAliveStatus(_orderId, _status);
    }

    function modifyOrder(uint256 _orderId,
                         bytes32 _whitelist,
                         uint256 _interestRate,
                         uint256 _duration,
                         uint256 _minLoan,
                         uint16 _currencyLimit,
                         uint8 _leverage,
                         address _oracle,
                         uint256 _liquidationRewardAmount,
                         address _liquidationRewardAsset,
                         uint32 _deadline) 
            public 
            onlyOrderOwner(_orderId)
    {
        Order storage order = orders[_orderId];
        require(order_status[_orderId].positions == 0, "Cannot modify an Order which parents active positions");

        order.whitelist     = _whitelist;
        order.interestRate  = _interestRate;
        order.duration      = _duration;
        order.minLoan       = _minLoan;
        order.currencyLimit = _currencyLimit;
        order.leverage      = _leverage;
        order.oracle        = _oracle;
        order.expirationData = OrderExpiration(_liquidationRewardAmount, _liquidationRewardAsset, _deadline);
        /*
        

    event OrderModified(
        uint256 indexed orderId,
        address indexed owner,
        address indexed baseAsset,
        uint256 interestRate,
        uint256 duration,
        uint256 minLoan,
        uint8 leverage,
        bool alive,
        address oracle
    );
    */
        //emit OrderModified(_orderId, msg.sender, order.baseAsset, order.interestRate, order.duration, order.minLoan, order.leverage, order_status[_orderId].alive, order.oracle);
        emit OrderModified(_orderId, msg.sender, order.baseAsset, _whitelist, _interestRate, _duration, _minLoan, _leverage, _oracle);
    }

    function orderDepositEth(uint256 _orderId) public payable onlyOrderOwner(_orderId) {
        require(isOrderOpen(_orderId), "Order is expired");
        require(orders[_orderId].baseAsset == address(0));

        orders[_orderId].balance += msg.value;
        emit OrderDeposit(_orderId, address(0), msg.value);
    }

    function orderDepositWETH9(uint256 _orderId, address _WETH9) public payable onlyOrderOwner(_orderId) {
        require(isOrderOpen(_orderId), "Order is expired");
        require(orders[_orderId].baseAsset == _WETH9);

        uint256 _balanceBefore = IWETH9(_WETH9).balanceOf(address(this));
        IWETH9(_WETH9).deposit{value: msg.value}();  // Execute deposit to WETH contract and track the received amount.
        uint256 _balanceDelta  = IWETH9(_WETH9).balanceOf(address(this)) - _balanceBefore;

        orders[_orderId].balance += _balanceDelta;
        //orders[_orderId].balance += msg.value;
        emit OrderDeposit(_orderId, address(0), _balanceDelta);
    }

    function orderDepositToken(uint256 _orderId, uint256 amount) public onlyOrderOwner(_orderId) {
        require(isOrderOpen(_orderId), "Order is expired");
        require(orders[_orderId].baseAsset != address(0));

        _receiveAsset(orders[_orderId].baseAsset, amount);
        orders[_orderId].balance += amount;
        emit OrderDeposit(_orderId, orders[_orderId].baseAsset, amount);
    }

    function isOrderOpen(uint256 id) public view returns(bool) {
        Order storage order = orders[id];
        ( , , uint32 deadline) = getOrderExpirationData(id);
        bool isActivated = order.collateralAssets.length > 0;
        bool isNotExpired = deadline > block.timestamp;

        return isActivated && isNotExpired && order_status[id].alive;
    }

    function orderWithdraw(uint256 _orderId, uint256 amount) public onlyOrderOwner(_orderId) {
        require(orders[_orderId].owner == msg.sender);
        // withdrawal is possible only when the order is closed
        //require(!isOrderOpen(_orderId), "Order is still active");
        require(orders[_orderId].balance >= amount);

        orders[_orderId].balance -= amount;
        if (orders[_orderId].baseAsset == address(0)) {
            _sendEth(amount, msg.sender);
        } else {
            _sendAsset(orders[_orderId].baseAsset, amount, msg.sender);
        }

        emit OrderWithdraw(_orderId, orders[_orderId].baseAsset, amount);
    }

    // TODO: Anyone can deposit funds to a position, not only the owner of the position.
    function positionDeposit(uint256 positionId, address asset, uint256 idInWhitelist,  uint256 amount) public {
        require(positions[positionId].owner == msg.sender, "Only the owner can deposit into this position");
        require(amount > 0, "Deposit must exceed zero");

        _validateAsset(positionId, asset, idInWhitelist);
        _receiveAsset(asset, amount);

        addAsset(positionId, asset, amount);
        emit PositionDeposit(positionId, asset, amount);
    }

    function getAssetId(uint256 positionId, address asset) public view returns (uint256) {
        address[] storage assets = positions[positionId].assets;

        for (uint256 i = 0; i < assets.length; i++) {
            if (assets[i] == asset) return i;
        }
        return assets.length;
    }

    function addAsset(uint256 _positionIndex, address _asset, uint256 _amount) internal {
        Position storage position = positions[_positionIndex];
        require(position.open);

        address[] storage assets = position.assets;
        uint256[] storage balances = position.balances;

        // base asset
        if (assets.length > 0 && assets[0] == _asset) {
            balances[0] += _amount;
        } else {
            uint256 id = getAssetId(_positionIndex, _asset);
            if (id < assets.length) {
                balances[id] += _amount;
            } else {
                require(checkCurrencyLimit(_positionIndex));
                require(_amount > 0);

                assets.push(_asset);
                balances.push(_amount);
            }
        }

    }

    function reduceAsset(uint256 _positionIndex, address _asset, uint256 _amount) internal {
        uint256 id = getAssetId(_positionIndex, _asset);
        Position storage position = positions[_positionIndex];
        address[] storage assets = position.assets;
        uint256[] storage balances = position.balances;

        require(id < assets.length);
        require(balances[id] >= _amount);

        balances[id] -= _amount;

        if (balances[id] == 0) {
            removeAsset(_positionIndex, id);
        }
    }

    function removeAsset(uint256 _positionIndex, uint256 _idx) internal {
        // base asset is not deleted, even if it is empty
        if (_idx == 0) return;

        Position storage position = positions[_positionIndex];
        address[] storage assets = position.assets;
        uint256[] storage balances = position.balances;
        uint256 lastId = assets.length - 1;

        assets[_idx] = assets[lastId];
        assets.pop();
        balances[_idx] = balances[lastId];
        balances.pop();
    }

    function takeLoan(uint256 _orderId, uint256 _amount, uint256 _collateralIdx, uint256 _collateralAmount) public payable {
        // Make sure that both collateralToken and LiquidationRewardToken are approved
        // in sufficient quantity.
        require(isOrderOpen(_orderId), "Order is expired");

        Order storage order = orders[_orderId];
        require(tokenlists[order.whitelist].tokens.length != 0, "Orders whitelist is empty");

        require(_collateralIdx < order.collateralAssets.length, "Collaterals error");
        address collateralAsset = order.collateralAssets[_collateralIdx];

        require(order.minLoan <= _amount, "Minloan error");
        require(order.balance >= _amount, "Balance error");

        // leverage validation:
        // (collateral + loaned_asset) / collateral <= order.leverage
        uint256 collateralEquivalentInBaseAsset = _getEquivalentInBaseAsset(collateralAsset, _collateralAmount, order.baseAsset, _orderId);
        
        uint256 leverage = (collateralEquivalentInBaseAsset + _amount) / collateralEquivalentInBaseAsset;
        require(leverage <= MAX_UINT8, "Leverage exceeds maxuint8");
        require(uint8(leverage) <= order.leverage, "Leverage error");

        address[] memory _assets;
        uint256[] memory _balances;

        Position memory _newPosition = Position(_orderId,
            msg.sender,
            _assets,
            _balances,

            block.timestamp + order.duration,
            block.timestamp,
            _amount,
            order.interestRate,
            0,
            true,
            0,
            address(0));

        positionInitialCollateral[positionIndex] = collateralAsset;
        positions[positionIndex] = _newPosition;

        order.balance -= _amount;
        addAsset(positionIndex, order.baseAsset, _amount);
        addAsset(positionIndex, collateralAsset, _collateralAmount);

        uint256 receivedEth = msg.value;

        // Deposit collateral
        // In case the collateral asset is Ether
        if (collateralAsset == address(0)) {
            require(receivedEth >= _collateralAmount, "ETH reception error");
            receivedEth -= _collateralAmount;
        // or ERC-20
        } else {
            _receiveAsset(collateralAsset, _collateralAmount);
        }

        // Deposit the liquidation reward
        // In case the reward asset is Ether
        (uint256 rewardAmount, address rewardAsset, ) = getOrderExpirationData(_orderId);
        if (rewardAsset == address(0)) {
            require(receivedEth >= rewardAmount, "ETH reward reception error");
            receivedEth -= rewardAmount;
        // or ERC-20
        } else {
            _receiveAsset(rewardAsset, rewardAmount);
        }

        // Make sure position is not subject to liquidation right after it was created.
        // Revert otherwise.
        // This automatically checks if all the collateral that was paid satisfies the criteria set by the lender.

        require(!subjectToLiquidation(positionIndex), "Position is immediately exposed to liquidation");

        // Increment the amount of active positions associated with the parent order,
        // we are tracking the active positions to make sure that the Order owner
        // will not modify an Order that has any active positins.
        order_status[_orderId].positions++;

        emit PositionOpened(positionIndex, msg.sender, _amount, order.baseAsset);
        positionIndex++;
    }

    function marginSwap(uint256 _positionId,
        uint256 _assetId1,
        uint256 _whitelistId1, // Internal ID in the whitelisted array. If set to 0
        // then the asset must be found in an auto-listing contract.
        uint256 _whitelistId2,
        uint256 _amount,
        address _asset2,
        uint24 _feeTier
    ) public {

        Position storage position = positions[_positionId];

        if (msg.sender != position.owner) {
            require(msg.sender == position.liquidator && position.frozenTime > 0, "Only owner or liquidator");
        }

        address _asset1 = positions[_positionId].assets[_assetId1];

        _validateAsset(_positionId, _asset1, _whitelistId1);
        _validateAsset(_positionId, _asset2, _whitelistId2);

        // check if position has enough Asset1
        require(positions[_positionId].balances[_assetId1] >= _amount);

        // Perform the swap operation.
        // We only allow direct swaps for security reasons currently.

        require(factory.getPool(_asset1, _asset2, _feeTier) != address(0));

        // load & use IRouter interface for ERC-20.
        IERC20Minimal(_asset1).approve(address(router), _amount);
        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: _asset1,
            tokenOut: _asset2,
            fee: _feeTier,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: _amount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0,
            prefer223Out: false
        });
        uint256 amountOut = ISwapRouter(router).exactInputSingle(swapParams);
        require(amountOut > 0);

        // add new (received) asset to Position
        addAsset(_positionId, _asset2, amountOut);
        reduceAsset(_positionId, _asset1, _amount);

        emit MarginSwap(_positionId, _asset1, _asset2, _amount, amountOut);
    }

    function resolveTokenOut(
        bool prefer223Out,
        address pool,
        address tokenIn,
        address tokenOut
    ) private view returns (address) {
        if (prefer223Out) {
            (address _token0_erc20, address _token0_erc223) = IDex223Pool(pool).token0();
            (, address _token1_erc223) = IDex223Pool(pool).token1();

            return (_token0_erc20 == tokenIn) ? _token1_erc223 : _token0_erc223;
        } else {
            return tokenOut;
        }
    }

    function executeSwapWithDeposit(
        uint256 amountIn,
        address recipient,
        SwapCallbackData memory data,
        SwapData memory swapData
    ) private returns (uint256 amountOut) {
        bytes memory _data = abi.encodeWithSignature(
            "swap(address,bool,int256,uint160,bool,bytes)",
            recipient,
            swapData.zeroForOne,
            int256(amountIn),
            swapData.sqrtPriceLimitX96 == 0
                ? (swapData.zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
                : swapData.sqrtPriceLimitX96,
            swapData.prefer223Out,
            data
        );

        address _tokenOut = resolveTokenOut(swapData.prefer223Out, swapData.pool, swapData.tokenIn, swapData.tokenOut);

        (bool success, bytes memory resdata) = _tokenOut.call(abi.encodeWithSelector(IERC20Minimal.balanceOf.selector, recipient));

        bool tokenNotExist = (success && resdata.length == 0);

        uint256 balance1before = tokenNotExist ? 0 : abi.decode(resdata, (uint));
        require(IERC223(swapData.tokenIn223).transfer(swapData.pool, amountIn, _data));

        return uint256(IERC20Minimal(_tokenOut).balanceOf(recipient) - balance1before);
    }

    function marginSwap223(uint256 _positionId,
        uint256 _assetId1,
        uint256 _whitelistId1, // Internal ID in the whitelisted array. If set to 0
        // then the asset must be found in an auto-listing contract.
        uint256 _whitelistId2,
        uint256 _amount,
        address _asset2,
        uint24 _feeTier) public {
        // Only allow the owner of the position to perform trading operations with it.
        require(positions[_positionId].owner == msg.sender);
        address _asset1 = positions[_positionId].assets[_assetId1];

        _validateAsset(_positionId, _asset1, _whitelistId1);
        _validateAsset(_positionId, _asset2, _whitelistId2);

        // check if position has enough Asset1
        require(positions[_positionId].balances[_assetId1] >= _amount);

        // Perform the swap operation.
        // We only allow direct swaps for security reasons currently.


        address pool = factory.getPool(_asset1, _asset2, _feeTier);
        require(pool != address(0));

        address _asset1_20;
        address _asset2_20;

        // we need to use ERC20 version of Asset1 and Asset2 
        (address token0_20, address token0_223) = IDex223Pool(pool).token0();
        (address token1_20, ) = IDex223Pool(pool).token1();
        if (token0_223 == _asset1) {
            _asset1_20 = token0_20;
            _asset2_20 = token1_20;
        } else {
            _asset2_20 = token0_20;
            _asset1_20 = token1_20;
        }

        // SwapData memory swapData = SwapData({
        //     pool: pool,
        //     tokenIn: _asset1_20,
        //     tokenIn223: _asset1,
        //     tokenOut: _asset2_20,
        //     fee: _feeTier,
        //     zeroForOne: (_asset1_20 < _asset2_20),
        //     prefer223Out: true,
        //     sqrtPriceLimitX96: 0
        // });

        // SwapCallbackData memory data = SwapCallbackData({path: abi.encodePacked(_asset1_20, _feeTier, _asset2_20), payer: address(this)});

        uint256 amountOut = executeSwapWithDeposit(
            _amount,
            address(this),
            SwapCallbackData({path: abi.encodePacked(_asset1_20, _feeTier, _asset2_20), payer: address(this)}),
            SwapData({
                pool: pool,
                tokenIn: _asset1_20,
                tokenIn223: _asset1,
                tokenOut: _asset2_20,
                fee: _feeTier,
                zeroForOne: (_asset1_20 < _asset2_20),
                prefer223Out: true,
                sqrtPriceLimitX96: 0
            })
        );
        require(amountOut > 0);

        // add new (received) asset to Position
        addAsset(_positionId, _asset2, amountOut);
        reduceAsset(_positionId, _asset1, _amount);
        emit MarginSwap(_positionId, _asset1, _asset2, _amount, amountOut);
    }
    

    function getPositionStatus(uint256 positionId) public view returns(uint256 expected_balance, uint256 actual_balance)
    {
        Position storage position = positions[positionId];
        Order storage order = orders[position.orderId];
        Oracle oracle = Oracle(order.oracle);
        
        uint256 requiredAmount = calculateDebtAmount(position);
        // base asset(at index 0) balance
        uint256 totalValueInBaseAsset = position.balances[0];
        address baseAsset = position.assets[0];

        for (uint256 i = 1; i < position.assets.length; i++) {
            address asset = position.assets[i];
            uint256 balance = position.balances[i];

            //(address poolAddress,,) = oracle.findPoolWithHighestLiquidity(asset, baseAsset);
            //uint256 estimatedAsBase = oracle.getAmountOut(poolAddress, baseAsset, asset, balance);
            uint256 _estimatedAsBase = oracle.getAmountOut(baseAsset, asset, balance);
            totalValueInBaseAsset += _estimatedAsBase;
        }

        return (requiredAmount, totalValueInBaseAsset);
    }


    // @Dexaran 
    // Add liquidation criteria checks.
    // A position must be subject to liquidation once the amount of funds currently available is less-than-equal
    // than the amount of funds expected at the moment of the position check.
    // Example: if $10,000 loan was taken at 30% per 30 days and we are checking the state of this position 
    //          at 15th day then we expect it to have a cumulative balance of $11,500 at the moment of the check.

    // Price must be taken from the price source specified by the order owner.
    function subjectToLiquidation(uint256 positionId) public view returns (bool) {
        Position storage position = positions[positionId];
        Order storage order = orders[position.orderId];
        Oracle oracle = Oracle(order.oracle);

        uint256 requiredAmount = calculateDebtAmount(position);

        // base asset(at index 0) balance
        uint256 totalValueInBaseAsset = position.balances[0];
        address baseAsset = position.assets[0];

        for (uint256 i = 1; i < position.assets.length; i++) {
            address asset = position.assets[i];
            uint256 balance = position.balances[i];

            //(address poolAddress,,) = oracle.findPoolWithHighestLiquidity(asset, baseAsset);
            //uint256 estimatedAsBase = oracle.getAmountOut(poolAddress, baseAsset, asset, balance);
            uint256 _estimatedAsBase = oracle.getAmountOut(baseAsset, asset, balance);
            totalValueInBaseAsset += _estimatedAsBase;
        }

        return totalValueInBaseAsset < requiredAmount;
    }

    // The borrower must repay both the principal amount and the accrued interest.
    function calculateDebtAmount(Position storage position) internal view returns (uint256) {
        uint256 elapsedSecs = block.timestamp - position.createdAt;

        Order storage order = orders[position.orderId];
        // calculation of accrued loan interest over the past days
        uint256 requiredAmount = (position.initialBalance * order.interestRate * elapsedSecs) / 30 days;
        // strip excess precision digits from interestRate
        requiredAmount = requiredAmount / INTEREST_RATE_PRECISION;
        // include the loan principal amount
        requiredAmount += position.initialBalance;

        return requiredAmount;
    }

    function liquidate(uint256 positionId, address receiver) public {
        Position storage position = positions[positionId];

        require(position.open);

        if (position.frozenTime > 0) {
            require(position.frozenTime < block.timestamp);
            uint256 frozenDuration = block.timestamp - position.frozenTime;
            // On the first hour after a position is frozen, only the party that initiated the freeze can liquidate it.
            if (frozenDuration <= MAX_FREEZE_DURATION) {
                require(msg.sender == position.liquidator);
                _liquidate(positionId, receiver);
                emit Liquidation(positionId, positions[positionId].orderId, msg.sender, receiver);
            } else {
                position.frozenTime = 0;
                position.liquidator = address(0);
            }

        } else if (subjectToLiquidation(positionId)) {
            position.frozenTime = block.timestamp;
            position.liquidator = msg.sender;
            emit PositionFrozen(positionId, msg.sender, block.timestamp);
        }
    }

    function positionClose(uint256 positionId) public {
        Position storage position = positions[positionId];
        Order storage order = orders[position.orderId];
        require(position.open);

        // Only position owner can close, or order owner after deadline
        if (msg.sender != position.owner) {
            bool isExpired = position.deadline <= block.timestamp;
            require(isExpired && msg.sender == order.owner);
        }

        require(position.frozenTime == 0, "Position frozen");
        require(subjectToLiquidation(positionId) == false, "Subject to liquidation");
        position.open = false;

        uint256 requiredAmount = _paybackBaseAsset(position);
        if (requiredAmount > 0) {
            // Start from 1 as 0 is base asset
            for (uint256 i = 1; i < position.assets.length && requiredAmount > 0; i++) 
            {
                address asset = position.assets[i];
                uint256 balance = position.balances[i];
                
                if (balance == 0) continue;
                
                uint256 baseAssetReceived = _swapToBaseAsset(positionId, asset, balance);
            }
            
            // Final attempt to pay back after all swaps
            requiredAmount = _paybackBaseAsset(position);
            
            require(requiredAmount == 0, "Insufficient funds to close position");
        }

        // Autowithdraw the liquidation fee as soon as position is closed.
        (uint256 rewardAmount, address rewardAsset, ) = getOrderExpirationData(position.orderId);
        if (rewardAsset == address(0)) {
            _sendEth(rewardAmount, msg.sender);
        } else {
            _sendAsset(rewardAsset, rewardAmount, msg.sender);
        }

        emit PositionClosed(positionId, msg.sender);

        // Once the position is closed
        // we can decrease the number of active positions for the parent order.
        // If the number of active positions is 0 then the order owner can modify the order.
        order_status[position.orderId].positions--;
    }

    function positionWithdraw(uint256 positionId, address asset) public {
        Position storage position = positions[positionId];
        require(position.owner == msg.sender);
        require(!position.open, "Withdraw only from closed position");

        uint256 id = getAssetId(positionId, asset);
        require(id < position.assets.length);

        uint256[] storage balances = position.balances;
        uint256 amount = balances[id];

        reduceAsset(positionId, asset, amount);
        emit PositionWithdrawal(positionId, asset, amount);

        if (asset == address(0)) {
            _sendEth(amount, msg.sender);
        } else {
            _sendAsset(asset, amount, msg.sender);
        }
    }

    function _liquidate(uint256 positionId, address _receiver) internal {
        Position storage position = positions[positionId];

        for (uint256 i = 1; i < position.assets.length; i++) {
                address asset = position.assets[i];
                uint256 balance = position.balances[i];
                
                if (balance == 0) continue;
                
                uint256 baseAssetReceived = _swapToBaseAsset(positionId, asset, balance);
        }
        _paybackBaseAsset(position);

        // Payment of liquidation reward
        (uint256 rewardAmount, address rewardAsset, ) = getOrderExpirationData(position.orderId);
        if (rewardAsset == address(0)) 
        {
            _sendEth(rewardAmount, _receiver);
        } 
        else 
        {
            _sendAsset(rewardAsset, rewardAmount, _receiver);
        }

        position.open = false;

        // Once the position is liquidated
        // we can decrease the number of active positions for the parent order.
        // If the number of active positions is 0 then the order owner can modify the order.
        order_status[position.orderId].positions--;
    }

    /* Internal functions */

    function _paybackBaseAsset(Position storage position) internal returns(uint256) {
        // baseAsset is always at index 0 in the assets array
        uint256 baseBalance = position.balances[0];
        uint256 requiredAmount = calculateDebtAmount(position);

        Order storage order = orders[position.orderId];

        // checking whether the base asset balance is sufficient to repay the loan
        if (baseBalance >= requiredAmount) {
            position.balances[0] -= requiredAmount;
            order.balance += requiredAmount;
            requiredAmount = 0;
        } else {
            position.balances[0] = 0;
            order.balance += baseBalance;
            requiredAmount -= baseBalance;
        }
        return requiredAmount;
    }

    function _getEquivalentInBaseAsset(address asset, uint256 amount, address baseAsset, uint256 orderId) internal view returns(uint256 baseAmount) {
        if (asset == baseAsset) {
            baseAmount = amount;
        } else {
            Order storage order = orders[orderId];
            Oracle oracle = Oracle(order.oracle);
            //(address poolAddress,,) = oracle.findPoolWithHighestLiquidity(asset, baseAsset);
            //uint256 estimatedAsBase = oracle.getAmountOut(poolAddress, baseAsset, asset, amount);
            uint256 _estimatedAsBase = oracle.getAmountOut(baseAsset, asset, amount);
            baseAmount = _estimatedAsBase;
        }

        return baseAmount;
    }


    function _validateAsset(uint256 positionId, address asset, uint256 idInWhitelist) internal view {
        Position storage position = positions[positionId];
        Order storage order = orders[position.orderId];
        Tokenlist storage whitelist = tokenlists[order.whitelist];

        if (whitelist.isContract == true) {
            // Optimization: contract address stored as first element instead of separate var
            address _contract = whitelist.tokens[0];
            require(IDex223Autolisting(_contract).isListed(asset) || order.baseAsset == asset || positionInitialCollateral[positionId] == asset);
        } else {
            require(whitelist.tokens[idInWhitelist] == asset || order.baseAsset == asset || positionInitialCollateral[positionId] == asset);
        }
    }

    function _sendAsset(address asset, uint256 amount, address receiver) internal {
        require(asset != address(0));

        IERC20Minimal(asset).transfer(receiver, amount);
    }

    function _sendEth(uint256 amount, address receiver) internal {
        (bool success, ) = payable(receiver).call{value: amount}("");
        require(success);
    }

    function _receiveAsset(address asset, uint256 amount) internal {
        require(asset != address(0));
        
        // erc223
        if (erc223deposit[msg.sender][asset] > 0) {
            require(erc223deposit[msg.sender][asset] >= amount);
            erc223deposit[msg.sender][asset] -= amount;

        // erc20
        } else {
            uint256 balance = IERC20Minimal(asset).balanceOf(address(this));
            IERC20Minimal(asset).transferFrom(msg.sender, address(this), amount);
            require(IERC20Minimal(asset).balanceOf(address(this)) >= balance + amount);
        }
    }

    function checkCurrencyLimit(uint256 _positionId) internal view returns (bool) {
        return positions[_positionId].assets.length + 1 <= orders[positions[_positionId].orderId].currencyLimit;
    }

    function tokenReceived(address user, uint256 value, bytes memory data) public returns (bytes4) {
        address asset = msg.sender;
        erc223deposit[user][asset] += value;
        
        return 0x8943ec02;
    }

    function withdraw223(address asset) public {
        uint256 amount = erc223deposit[msg.sender][asset]; 
        require(amount > 0);

        erc223deposit[msg.sender][asset] = 0;
        require(IERC223(asset).transfer(msg.sender, amount));
    }
    

    function _swapToBaseAsset(uint256 positionId, address asset, uint256 amount) internal returns (uint256) {
        Position storage position = positions[positionId];
        Order storage order = orders[position.orderId];
        Oracle oracle = Oracle(order.oracle);

        (address pool,, uint24 fee) = oracle.findPoolWithHighestLiquidity(asset, order.baseAsset);
        require(pool != address(0), "No pool available");

        (, address token0) = IDex223Pool(pool).token0();
        (, address token1) = IDex223Pool(pool).token1();

        uint256 idInWl0 = getIdFromTokenlist(order.whitelist, asset);
        uint256 idInWl1 = getIdFromTokenlist(order.whitelist, order.baseAsset);

        if (token0 == asset || token1 == asset) {
            marginSwap223(positionId, getAssetId(positionId, asset), idInWl0, idInWl1, amount, order.baseAsset, fee);
        } else {
            marginSwap(positionId, getAssetId(positionId, asset), idInWl0, idInWl1, amount, order.baseAsset, fee);
        }

        // Return new base asset balance
        return position.balances[0]; 
    }

    // view functions
/*
    function getTokenlistsLength() public view returns (uint256) {
        return tokenlists.length;
    }
*/


    function getPositionAssets(uint256 id) public view returns (address[] memory) {
        return positions[id].assets;
    }

    function getPositionBalances(uint256 id) public view returns (uint256[] memory) {
        return positions[id].balances;
    }

    function getOrderCollateralAssets(uint256 id) public view returns (address[] memory) {
        return orders[id].collateralAssets;
    }

    function getOrderExpirationData(uint256 id) public view returns(uint256, address, uint32) {
        OrderExpiration storage data = orders[id].expirationData;

        return (data.liquidationRewardAmount, data.liquidationRewardAsset, data.deadline);
    }

    function getOrdersLength() public view returns (uint256) {
       return orderIndex;
    }

    function getPositionsLength() public view returns (uint256) {
        return positionIndex;
    }

    function getIdFromTokenlist(bytes32 _listId, address asset) public view returns(uint256 assetId) {
        Tokenlist storage list = tokenlists[_listId];

        if (list.isContract == true) {
            return 0;
        }

        assetId = list.tokens.length;
        for (uint256 i = 0; i < list.tokens.length; i++) {
            if (list.tokens[i] == asset) {
                assetId = i;
                break;
            }
        }
        require(assetId < list.tokens.length);
    }

    function getPositionTokenlistID(uint256 _positionId) public view returns(bytes32 _whitelistId) {
        
        Position storage position = positions[_positionId];
        Order storage order = orders[position.orderId];
        return order.whitelist;
    }
}

/**
 * @title ERC20Token
 * @dev Implementation of the ERC20 token standard with comprehensive features
 */
contract ERC20Token is IERC20 {
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    // Token metadata
    string public name;
    string public symbol;
    
    // Total supply tracking
    uint256 private _totalSupply;
    
    // Balance tracking system
    mapping(address => uint256) private _balances;
    
    // Allowance system - tracks approved spending amounts
    mapping(address => mapping(address => uint256)) private _allowances;
    
    // Events
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Mint(address indexed to, uint256 amount);
    event Burn(address indexed from, uint256 amount);
    
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 _initialSupply
    ) {
        require(bytes(_name).length > 0, "ERC20: name cannot be empty");
        require(bytes(_symbol).length > 0, "ERC20: symbol cannot be empty");
        require(_decimals <= 18, "ERC20: decimals cannot exceed 18");
        
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        
        // Calculate total supply with decimals
        _totalSupply = _initialSupply * 10**_decimals;
        
        // Assign initial supply to contract deployer
        _balances[msg.sender] = _totalSupply;
        
        emit Transfer(address(0), msg.sender, _totalSupply);
        emit OwnershipTransferred(address(0), msg.sender);
    }
    
    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }
    
    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }
    
    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }
    
    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }
    
    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        uint256 currentAllowance = _allowances[sender][msg.sender];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        
        _transfer(sender, recipient, amount);
        _approve(sender, msg.sender, currentAllowance - amount);
        
        return true;
    }
    
    function increaseAllowance(address spender, uint256 addedValue) public returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender] + addedValue);
        return true;
    }
    
    function decreaseAllowance(address spender, uint256 subtractedValue) public returns (bool) {
        uint256 currentAllowance = _allowances[msg.sender][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        
        _approve(msg.sender, spender, currentAllowance - subtractedValue);
        return true;
    }
    
    function mint(address to, uint256 amount) public override {
        require(amount > 0, "ERC20: mint amount must be greater than 0");
        
        _totalSupply += amount;
        _balances[to] += amount;
        
        emit Transfer(address(0), to, amount);
        emit Mint(to, amount);
    }
    
    /**
     * @dev Internal function to handle transfers
     * @param sender Address to transfer from
     * @param recipient Address to transfer to
     * @param amount Amount to transfer
     */
    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(_balances[sender] >= amount, "ERC20: transfer amount exceeds balance");
        
        _balances[sender] -= amount;
        _balances[recipient] += amount;
        
        emit Transfer(sender, recipient, amount);
    }
    
    /**
     * @dev Internal function to handle approvals
     * @param owner Address that owns the tokens
     * @param spender Address that will spend the tokens
     * @param amount Amount to approve
     */
    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
}
