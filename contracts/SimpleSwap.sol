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
        require(_checkContract(_tokenA), "SimpleSwap: TOKENA_IS_NOT_CONTRACT");
        require(_checkContract(_tokenB), "SimpleSwap: TOKENB_IS_NOT_CONTRACT");
        require(_tokenA != _tokenB, "SimpleSwap: TOKENA_TOKENB_IDENTICAL_ADDRESS");
        tokenA = ERC20(_tokenA);
        tokenB = ERC20(_tokenB);
    }

    /**
        Check whether a addres is a contract
     */
    function _checkContract(address addr) private view returns (bool) {
        // kaccak result of empty data
        bytes32 emptyAccountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
        bytes32 codehash;
        assembly {
            codehash := extcodehash(addr)
        }
        return (codehash != 0x0 && codehash != emptyAccountHash);
    }

    /// @notice Swap tokenIn for tokenOut with amountIn
    /// @param tokenIn The address of the token to swap from
    /// @param tokenOut The address of the token to swap to
    /// @param amountIn The amount of tokenIn to swap
    /// @return amountOut The amount of tokenOut received
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external nonReentrant returns (uint256) {
        // forces error, when tokenIn is not tokenA or tokenB
        require((tokenIn == address(tokenA) || tokenIn == address(tokenB)), "SimpleSwap: INVALID_TOKEN_IN");
        // forces error, when tokenOut is not tokenA or tokenB
        require((tokenOut == address(tokenA) || tokenOut == address(tokenB)), "SimpleSwap: INVALID_TOKEN_OUT");
        // forces error, when tokenIn is the same as tokenOut
        require(tokenIn != tokenOut, "SimpleSwap: IDENTICAL_ADDRESS");
        // forces error, when amountIn is zero
        require(amountIn > 0, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");

        address sender = _msgSender();
        uint256 originTokenIn = ERC20(tokenIn).balanceOf(address(this));
        uint256 originTokenOut = ERC20(tokenOut).balanceOf(address(this));

        // 算法1 (減法後面那串的結果的小數點會被捨去，相剪出來的值會大於實際可以轉出的值，所以這種算法會有錯):
        // uint256 amountOut = originTokenOut - (originTokenOut * originTokenIn / (originTokenIn + amountIn)) ;

        // 算法2:
        // x * y = x' * y' = k
        // originTokenOut * originTokenIn = (originTokenIn + amountIn) * (originTokenOut - amountOut)
        // originTokenOut * originTokenIn = originTokenIn * originTokenOut - originTokenIn * amountOut + amountIn * originTokenOut - amountIn * amountOut
        // originTokenIn * amountOut + amountIn * amountOut = originTokenIn * originTokenOut + amountIn * originTokenOut - originTokenOut * originTokenIn
        // amountOut * (originTokenIn + amountIn) = originTokenIn * originTokenOut + amountIn * originTokenOut - originTokenOut * originTokenIn
        // amountOut = originTokenIn * originTokenOut + amountIn * originTokenOut - originTokenOut * originTokenIn / (originTokenIn + amountIn)
        // amountOut = originTokenOut * (originTokenIn + amountIn - originTokenIn) / (originTokenIn + amountIn)
        // amountOut = originTokenOut * amountIn / (originTokenIn + amountIn)
        uint256 amountOut = (originTokenOut * amountIn) / (originTokenIn + amountIn);

        // forces error, when amountOut is zero
        require(amountOut > 0, "SimpleSwap: INSUFFICIENT_OUTPUT_AMOUNT");

        // Make sure k is the same after swap (有時會有無窮小數問題，所以這邊改成 >=)
        require(
            (originTokenIn + amountIn) * (originTokenOut - amountOut) >= originTokenIn * originTokenOut,
            "SimpleSwap: UNEXPECTED_K"
        );

        // Update reserves
        if (tokenIn == address(tokenA)) {
            reserveA = tokenA.balanceOf(address(this)) + amountIn;
            reserveB = tokenB.balanceOf(address(this)) - amountOut;
        } else if (tokenIn == address(tokenB)) {
            reserveA = tokenA.balanceOf(address(this)) - amountOut;
            reserveB = tokenB.balanceOf(address(this)) + amountIn;
        }

        // Action swap
        ERC20(tokenIn).transferFrom(sender, address(this), amountIn);
        ERC20(tokenOut).transfer(sender, amountOut);

        emit Swap(sender, tokenIn, tokenOut, amountIn, amountOut);

        return amountOut;
    }

    /// @notice Add liquidity to the pool
    /// @param amountAIn The amount of tokenA to add
    /// @param amountBIn The amount of tokenB to add
    /// @return amountA The actually amount of tokenA added
    /// @return amountB The actually amount of tokenB added
    /// @return liquidity The amount of liquidity minted
    function addLiquidity(uint256 amountAIn, uint256 amountBIn)
        external nonReentrant
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        // forces error, when tokenA amount is zero
        // forces error, when tokenB amount is zero
        require(amountAIn > 0 && amountBIn > 0, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");

        address _sender = _msgSender();
        uint256 _totalSupply = totalSupply();
        uint256 _liquidity;
        uint256 _actualAmountAIn = amountAIn;
        uint256 _actualAmountBIn = amountBIn;

        if (_totalSupply == 0) {
            _liquidity = Math.sqrt(amountAIn * amountBIn);
        } else {
            _liquidity = Math.min((amountAIn * _totalSupply) / reserveA, (amountBIn * _totalSupply) / reserveB);
            _actualAmountAIn = (_liquidity * reserveA) / _totalSupply;
            _actualAmountBIn = (_liquidity * reserveB) / _totalSupply;
        }

        // Update reserves
        reserveA = tokenA.balanceOf(address(this)) + _actualAmountAIn;
        reserveB = tokenB.balanceOf(address(this)) + _actualAmountBIn;

        // Action transfer in
        tokenA.transferFrom(_sender, address(this), _actualAmountAIn);
        tokenB.transferFrom(_sender, address(this), _actualAmountBIn);

        _mint(_sender, _liquidity);

        emit AddLiquidity(_sender, _actualAmountAIn, _actualAmountBIn, _liquidity);

        return (_actualAmountAIn, _actualAmountBIn, _liquidity);
    }

    /// @notice Remove liquidity from the pool
    /// @param liquidity The amount of liquidity to remove
    /// @return amountA The amount of tokenA received
    /// @return amountB The amount of tokenB received
    function removeLiquidity(uint256 liquidity) external nonReentrant returns (uint256, uint256) {
        // forces error, when lp token amount is zero
        require(liquidity > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY_BURNED");

        address _sender = _msgSender();
        uint256 _totalSupply = totalSupply();
        uint256 _amountAOut = (liquidity * reserveA) / _totalSupply;
        uint256 _amountBOut = (liquidity * reserveB) / _totalSupply;

        _transfer(_sender, address(this), liquidity);
        _burn(address(this), liquidity);

        // Update reserves
        reserveA = tokenA.balanceOf(address(this)) - _amountAOut;
        reserveB = tokenB.balanceOf(address(this)) - _amountBOut;

        // Action transfer out
        tokenA.transfer(_sender, _amountAOut);
        tokenB.transfer(_sender, _amountBOut);

        emit RemoveLiquidity(_sender, _amountAOut, _amountBOut, liquidity);

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
