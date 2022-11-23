// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ISimpleSwap } from "./interface/ISimpleSwap.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "hardhat/console.sol";

contract SimpleSwap is ISimpleSwap, ERC20, ReentrancyGuard {
    ERC20 public tokenA;
    ERC20 public tokenB;
    uint256 public reserveA;
    uint256 public reserveB;

    constructor(address _tokenA, address _tokenB) ERC20("TestErc20Token", "TET") {
        require(_isContract(_tokenA), "SimpleSwap: TOKENA_IS_NOT_CONTRACT");
        require(_isContract(_tokenB), "SimpleSwap: TOKENB_IS_NOT_CONTRACT");
        require(_tokenA != _tokenB, "SimpleSwap: TOKENA_TOKENB_IDENTICAL_ADDRESS");
        tokenA = ERC20(_tokenA);
        tokenB = ERC20(_tokenB);
    }

    /**
        Check whether a addres is a contract
     */
    function _isContract(address _addr) private view returns (bool) {
        // kaccak result of empty data
        bytes32 _emptyAccountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
        bytes32 _codehash;
        assembly {
            _codehash := extcodehash(_addr)
        }
        return (_codehash != 0x0 && _codehash != _emptyAccountHash);
    }

    /// @notice Swap tokenIn for tokenOut with amountIn
    /// @param _tokenIn The address of the token to swap from
    /// @param _tokenOut The address of the token to swap to
    /// @param _amountIn The amount of tokenIn to swap
    /// @return _amountOut The amount of tokenOut received
    function swap(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn
    ) external nonReentrant returns (uint256) {
        // forces error, when tokenIn is not tokenA or tokenB
        require(_tokenIn == address(tokenA) || _tokenIn == address(tokenB), "SimpleSwap: INVALID_TOKEN_IN");
        // forces error, when tokenOut is not tokenA or tokenB
        require(_tokenOut == address(tokenA) || _tokenOut == address(tokenB), "SimpleSwap: INVALID_TOKEN_OUT");
        // forces error, when tokenIn is the same as tokenOut
        require(_tokenIn != _tokenOut, "SimpleSwap: IDENTICAL_ADDRESS");
        // forces error, when amountIn is zero
        require(_amountIn > 0, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");

        address _sender = _msgSender();
        uint256 _originTokenIn = ERC20(_tokenIn).balanceOf(address(this));
        uint256 _originTokenOut = ERC20(_tokenOut).balanceOf(address(this));

        // 算法1: (減法後面那串的結果的小數點會被捨去，相剪出來的值會大於實際可以轉出的值，所以這種算法會有錯):
        // uint256 _amountOut = _originTokenOut - (_originTokenOut * _originTokenIn / (_originTokenIn + _amountIn)) ;

        // 算法2:
        // x * y = x' * y' = k
        // => _originTokenOut * _originTokenIn = (_originTokenIn + _amountIn) * (_originTokenOut - _amountOut)
        // => _originTokenOut * _originTokenIn = _originTokenIn * _originTokenOut - _originTokenIn * _amountOut + _amountIn * _originTokenOut - _amountIn * _amountOut
        // => _originTokenIn * _amountOut + _amountIn * _amountOut = _originTokenIn * _originTokenOut + _amountIn * _originTokenOut - _originTokenOut * _originTokenIn
        // => _amountOut * (_originTokenIn + _amountIn) = _originTokenIn * _originTokenOut + _amountIn * _originTokenOut - _originTokenOut * _originTokenIn
        // => _amountOut = originTokenIn * _originTokenOut + _amountIn * _originTokenOut - _originTokenOut * _originTokenIn / (_originTokenIn + _amountIn)
        // => _amountOut = _originTokenOut * (_originTokenIn + _amountIn - _originTokenIn) / (_originTokenIn + _amountIn)
        // => _amountOut = _originTokenOut * _amountIn / (_originTokenIn + _amountIn)
        uint256 _amountOut = (_originTokenOut * _amountIn) / (_originTokenIn + _amountIn);

        // forces error, when amountOut is zero
        require(_amountOut > 0, "SimpleSwap: INSUFFICIENT_OUTPUT_AMOUNT");

        // Make sure k is the same after swap (有時會有無窮小數問題，所以這邊改成 >=)
        require(
            (_originTokenIn + _amountIn) * (_originTokenOut - _amountOut) >= _originTokenIn * _originTokenOut,
            "SimpleSwap: UNEXPECTED_K"
        );

        // Update reserves
        if (_tokenIn == address(tokenA)) {
            reserveA = tokenA.balanceOf(address(this)) + _amountIn;
            reserveB = tokenB.balanceOf(address(this)) - _amountOut;
        } else if (_tokenIn == address(tokenB)) {
            reserveA = tokenA.balanceOf(address(this)) - _amountOut;
            reserveB = tokenB.balanceOf(address(this)) + _amountIn;
        }

        // Action swap
        ERC20(_tokenIn).transferFrom(_sender, address(this), _amountIn);
        ERC20(_tokenOut).transfer(_sender, _amountOut);

        emit Swap(_sender, _tokenIn, _tokenOut, _amountIn, _amountOut);

        return _amountOut;
    }

    /// @notice Add liquidity to the pool
    /// @param _amountAIn The amount of tokenA to add
    /// @param _amountBIn The amount of tokenB to add
    /// @return _actualAmountAIn The actually amount of tokenA added
    /// @return _actualAmountBIn The actually amount of tokenB added
    /// @return _liquidity The amount of liquidity minted
    function addLiquidity(uint256 _amountAIn, uint256 _amountBIn)
        external nonReentrant
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        // forces error, when tokenA amount is zero
        // forces error, when tokenB amount is zero
        require(_amountAIn > 0 && _amountBIn > 0, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");

        address _sender = _msgSender();
        uint256 _totalSupply = totalSupply();
        uint256 _liquidity;
        uint256 _actualAmountAIn;
        uint256 _actualAmountBIn;

        if (_totalSupply == 0) {
            _liquidity = Math.sqrt(_amountAIn * _amountBIn);
            _actualAmountAIn = _amountAIn;
            _actualAmountBIn = _amountBIn;
        } else {
            _liquidity = Math.min((_amountAIn * _totalSupply) / reserveA, (_amountBIn * _totalSupply) / reserveB);
            _actualAmountAIn = (_liquidity * reserveA) / _totalSupply;
            _actualAmountBIn = (_liquidity * reserveB) / _totalSupply;
        }

        // Update reserves
        reserveA = tokenA.balanceOf(address(this)) + _actualAmountAIn;
        reserveB = tokenB.balanceOf(address(this)) + _actualAmountBIn;

        // Action transfer in
        tokenA.transferFrom(_sender, address(this), _actualAmountAIn);
        tokenB.transferFrom(_sender, address(this), _actualAmountBIn);

        // Action add liquidity
        _mint(_sender, _liquidity);

        emit AddLiquidity(_sender, _actualAmountAIn, _actualAmountBIn, _liquidity);

        return (_actualAmountAIn, _actualAmountBIn, _liquidity);
    }

    /// @notice Remove liquidity from the pool
    /// @param _liquidity The amount of liquidity to remove
    /// @return _amountAOut The amount of tokenA received
    /// @return _amountBOut The amount of tokenB received
    function removeLiquidity(uint256 _liquidity) external nonReentrant returns (uint256, uint256) {
        // forces error, when lp token amount is zero
        require(_liquidity > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY_BURNED");

        address _sender = _msgSender();
        uint256 _totalSupply = totalSupply();
        uint256 _amountAOut = (_liquidity * reserveA) / _totalSupply;
        uint256 _amountBOut = (_liquidity * reserveB) / _totalSupply;

        // Update reserves
        reserveA = tokenA.balanceOf(address(this)) - _amountAOut;
        reserveB = tokenB.balanceOf(address(this)) - _amountBOut;

        // Action remove liquidity
        _transfer(_sender, address(this), _liquidity);
        _burn(address(this), _liquidity);

        // Action transfer out
        tokenA.transfer(_sender, _amountAOut);
        tokenB.transfer(_sender, _amountBOut);

        emit RemoveLiquidity(_sender, _amountAOut, _amountBOut, _liquidity);

        return (_amountAOut, _amountBOut);
    }

    /// @notice Get the reserves of the pool
    /// @return reserveA The reserve of tokenA
    /// @return reserveB The reserve of tokenB
    function getReserves() external view returns (uint256, uint256) {
        return (reserveA, reserveB);
    }

    /// @notice Get the address of tokenA
    /// @return tokenA The address of tokenA
    function getTokenA() external view returns (address) {
        return address(tokenA);
    }

    /// @notice Get the address of tokenB
    /// @return tokenB The address of tokenB
    function getTokenB() external view returns (address) {
        return address(tokenB);
    }
}
