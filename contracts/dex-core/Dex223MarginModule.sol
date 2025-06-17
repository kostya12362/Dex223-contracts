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
import './Dex223Oracle.sol';

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

contract WhitelistIDHelper
{
    function calcTokenListsID(address[] calldata tokens, bool isContract) public view returns(bytes32) {
        bytes32 _hash = keccak256(abi.encode(isContract, tokens));
        return _hash;
    }
}

contract MarginModule {
    uint256 constant private MAX_UINT8 = 255;
    uint256 constant private MAX_FREEZE_DURATION = 1 hours;
    uint256 constant private INTEREST_RATE_PRECISION = 10000; 
    IDex223Factory public factory;
    ISwapRouter public router;

    mapping (uint256 => Order) public orders;
    mapping (uint256 => OrderStatus) public order_status;
    mapping (uint256 => Position) public positions;
    mapping (address => mapping(address => uint256)) public erc223deposit;
    mapping(bytes32 => Tokenlist) public tokenlists;

    uint256 internal orderIndex;
    uint256 internal positionIndex;

    event OrderCreated(
        uint256 indexed orderId,
        address indexed owner,
        address indexed baseAsset,
        uint256 interestRate,
        uint256 duration,
        uint256 minLoan,
        uint8 leverage
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

    constructor(address _factory, address _router) {
        factory = IDex223Factory(_factory);
        router = ISwapRouter(_router);
    }

    function addTokenlist(address[] calldata tokens, bool isContract) public returns(bytes32) {
        //tokenlists.push(list);
        bytes32 _hash = keccak256(abi.encode(isContract, tokens));
        if(tokenlists[_hash].exists) { return _hash; }  // No need to waste gas if the same exact list already exists.
        tokenlists[_hash] = Tokenlist(true, isContract, tokens);
        return _hash;
    }

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
    ) public {

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

        emit OrderCreated(orderIndex, msg.sender, params.asset, params.interestRate, params.duration, params.minLoan, params.leverage);
        orderIndex++;
    }

    // ActivateOrder is unnecessary since we can set everything properly with createOrder
    // since the implementation of OrderParams that bypasses stack depth limits.
    function activateOrder(uint256 id, address[] calldata collateral) public {
        Order storage order = orders[id];
        require(order.owner == msg.sender);
        require(order.collateralAssets.length == 0);
        require(collateral.length > 0);

        order.collateralAssets = collateral;
    }

    function setOrderStatus(uint256 _orderId, bool _status) public
    {
        Order storage order = orders[_orderId];
        require(order.owner == msg.sender);
        order_status[_orderId].alive = _status;
    }

    function modifyOrder(uint256 _orderId, bytes32 _whitelist, uint256 _interestRate, uint256 _duration, uint256 _minLoan, uint16 _currencyLimit, uint8 _leverage, address _oracle, uint256 _liquidationRewardAmount, address _liquidationRewardAsset, uint32 _deadline) public 
    {
        Order storage order = orders[_orderId];
        require(order.owner == msg.sender);
        require(order_status[_orderId].positions == 0, "Cannot modify an Order which parents active positions");

/*
    struct Order {
        address owner;
        uint256 id;
        uint256 whitelist;
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
*/
        order.whitelist     = _whitelist;
        order.interestRate  = _interestRate;
        order.duration      = _duration;
        order.minLoan       = _minLoan;
        order.currencyLimit = _currencyLimit;
        order.leverage      = _leverage;
        order.oracle        = _oracle;
        order.expirationData = OrderExpiration(_liquidationRewardAmount, _liquidationRewardAsset, _deadline);
    }

    function orderDepositEth(uint256 orderId) public payable {
        require(orders[orderId].owner == msg.sender);
        require(isOrderOpen(orderId), "Order is expired");
        require(orders[orderId].baseAsset == address(0));

        orders[orderId].balance += msg.value;
        emit OrderDeposit(orderId, address(0), msg.value);
    }

    function orderDeposit(uint256 orderId, uint256 amount) public {
        require(orders[orderId].owner == msg.sender);
        require(isOrderOpen(orderId), "Order is expired");
        require(orders[orderId].baseAsset != address(0));

        _receiveAsset(orders[orderId].baseAsset, amount);
        orders[orderId].balance += amount;
        emit OrderDeposit(orderId, orders[orderId].baseAsset, amount);
    }

    function isOrderOpen(uint256 id) public view returns(bool) {
        Order storage order = orders[id];
        ( , , uint32 deadline) = getOrderExpirationData(id);
        bool isActivated = order.collateralAssets.length > 0;
        bool isNotExpired = deadline > block.timestamp;

        return isActivated && isNotExpired && order_status[id].alive;
    }

    function orderWithdraw(uint256 orderId, uint256 amount) public {
        require(orders[orderId].owner == msg.sender);
        // withdrawal is possible only when the order is closed
        //require(!isOrderOpen(orderId), "Order is still active");
        require(orders[orderId].balance >= amount);

        orders[orderId].balance -= amount;
        if (orders[orderId].baseAsset == address(0)) {
            _sendEth(amount);
        } else {
            _sendAsset(orders[orderId].baseAsset, amount);
        }

        emit OrderWithdraw(orderId, orders[orderId].baseAsset, amount);
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

        require(isOrderOpen(_orderId), "Order is expired");

        Order storage order = orders[_orderId];
        require(tokenlists[order.whitelist].tokens.length != 0, "Orders whitelist is empty");

        require(_collateralIdx < order.collateralAssets.length);
        address collateralAsset = order.collateralAssets[_collateralIdx];

        require(order.minLoan <= _amount);
        require(order.balance >= _amount);

        // leverage validation:
        // (collateral + loaned_asset) / collateral <= order.leverage
        uint256 collateralEquivalentInBaseAsset = _getEquivalentInBaseAsset(collateralAsset, _collateralAmount, order.baseAsset, _orderId);
        
        uint256 leverage = (collateralEquivalentInBaseAsset + _amount) / collateralEquivalentInBaseAsset;
        require(leverage <= MAX_UINT8);
        require(uint8(leverage) <= order.leverage);

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

        positions[positionIndex] = _newPosition;

        order.balance -= _amount;
        addAsset(positionIndex, order.baseAsset, _amount);

        addAsset(positionIndex, collateralAsset, _collateralAmount);

        uint256 receivedEth = msg.value;

        // Deposit collateral
        // In case the collateral asset is Ether
        if (collateralAsset == address(0)) {
            require(receivedEth >= _collateralAmount);
            receivedEth -= _collateralAmount;
        // or ERC-20
        } else {
            _receiveAsset(collateralAsset, _collateralAmount);
        }

        // Deposit the liquidation reward
        // In case the reward asset is Ether
        (uint256 rewardAmount, address rewardAsset, ) = getOrderExpirationData(_orderId);
        if (rewardAsset == address(0)) {
            require(receivedEth >= rewardAmount);
            receivedEth -= rewardAmount;
        // or ERC-20
        } else {
            _receiveAsset(rewardAsset, rewardAmount);
        }

        // Make sure position is not subject to liquidation right after it was created.
        // Revert otherwise.
        // This automatically checks if all the collateral that was paid satisfies the criteria set by the lender.

        require(!subjectToLiquidation(positionIndex));
        positionIndex++;

        // Increment the amount of active positions associated with the parent order,
        // we are tracking the active positions to make sure that the Order owner
        // will not modify an Order that has any active positins.
        order_status[_orderId].positions++;

        emit PositionOpened(positionIndex, msg.sender, _amount, order.baseAsset);
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

            (address poolAddress,,) = oracle.findPoolWithHighestLiquidity(asset, baseAsset);
            uint256 estimatedAsBase = oracle.getAmountOut(poolAddress, baseAsset, asset, balance);
            totalValueInBaseAsset += estimatedAsBase;
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

    function liquidate(uint256 positionId) public {
        Position storage position = positions[positionId];

        require(position.open);

        if (position.frozenTime > 0) {
            require(position.frozenTime < block.timestamp);
            uint256 frozenDuration = block.timestamp - position.frozenTime;
            // On the first hour after a position is frozen, only the party that initiated the freeze can liquidate it.
            if (frozenDuration <= MAX_FREEZE_DURATION) {
                require(msg.sender == position.liquidator);
                _liquidate(positionId);
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
        if (asset == address(0)) {
            _sendEth(amount);
        } else {
            _sendAsset(asset, amount);
        }

        // Payment of liquidation reward
        // TODO: Fix reading data from positions parenting Order
        //       because the Order owner can update configuration
        //       after the position was closed.
        Order storage order = orders[position.orderId];
        (uint256 rewardAmount, address rewardAsset, ) = getOrderExpirationData(position.orderId);
        if (rewardAsset == address(0)) {
            _sendEth(rewardAmount);
        } else {
            _sendAsset(rewardAsset, rewardAmount);
        }
    }

    function _liquidate(uint256 positionId) internal {
        Position storage position = positions[positionId];
        //Order storage order = orders[position.orderId];
        bool success = true;

        uint256 requiredAmount = _paybackBaseAsset(position);
        if (requiredAmount > 0) {
            // Start from 1 as 0 is base asset
            for (uint256 i = 1; i < position.assets.length && requiredAmount > 0; i++) {
                address asset = position.assets[i];
                uint256 balance = position.balances[i];
                
                if (balance == 0) continue;
                
                uint256 baseAssetReceived = _swapToBaseAsset(positionId, asset, balance);
            }
            
            // Final attempt to pay back after all swaps
            requiredAmount = _paybackBaseAsset(position);
        }

        if (success) {
            // Payment of liquidation reward
            (uint256 rewardAmount, address rewardAsset, ) = getOrderExpirationData(position.orderId);
            if (rewardAsset == address(0)) {
                _sendEth(rewardAmount);
            } else {
                _sendAsset(rewardAsset, rewardAmount);
            }
            emit PositionLiquidated(positionId, msg.sender, rewardAmount);
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
            (address poolAddress,,) = oracle.findPoolWithHighestLiquidity(asset, baseAsset);
            uint256 estimatedAsBase = oracle.getAmountOut(poolAddress, baseAsset, asset, amount);
            baseAmount = estimatedAsBase;
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
            require(IDex223Autolisting(_contract).isListed(asset));
        } else {
            require(whitelist.tokens[idInWhitelist] == asset);
        }
    }

    function _sendAsset(address asset, uint256 amount) internal {
        require(asset != address(0));

        IERC20Minimal(asset).transfer(msg.sender, amount);
    }

    function _sendEth(uint256 amount) internal {
        (bool success, ) = payable(msg.sender).call{value: amount}("");
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

}
