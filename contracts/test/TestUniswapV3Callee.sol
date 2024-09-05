// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;

import '../interfaces/IERC20Minimal.sol';

import '../libraries/SafeCast.sol';
import '../libraries/TickMath.sol';

import '../interfaces/callback/IUniswapV3MintCallback.sol';
import '../interfaces/callback/IUniswapV3SwapCallback.sol';
import '../interfaces/callback/IUniswapV3FlashCallback.sol';
import '../tokens/interfaces/IERC223Recipient.sol';

import '../interfaces/IUniswapV3Pool.sol';

import 'hardhat/console.sol';

interface IDex223Pool {
    function token0() external view returns (address, address);
    function token1() external view returns (address, address);

    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bool prefer223,
        bytes memory data
    ) external returns (int256 amount0, int256 amount1);
}

contract TestUniswapV3Callee is IUniswapV3MintCallback, IUniswapV3SwapCallback, IERC223Recipient { // IUniswapV3FlashCallback
    using SafeCast for uint256;

    mapping(address => mapping(address => uint256)) internal _erc223Deposits;
    ERC223TransferInfo private tkn;

    address public call_sender;

    modifier adjustableSender() {
        if (call_sender == address(0))
        {
            call_sender = msg.sender;
        }

        _;

        call_sender = address(0);
    }

    function depositERC223(address _user, address _token, uint256 _quantity) internal
    {
        _erc223Deposits[_user][_token] += _quantity;
    }

    function depositedTokens(address _user, address _token) public view returns (uint256)
    {
        return _erc223Deposits[_user][_token];
    }

    function tokenReceived(address _from, uint _value, bytes memory _data) public override returns (bytes4)
    {
//        console.log('Callee tokens received');
//        console.log(_from);
//        console.logUint(_value);
        depositERC223(_from, msg.sender, _value);
//        erc223deposit[_from][msg.sender] += _value;

        call_sender = _from;
        if (_data.length != 0)
        {
            // Standard ERC-223 swapping via ERC-20 pattern
            (bool success, bytes memory _data_) = address(this).delegatecall(_data);
            require(success, "23F");
/*
            ERC223SwapStep memory encodedSwaps = abi.decode(_data, (ERC223SwapStep));

            for (uint16 i = 0; i < encodedSwaps.path.length; i++)
            {
                swapERC223(encodedSwaps.path[i-1], encodedSwaps.path[i]);
            }
*/
        }
//        console.log('Callee operation success');
        // NOTE this is needed only on mint, but not on swap
//        if (_erc223Deposits[_from][msg.sender] != 0) IERC20Minimal(msg.sender).transfer(_from, _erc223Deposits[_from][msg.sender]);

        call_sender = address(0);
        return 0x8943ec02;
    }

    function swapExact0For1(
        address pool,
        uint256 amount0In,
        address recipient,
        uint160 sqrtPriceLimitX96
    ) external {
        IDex223Pool(pool).swap(recipient, true, amount0In.toInt256(), sqrtPriceLimitX96, false, abi.encode(msg.sender));
    }

    function swap0ForExact1(
        address pool,
        uint256 amount1Out,
        address recipient,
        uint160 sqrtPriceLimitX96
    ) external {
        IDex223Pool(pool).swap(recipient, true, -amount1Out.toInt256(), sqrtPriceLimitX96, false, abi.encode(msg.sender));
    }

    function swapExact1For0(
        address pool,
        uint256 amount1In,
        address recipient,
        uint160 sqrtPriceLimitX96
    ) external {
        IDex223Pool(pool).swap(recipient, false, amount1In.toInt256(), sqrtPriceLimitX96, false, abi.encode(msg.sender));
    }

    function swap1ForExact0(
        address pool,
        uint256 amount0Out,
        address recipient,
        uint160 sqrtPriceLimitX96
    ) external {
        IDex223Pool(pool).swap(recipient, false, -amount0Out.toInt256(), sqrtPriceLimitX96, false, abi.encode(msg.sender));
    }

    function swapToLowerSqrtPrice(
        address pool,
        uint160 sqrtPriceX96,
        address recipient
    ) external {
        IDex223Pool(pool).swap(recipient, true, type(int256).max-1, sqrtPriceX96, false, abi.encode(msg.sender));
    }

    function swapToHigherSqrtPrice(
        address pool,
        uint160 sqrtPriceX96,
        address recipient
    ) external {
        IDex223Pool(pool).swap(recipient, false, type(int256).max-1, sqrtPriceX96, false, abi.encode(msg.sender));
    }

    event SwapCallback(int256 amount0Delta, int256 amount1Delta);

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external override {
        address sender = abi.decode(data, (address));

        emit SwapCallback(amount0Delta, amount1Delta);

//        console.log('uniswapV3SwapCallback');
//        console.logInt(amount0Delta);
//        console.logInt(amount1Delta);

        if (amount0Delta > 0) {
            (address _token0_erc20, address _token0_erc223) = IDex223Pool(msg.sender).token0();

            IERC20Minimal(_token0_erc20).transferFrom(sender, msg.sender, uint256(amount0Delta));

        } else if (amount1Delta > 0) {
            (address _token1_erc20, address _token1_erc223) = IDex223Pool(msg.sender).token1();

            IERC20Minimal(_token1_erc20).transferFrom(sender, msg.sender, uint256(amount1Delta));

        } else {
            // if both are not gt 0, both must be 0.
            assert(amount0Delta == 0 && amount1Delta == 0);
        }
    }

    function mint(
        address pool,
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount
    ) external adjustableSender {
        IUniswapV3Pool(pool).mint(recipient, tickLower, tickUpper, amount, abi.encode(call_sender));
    }

    event MintCallback(uint256 amount0Owed, uint256 amount1Owed);

    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external override {
        address sender = abi.decode(data, (address));

        emit MintCallback(amount0Owed, amount1Owed);

        if (amount0Owed > 0) {
            (address _token0_erc20, address _token0_erc223) = IDex223Pool(msg.sender).token0();

            if(_erc223Deposits[sender][_token0_erc223] >= amount0Owed)
            {
                if(IERC20Minimal(_token0_erc223).allowance(address(this), address(this)) < amount0Owed)
                {
                    IERC20Minimal(_token0_erc223).approve(address(this), 2**256 - 1);
                }
                IERC20Minimal(_token0_erc223).transferFrom(address(this), msg.sender, amount0Owed);
            }
            else
            {
                IERC20Minimal(_token0_erc20).transferFrom(sender, msg.sender, amount0Owed);
            }
        }

        if (amount1Owed > 0) {
            (address _token1_erc20, address _token1_erc223) = IDex223Pool(msg.sender).token1();

            if(_erc223Deposits[sender][_token1_erc223] >= amount1Owed)
            {
                if(IERC20Minimal(_token1_erc223).allowance(address(this), address(this)) < amount1Owed)
                {
                    IERC20Minimal(_token1_erc223).approve(address(this), 2**256 - 1);
                }
                IERC20Minimal(_token1_erc223).transferFrom(address(this), msg.sender, amount1Owed);
            }
            else
            {
                IERC20Minimal(_token1_erc20).transferFrom(sender, msg.sender, amount1Owed);
            }
        }
    }

//    event FlashCallback(uint256 fee0, uint256 fee1);
//
//    function flash(
//        address pool,
//        address recipient,
//        uint256 amount0,
//        uint256 amount1,
//        uint256 pay0,
//        uint256 pay1
//    ) external {
//        IUniswapV3Pool(pool).flash(recipient, amount0, amount1, abi.encode(msg.sender, pay0, pay1));
//    }

//    function uniswapV3FlashCallback(
//        uint256 fee0,
//        uint256 fee1,
//        bytes calldata data
//    ) external override {
//        emit FlashCallback(fee0, fee1);
//
//        (address sender, uint256 pay0, uint256 pay1) = abi.decode(data, (address, uint256, uint256));
//
//        if (pay0 > 0) IERC20Minimal(IUniswapV3Pool(msg.sender).token0()).transferFrom(sender, msg.sender, pay0);
//        if (pay1 > 0) IERC20Minimal(IUniswapV3Pool(msg.sender).token1()).transferFrom(sender, msg.sender, pay1);
//    }
}
