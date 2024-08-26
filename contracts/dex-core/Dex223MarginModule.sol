// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.7.6;
pragma abicoder v2;

import './interfaces/IDex223Factory.sol';
import '../interfaces/IERC20Minimal.sol';
import './interfaces/IDex223Autolisting.sol';

contract MarginModule
{
    IDex223Factory public factory;

    mapping (uint256 => Order)    public orders;
    mapping (uint256 => Position) public positions;

    uint256 orderIndex;
    uint256 positionIndex;

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
        uint256 minCollateralAmounts;
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

    constructor(address _factory) {
        factory = IDex223Factory(_factory);
    }

    function createOrder(address[] memory tokens,
                         address listingContract,
                         uint256 interestRate,
                         uint256 duration,
                         address[] memory collateral,
                         uint256 minCollateralAmount,
                         address liquidationCollateral,
                         uint256 liquidationCollateralAmount,
                         address asset,
                         uint16 currencyLimit
                         ) public
    {
        Order memory _newOrder = Order(msg.sender,
                                orderIndex,
                                tokens,
                                listingContract,
                                interestRate,
                                duration,
                                collateral,
                                minCollateralAmount,
                                liquidationCollateral,
                                liquidationCollateralAmount,
                                asset,
                                0,
                                0,
                                currencyLimit);
        
        orderIndex++;
        orders[orderIndex] = _newOrder;

        emit NewOrder(asset, orderIndex);
    }

    function orderDeposit(uint256 orderId, uint256 amount) public payable
    {
        require(orders[orderId].owner == msg.sender);
        if(orders[orderId].baseAsset == address(0))
        {
            orders[orderId].balance += msg.value;
        }
        else 
        {
            // Remember the crrent balance of the contract
            uint256 _balance = IERC20Minimal(orders[orderId].baseAsset).balanceOf(address(this));
            IERC20Minimal(orders[orderId].baseAsset).transferFrom(msg.sender, address(this), amount);
            require(IERC20Minimal(orders[orderId].baseAsset).balanceOf(address(this)) >= _balance + amount);
            orders[orderId].balance += amount;
        }
    }

    function orderWithdraw() public
    {

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

    function takeLoan(uint256 _orderId, uint256 _amount, uint256 _collateralIdx, uint256 _collateralAmount) public
    {
        // Create a new position template.

        require(orders[_orderId].collateralAssets[_collateralIdx] != address(0));
        address[] memory _assets;
        uint256[] memory _balances;

        /*
    struct Position
    {
        uint256 orderId;
        address owner;

        address[] assets;
        uint256[] balances;

        address[] whitelistedTokens;
        address[] whitelistedTokenLists;

        uint256 deadline;

        address baseAsset;
        uint256 initialBalance;
        uint256 interest;
    }
    */
        Position memory _newPosition = Position(_orderId, 
                                                msg.sender,
                                                _assets,
                                                _balances,

                                                orders[_orderId].whitelistedTokens,
                                                orders[_orderId].whitelistedTokenList,

                                                orders[_orderId].duration,
                                                orders[_orderId].baseAsset,
                                                _amount,
                                                orders[_orderId].interestRate);
        positionIndex++;
        positions[positionIndex] = _newPosition;
        positions[positionIndex].assets.push(orders[_orderId].collateralAssets[_collateralIdx]);
        positions[positionIndex].balances.push(_collateralAmount);

        // Withdraw the tokens (collateral).

        IERC20Minimal(orders[_orderId].collateralAssets[_collateralIdx]).transferFrom(msg.sender, address(this), _collateralAmount);

        // Copy the balance loaned from "order" to the balance of a new "position"
        // ------------ removed in v2 as the values are filled during position creation ------------

        //positions[positionIndex].assets.push(orders[_orderId].baseAsset);
        //positions[positionIndex].balances.push(_amount);

        // Make sure position is not subject to liquidation right after it was created.
        // Revert otherwise.
        // This automatically checks if all the collateral that was paid satisfies the criteria set by the lender.

        require(!subjectToLiquidation(positionIndex));
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
            require(positions[_positionId].whitelistedTokens[_whitelistId2] == _asset1);
        }
        else 
        {
            require(IDex223Autolisting(positions[_positionId].whitelistedTokenList).isListed(_asset2));
        }

        // Perform the swap operation.
        // We only allow direct swaps for security reasons currently.

        require(factory.getPool(_asset1, _asset2, _feeTier) != address(0));

        
        // TODO load & use IRouter interface for ERC-20.
        
        // Check if we do not exceed the set currency limit.
    }

    function marginSwap223() public
    {

    }

    function subjectToLiquidation(uint256 _positionId) public returns (bool)
    {
        // Always returns false for testing reasons.
        return false;
    }

    function liquidate() public 
    {
        // 
    }

}
