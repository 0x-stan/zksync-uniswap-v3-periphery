// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol';
import '@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol';

import '../libraries/PoolAddress.sol';
import '../libraries/CallbackValidation.sol';

import './PeripheryPayments.sol';
import './PeripheryImmutableState.sol';

/// @title Liquidity management functions
/// @notice Internal functions for safely managing liquidity in Uniswap V3
abstract contract LiquidityManagement is IUniswapV3MintCallback, PeripheryImmutableState, PeripheryPayments {
    struct CreatePoolAndAddLiquidityParams {
        address token0;
        address token1;
        uint24 fee;
        uint160 sqrtPriceX96;
        int24 tickLower;
        int24 tickUpper;
        uint128 amount;
        address recipient;
    }

    /// @notice Called to add liquidity for a pool that does not exist
    function createPoolAndAddLiquidity(CreatePoolAndAddLiquidityParams memory params)
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        IUniswapV3Pool pool =
            IUniswapV3Pool(IUniswapV3Factory(factory).getPool(params.token0, params.token1, params.fee));
        if (address(pool) == address(0)) {
            pool = IUniswapV3Pool(IUniswapV3Factory(factory).createPool(params.token0, params.token1, params.fee));
        }

        // pool must not already be initialized
        pool.initialize(params.sqrtPriceX96);

        // max is irrelevant because the pool creator set the price
        return
            _addLiquidity(
                pool,
                PoolAddress.PoolKey({token0: params.token0, token1: params.token1, fee: params.fee}),
                params.recipient,
                params.tickLower,
                params.tickUpper,
                params.amount,
                type(uint256).max,
                type(uint256).max
            );
    }

    struct AddLiquidityParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint128 amount;
        uint256 amount0Max;
        uint256 amount1Max;
        address recipient;
    }

    /// @notice Add liquidity for an existing pool
    function addLiquidity(AddLiquidityParams memory params) internal returns (uint256 amount0, uint256 amount1) {
        PoolAddress.PoolKey memory poolKey =
            PoolAddress.PoolKey({token0: params.token0, token1: params.token1, fee: params.fee});

        return
            _addLiquidity(
                IUniswapV3Pool(PoolAddress.computeAddress(factory, poolKey)),
                poolKey,
                params.recipient,
                params.tickLower,
                params.tickUpper,
                params.amount,
                params.amount0Max,
                params.amount1Max
            );
    }

    struct MintCallbackData {
        // the pool key
        PoolAddress.PoolKey poolKey;
        // the address paying for the mint
        address payer;
        // used to protect the minter from price movement
        uint256 amount0Max;
        uint256 amount1Max;
    }

    function _addLiquidity(
        IUniswapV3Pool pool,
        PoolAddress.PoolKey memory poolKey,
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount,
        uint256 amount0Max,
        uint256 amount1Max
    ) private returns (uint256 amount0, uint256 amount1) {
        require(poolKey.token0 < poolKey.token1, 'Token order');
        MintCallbackData memory callbackData =
            MintCallbackData({payer: msg.sender, poolKey: poolKey, amount0Max: amount0Max, amount1Max: amount1Max});
        return pool.mint(recipient, tickLower, tickUpper, amount, abi.encode(callbackData));
    }

    /// @inheritdoc IUniswapV3MintCallback
    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external override {
        MintCallbackData memory decoded = abi.decode(data, (MintCallbackData));
        CallbackValidation.verifyCallback(factory, decoded.poolKey);
        require(amount0Owed <= decoded.amount0Max);
        require(amount1Owed <= decoded.amount1Max);

        if (amount0Owed > 0) pay(decoded.poolKey.token0, decoded.payer, msg.sender, amount0Owed);
        if (amount1Owed > 0) pay(decoded.poolKey.token1, decoded.payer, msg.sender, amount1Owed);
    }
}