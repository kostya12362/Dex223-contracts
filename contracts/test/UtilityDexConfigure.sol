// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;
pragma abicoder v2;

interface IQuotePool
{
    function quoteSwap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bool prefer223,
        bytes memory data
    ) external returns (int256 delta);
}

interface ISwapExactInputSingleParams
{
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
        bool    prefer223Out;
    }
}

interface INFPMParams
{
    struct MintParams {
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

interface IRouter is ISwapExactInputSingleParams
{
    function exactInputSingle(ExactInputSingleParams calldata params)
    external
    payable
    returns (uint256 amountOut);

    function setConfiguration(address _factory) external;
}

interface INFPM is INFPMParams
{    
    function mint(MintParams calldata params)
        external
        payable
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );

    function setConfiguration(address _factory) external;

    function createAndInitializePoolIfNecessary(
        address token0_20,
        address token1_20,
        address token0_223,
        address token1_223,
        uint24 fee,
        uint160 sqrtPriceX96
    ) external payable returns (address pool);
}

interface IERC7417TokenConverter
{

    function predictWrapperAddress(address _token,
                                   bool    _isERC20
                                  ) view external returns (address);
}

interface IERC20 {
    function mint(address who, uint256 quantity) external;
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    //function decimals() external view returns (uint256);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract UtilityDEXConfigure2 is INFPMParams, ISwapExactInputSingleParams
{
    address public factory;
    address public NFPM;
    address public Router;
    address public Converter;

    address public creator = msg.sender;

    address XE_token = address(0x8F5Ea3D9b780da2D0Ab6517ac4f6E697A948794f); // XE = token0
    address HE_token = address(0xEC5aa08386F4B20dE1ADF9Cdf225b71a133FfaBa);

    constructor()
    {
        IERC20(XE_token).mint(address(this), 99999999999999999999);
        IERC20(HE_token).mint(address(this), 99999999999999999999);

        factory   = 0x3BD240DC11601223e35F2b803905b832c2798c2c;
        NFPM      = 0x091249267D085055Fa2f281FA3f6C0cF4BF70bae;
        Router    = 0x6d1a12d5921692f240CcDD9d4b7cAc2cCeD1BEd2;
        Converter = 0x5847f5C0E09182d9e75fE8B1617786F62fee0D9F;
    }

    function set(address _factory, address _router, address _NFPM, address _converter, bool _dynamicAdjustment) public
    {
        factory = _factory;
        Router = _router;
        NFPM = _NFPM;
        Converter = _converter;

        if(_dynamicAdjustment)
        {
            // Configurable NFPM on Sepolia:   0x068754a9fd1923d5c7b2da008c56ba0ef0958d7e
            INFPM(NFPM).setConfiguration(factory);
            // Configurable Router on Sepolia: 0x99504dbaa0f9368e9341c15f67377d55ed4ac690
            IRouter(Router).setConfiguration(factory);
        }
    }

    function step1_XEHEPool() public
    {
        //IERC20(XE_token).approve(NFPM, 1157920892373161954235709850086879078532699846656405640394575840079131296);
        //IERC20(HE_token).approve(NFPM, 1157920892373161954235709850086879078532699846656405640394575840079131296);
        
        INFPM(NFPM).createAndInitializePoolIfNecessary(
            XE_token,
            HE_token,
            IERC7417TokenConverter(Converter).predictWrapperAddress(XE_token, true),
            IERC7417TokenConverter(Converter).predictWrapperAddress(HE_token, true),
            10000,
            2493578422612728506914605883 // Almost 1:1 ..... almost.
        );
    }

    function step2_XEHELiquidity() public
    {
        IERC20(XE_token).approve(NFPM, 1157920892373161954235709850086879078532699846656405640394575840079131296);
        IERC20(HE_token).approve(NFPM, 1157920892373161954235709850086879078532699846656405640394575840079131296);

        MintParams memory _mintParams = MintParams(
        XE_token,
        HE_token,
        10000,
        -887200,
        887200,
        4999998998,  // First one has 5 decimals
        4964528,     // The other one has 2 decimals
        0,
        0,
        creator,
        block.timestamp + 10000 );
        
        INFPM(NFPM).mint(_mintParams);
    }

    function step3_XEHESwap() public
    {
        IERC20(XE_token).approve(Router, 1157920892373161954235709850086879078532699846656405640394575840079131296);
        IERC20(HE_token).approve(Router, 1157920892373161954235709850086879078532699846656405640394575840079131296);

        ExactInputSingleParams memory _swapParams = ExactInputSingleParams(
        XE_token,
        HE_token,
        10000,
        creator,
        block.timestamp + 10000,
        //uint256(154) * IERC20(XE_token).decimals(),
        14814000,
        0,
        4295128740,
        false);
        
        IRouter(Router).exactInputSingle(_swapParams);
    }

    function step4_HEXESwap() public
    {
        if(IERC20(XE_token).allowance(address(this), Router) <= 100000000000)
        {
            IERC20(XE_token).approve(Router, 1157920892373161954235709850086879078532699846656405640394575840079131296);
            IERC20(HE_token).approve(Router, 1157920892373161954235709850086879078532699846656405640394575840079131296);
        }

        ExactInputSingleParams memory _swapParams = ExactInputSingleParams(
        HE_token,
        XE_token,
        10000,
        creator,
        block.timestamp + 10000,
        14814000,
        10578026,
        1461446703485210103287273052203988822378723970341,
        false);
        
        IRouter(Router).exactInputSingle(_swapParams);
    }

    /*
    ["0xEC5aa08386F4B20dE1ADF9Cdf225b71a133FfaBa", "0x8F5Ea3D9b780da2D0Ab6517ac4f6E697A948794f", "10000", "0x222E674FB1a7910cCF228f8aECF760508426b482", "1931079822268", "50000", "0", "1461446703485210103287273052203988822378723970341", "false"]
    */

    function step5_HEXEQuotePredict() public 
    {
        bytes memory data = abi.encodeWithSelector(0x1698ee82, XE_token, HE_token, 10000);
        (bool success, bytes memory returnData) = factory.staticcall(data);

        address _pool = abi.decode(returnData, (address));

        // Simulate swap and Quote-predict the price

        IQuotePool(_pool).quoteSwap(
            address(this), // Doesn't matter, swap will not actually execute anyways.
            true,          // Predict it for XE -> HE swap. XE is token0
            4202230,
            4295128740,
            false,
            ""
         );

        giveAllowancesIfNecessary();

        ExactInputSingleParams memory _swapParams = ExactInputSingleParams(
            XE_token,
            HE_token,
            10000,
            creator,
            block.timestamp + 10000,
            4202230,
            0,
            4295128740,
            false);
        
        IRouter(Router).exactInputSingle(_swapParams);

        //
        //address recipient,
        //bool zeroForOne,
        //int256 amountSpecified,
        //uint160 sqrtPriceLimitX96,
        //bool prefer223,
        //bytes memory data
    }

    function step6_HEXEQuoteInReverse() public 
    {
        bytes memory data = abi.encodeWithSelector(0x1698ee82, XE_token, HE_token, 10000);
        (bool success, bytes memory returnData) = factory.staticcall(data);

        address _pool = abi.decode(returnData, (address));

        // Simulate swap and Quote-predict the price

        IQuotePool(_pool).quoteSwap(
            address(this),
            false,          // Predict it for HE -> XE swap. XE is token0
            50000,
            1461446703485210103287273052203988822378723970341,
            false,
            "0xec5aa08386f4b20de1adf9cdf225b71a133ffaba0027108f5ea3d9b780da2d0ab6517ac4f6e697a948794f"
         );

        giveAllowancesIfNecessary();

        ExactInputSingleParams memory _swapParams = ExactInputSingleParams(
            HE_token,
            XE_token,
            10000,
            creator,
            block.timestamp + 10000,
            50000,
            0,
            1461446703485210103287273052203988822378723970341,
            false);
        
        IRouter(Router).exactInputSingle(_swapParams);

        //
        //address recipient,
        //bool zeroForOne,
        //int256 amountSpecified,
        //uint160 sqrtPriceLimitX96,
        //bool prefer223,
        //bytes memory data
    }

    function giveAllowancesIfNecessary() internal
    {
        if(IERC20(XE_token).allowance(address(this), Router) <= 100000000000)
        {
            IERC20(XE_token).approve(Router, 1157920892373161954235709850086879078532699846656405640394575840079131296);
            IERC20(HE_token).approve(Router, 1157920892373161954235709850086879078532699846656405640394575840079131296);
        }
    }



    /*
    0	recipient	address
0xaC68D878c004a28bD4505E61590D1703BFc339A9
1	zeroForOne	bool
false
2	amountSpecified	int256
50000
3	sqrtPriceLimitX96	uint160
1461446703485210103287273052203988822378723970341
4	prefer223	bool
false
5	data	bytes
0xec5aa08386f4b20de1adf9cdf225b71a133ffaba0027108f5ea3d9b780da2d0ab6517ac4f6e697a948794f
*/
}
