// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.7.6;
pragma abicoder v2;

import './interfaces/IDex223Factory.sol';
import './interfaces/IDex223Autolisting.sol';
import '../interfaces/ITokenConverter.sol';
import '../interfaces/IERC20Minimal.sol';
import '../interfaces/ISwapRouter.sol';
import '../libraries/TickMath.sol';
import '../tokens/interfaces/IERC223.sol';

interface IDex223Pool {
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

contract MarginModule
{
    IDex223Factory public factory;
    ISwapRouter public router;

    mapping (uint256 => Order)    public orders;
    mapping (uint256 => Position) public positions;
    mapping (uint256 => mapping (address => uint8)) assetIds;
    mapping (address => bool) public isAssetLoanable;
    mapping (address => bool) public isAssetPledgeable;

    uint256 orderIndex;
    uint256 positionIndex;
    address admin;

    event NewOrder(address asset, uint256 orderID);

    struct Order
    {
        address owner;
        uint256 id;
        address[] whitelistedTokens;
        address whitelistedTokenList;
        uint256 interestRate;
        uint256 duration;
        address[] collateralAssets;
        uint256[] minCollateralAmounts;
        address liquidationCollateral;
        uint256 liquidationCollateralAmount;

        address baseAsset;
        uint256 balance;

        uint8 state; // 0 - active
        // 1 - disabled, alive
        // 2 - disabled, empty

        uint16 currencyLimit;
    }

    struct Position
    {
        uint256 orderId;
        address owner;

        address[] assets;
        uint256[] balances;

        address[] whitelistedTokens;
        address whitelistedTokenList;

        uint256 deadline;

        address baseAsset;
        uint256 initialBalance;
        uint256 interest;
    }

    struct SwapCallbackData {
        bytes path;
        address payer;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin);
	_;
    }

    constructor(address _factory, address _router) {
	admin = msg.sender;
        factory = IDex223Factory(_factory);
        router = ISwapRouter(_router);
    }

    function createOrder(address[] memory tokens,
        address listingContract,
        uint256 interestRate,
        uint256 duration,
        address[] calldata collateral,
        uint256[] calldata minCollateralAmounts,
        address liquidationCollateral,
        uint256 liquidationCollateralAmount,
        address asset,
        uint16 currencyLimit
    ) public
    {
        require(isAssetLoanable[asset]);
        require(isAssetPledgeable[liquidationCollateral]);

        Order memory _newOrder = Order(msg.sender,
            orderIndex,
            tokens,
            listingContract,
            interestRate,
            duration,
            collateral,
            minCollateralAmounts,
            liquidationCollateral,
            liquidationCollateralAmount,
            asset,
            0,
            0,
            currencyLimit);

        orders[orderIndex] = _newOrder;

        emit NewOrder(asset, orderIndex);
        orderIndex++;
    }

    function orderDepositEth(uint256 orderId, uint256 amount) public payable {
        require(orders[orderId].owner == msg.sender);
        require(isOrderOpen(orderId));
        require(orders[orderId].baseAsset == address(0));

        orders[orderId].balance += msg.value;
    }

    function orderDeposit(uint256 orderId, uint256 amount) public {
        require(orders[orderId].owner == msg.sender);
        require(isOrderOpen(orderId));
        require(orders[orderId].baseAsset != address(0));

	uint256 _balance = IERC20Minimal(orders[orderId].baseAsset).balanceOf(address(this));
	IERC20Minimal(orders[orderId].baseAsset).transferFrom(msg.sender, address(this), amount);
	require(IERC20Minimal(orders[orderId].baseAsset).balanceOf(address(this)) >= _balance + amount);
	orders[orderId].balance += amount;
    }

    function isOrderOpen(uint256 id) public view returns(bool) {
        return orders[id].state == 0;
    }

    function orderWithdraw(uint256 orderId, uint256 amount) public {
        require(orders[orderId].owner == msg.sender);
        require(isOrderOpen(orderId));
        require(orders[orderId].baseAsset != address(0));
        require(orders[orderId].balance >= amount);

	IERC20Minimal(orders[orderId].baseAsset).transfer(msg.sender, amount);
	orders[orderId].balance -= amount;

    }

    function positionDeposit() public
    {

    }

    function positionWithdraw() public
    {

    }

    function positionClose() public
    {

    }

    function addAsset(uint256 _positionIndex, address _asset, int256 _amount) internal
    {
        uint8 _idx = assetIds[_positionIndex][_asset];
        if (_idx > 0) {
            positions[_positionIndex].balances[_idx-1] += uint(int(positions[_positionIndex].balances[_idx-1]) + _amount);
            // if asset become = 0 - remove it from array 
            if (positions[_positionIndex].balances[_idx-1] == 0) {
                positions[_positionIndex].assets[_idx-1] = positions[_positionIndex].assets[positions[_positionIndex].assets.length - 1];
                positions[_positionIndex].assets.pop();
                positions[_positionIndex].balances[_idx-1] = positions[_positionIndex].balances[positions[_positionIndex].balances.length - 1];
                positions[_positionIndex].balances.pop();
                assetIds[_positionIndex][_asset] = 0;
            }
        } else {
            positions[_positionIndex].assets.push(_asset);
            positions[_positionIndex].balances.push(uint(_amount));
            assetIds[_positionIndex][_asset] = uint8(positions[_positionIndex].assets.length);
        }
    }

    function takeLoan(uint256 _orderId, uint256 _amount, uint256 _collateralIdx, uint256 _collateralAmount) public {

        require(isOrderOpen(_orderId));

        Order storage order = orders[_orderId];
        address collateralAsset = order.collateralAssets[_collateralIdx];

        require(collateralAsset != address(0));
        require(order.minCollateralAmounts[_collateralIdx] <= _collateralAmount);
        require(order.balance > _amount);

        address[] memory _assets;
        uint256[] memory _balances;

        Position memory _newPosition = Position(_orderId,
            msg.sender,
            _assets,
            _balances,

            order.whitelistedTokens,
            order.whitelistedTokenList,

            order.duration,
            order.baseAsset,
            _amount,
            order.interestRate);

        positions[positionIndex] = _newPosition;

        order.balance -= _amount;
        addAsset(positionIndex, order.baseAsset, int(_amount));

        addAsset(positionIndex, collateralAsset, int(_collateralAmount));

        // Deposit the tokens (collateral).

        uint256 _balance = IERC20Minimal(collateralAsset).balanceOf(address(this));
        IERC20Minimal(collateralAsset).transferFrom(msg.sender, address(this), _collateralAmount);
        require(IERC20Minimal(collateralAsset).balanceOf(address(this)) >= _balance + _collateralAmount);

        // Make sure position is not subject to liquidation right after it was created.
        // Revert otherwise.
        // This automatically checks if all the collateral that was paid satisfies the criteria set by the lender.

        require(!subjectToLiquidation(positionIndex));
        positionIndex++;
    }

    function marginSwap(uint256 _positionId,
        uint256 _assetId1,
        uint256 _whitelistId1, // Internal ID in the whitelisted array. If set to 0
    // then the asset must be found in an auto-listing contract.
        uint256 _whitelistId2,
        uint256 _amount,
        address _asset2,
        uint24 _feeTier) public
    {
        // Only allow the owner of the position to perform trading operations with it.
        require(positions[_positionId].owner == msg.sender);
        address _asset1 = positions[_positionId].assets[_assetId1];

        // Check if the first asset is allowed within this position.
        if(_whitelistId1 != 0)
        {
            require(positions[_positionId].whitelistedTokens[_whitelistId1] == _asset1);
        }
        else
        {
            require(IDex223Autolisting(positions[_positionId].whitelistedTokenList).isListed(_asset1));
        }

        // Check if the second asset is allowed within this position.
        if(_whitelistId2 != 0)
        {
            require(positions[_positionId].whitelistedTokens[_whitelistId2] == _asset2);
        }
        else
        {
            require(IDex223Autolisting(positions[_positionId].whitelistedTokenList).isListed(_asset2));
        }

        // check if position has enough Asset1
        require(positions[_positionId].balances[_assetId1] >= _amount);

        // Perform the swap operation.
        // We only allow direct swaps for security reasons currently.

        require(factory.getPool(_asset1, _asset2, _feeTier) != address(0));

        // load & use IRouter interface for ERC-20.
        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: _asset1,
            tokenOut: _asset2,
            fee: _feeTier,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: _amount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0,
            prefer223Out: false  // TODO should we be able to choose out token type ?
        });
        uint256 amountOut = ISwapRouter(router).exactInputSingle(swapParams);
        require(amountOut > 0);

        // add new (received) asset to Position
        addAsset(_positionId, _asset2, int256(amountOut));
        addAsset(_positionId, _asset1, -int256(_amount));

        // Check if we do not exceed the set currency limit.
        require(checkCurrencyLimit(_positionId));
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
        address _asset2, // TODO can it be ERC20 ?
        uint24 _feeTier) public
    {
        // Only allow the owner of the position to perform trading operations with it.
        require(positions[_positionId].owner == msg.sender);
        address _asset1 = positions[_positionId].assets[_assetId1];

        // Check if the first asset is allowed within this position.
        if(_whitelistId1 != 0)
        {
            require(positions[_positionId].whitelistedTokens[_whitelistId1] == _asset1);
        }
        else
        {
            require(IDex223Autolisting(positions[_positionId].whitelistedTokenList).isListed(_asset1));
        }

        // Check if the second asset is allowed within this position.
        if(_whitelistId2 != 0)
        {
            require(positions[_positionId].whitelistedTokens[_whitelistId2] == _asset2);
        }
        else
        {
            require(IDex223Autolisting(positions[_positionId].whitelistedTokenList).isListed(_asset2));
        }

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
        addAsset(_positionId, _asset2, int256(amountOut));
        addAsset(_positionId, _asset1, -int256(_amount));

        // Check if we do not exceed the set currency limit.
        require(checkCurrencyLimit(_positionId));
    }

    function checkCurrencyLimit(uint256 _positionId) internal view returns (bool)
    {
        return positions[_positionId].assets.length <= orders[positions[_positionId].orderId].currencyLimit;
    }

    function subjectToLiquidation(uint256 _positionId) public view returns (bool)
    {
        // Always returns false for testing reasons.
        return false;
    }

    function liquidate() public
    {
        // 
    }

    function makePledgeable(address asset, bool pledgeable) public onlyAdmin {
        require(asset != address(0));
        isAssetPledgeable[asset] = pledgeable;
    }

    function makeLoanable(address asset, bool loanable) public onlyAdmin {
        require(asset != address(0));
        isAssetLoanable[asset] = loanable;
    }
}
