// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "v3-core/interfaces/IUniswapV3Factory.sol";
import "v3-periphery/interfaces/INonfungiblePositionManager.sol";
import "v3-periphery/interfaces/ISwapRouter.sol";
import "v3-core/interfaces/IUniswapV3Pool.sol";

import {IERC20Metadata as IERC20} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import "@openzeppelin/contracts/interfaces/IERC721Receiver.sol";

contract Rebalance is IERC721Receiver {
    IUniswapV3Factory immutable public factory;
    INonfungiblePositionManager immutable public positionManager;
    ISwapRouter immutable public swapRouter;

    address public owner;

    error UnAuthorized();
    error WrongContract();
    error SelfSend();
    error StillInRange();
    error NoLiquidity();
    error Expired();
    error TransferErr();

    constructor(address _factory, address _positionManager, address _swapRouter) {
        factory = IUniswapV3Factory(_factory);
        positionManager = INonfungiblePositionManager(_positionManager);
        swapRouter = ISwapRouter(_swapRouter);
        
        owner = msg.sender;
    }

    struct Instruction {
        // removing liquidity slippage
        uint256 amountRemoveMin0;
        uint256 amountRemoveMin1;

        // swapProportion, 1e4
        uint256 swapProportion;

        uint256 price0;
        uint256 price1;

        // slippage protection, 1e4
        uint256 slippage;

        // deadline, block.timestamp
        uint256 deadline;
    }

    /// @notice ERC721 callback function. Called on safeTransferFrom and does manipulation as configured in encoded Instruction parameter. 
    /// At the end the NFT (and any newly minted NFT) is returned to sender. The leftover tokens are sent to instruction.recipient.
    function onERC721Received(address, address from, uint256 tokenId, bytes calldata data) external override returns (bytes4) {
        if (msg.sender != address(positionManager)) revert WrongContract();
        if (from == address(this)) revert SelfSend();

        Instruction memory instruction = abi.decode(data, (Instruction));
        if (instruction.deadline < block.timestamp) revert Expired();

        // 1. Check out of range
        (,, address token0, address token1, uint24 fee, int24 tickLower, int24 tickUpper, uint128 liquidity,,,,) = positionManager.positions(tokenId);
        address pool = factory.getPool(token0, token1, fee);
        (, int24 tick,,,,,) = IUniswapV3Pool(pool).slot0();
        if (tick >= tickLower && tick <= tickUpper) revert StillInRange();
        if (liquidity == 0) revert NoLiquidity();

        // 2. Remove all liquidity
        positionManager.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams(
                tokenId,
                liquidity,
                instruction.amountRemoveMin0,
                instruction.amountRemoveMin1,
                block.timestamp
            )
        );
        positionManager.collect(
            INonfungiblePositionManager.CollectParams(
                tokenId,
                address(this),
                type(uint128).max,
                type(uint128).max
            )
        );
        positionManager.burn(tokenId);

        // 3. Swap part to the other side and cool operational
        if (tick > tickUpper) {
            uint256 amountIn = IERC20(token1).balanceOf(address(this)) * instruction.swapProportion / 1e4;
            uint256 amountOutMin = token0OutMin(token0, token1, instruction.price0, instruction.price1, instruction.slippage, amountIn);
            _swap(SwapParam(token1, token0, fee, amountIn, amountOutMin));
        } else {
            uint256 amountIn = IERC20(token0).balanceOf(address(this)) * instruction.swapProportion / 1e4;
            uint256 amountOutMin = token1OutMin(token0, token1, instruction.price0, instruction.price1, instruction.slippage, amountIn);
            _swap(SwapParam(token0, token1, fee, amountIn, amountOutMin));
        }

        return IERC721Receiver.onERC721Received.selector;
    }

    struct MintParam {
        address token0;
        address token1;
        uint24 fee;
        // +- current tick
        int24 tickDelta;
        // offset to swap, 1e4
        uint24 swapOffset;

        uint256 price0;
        uint256 price1;
        uint256 slippage;
        uint256 deadline;
    }

    function mint(MintParam calldata param) external returns (uint256 tokenId) {
        address token0 = param.token0;
        address token1 = param.token1;
        uint24 fee = param.fee;
        uint256 price0 = param.price0;
        uint256 price1 = param.price1;

        if (msg.sender != owner) revert UnAuthorized();
        if (param.deadline < block.timestamp) revert Expired();

        uint256 amount0 = IERC20(token0).balanceOf(address(this));
        uint256 value0 = (amount0 * price0) / 10 ** IERC20(token0).decimals();
        uint256 amount1 = IERC20(token1).balanceOf(address(this));
        uint256 value1 = (amount1 * price1) / 10 ** IERC20(token1).decimals();
        uint256 totalValue = value0 + value1;
        uint256 offsetProportion = value0 * 1e4 / totalValue;

        if (offsetProportion > 0.5e4 + param.swapOffset) {
            uint256 amountIn = (value0 - totalValue / 2) * 10 ** IERC20(token0).decimals() / price0;
            uint256 amountOutMin = token1OutMin(token0, token1, price0, price1, param.slippage, amountIn);
            _swap(SwapParam(token0, token1, fee, amountIn, amountOutMin));
        } else if (offsetProportion < 0.5e4 - param.swapOffset) {
            uint256 amountIn = (value1 - totalValue / 2) * 10 ** IERC20(token0).decimals() / price1;
            uint256 amountOutMin = token0OutMin(token0, token1, price0, price1, param.slippage, amountIn);
            _swap(SwapParam(token1, token0, fee, amountIn, amountOutMin));
        }
        
        address pool = factory.getPool(token0, token1, fee);
        (, int24 tick,,,,,) = IUniswapV3Pool(pool).slot0();
        int24 tickSpacing = IUniswapV3Pool(pool).tickSpacing();
        int24 validTick = tick / tickSpacing * tickSpacing;

        amount0 = IERC20(token0).balanceOf(address(this));
        amount1 = IERC20(token1).balanceOf(address(this));
        IERC20(token0).approve(address(positionManager), 0);
        IERC20(token0).approve(address(positionManager), amount0);
        IERC20(token1).approve(address(positionManager), 0);
        IERC20(token1).approve(address(positionManager), amount1);
        (tokenId,,,) = positionManager.mint(
            INonfungiblePositionManager.MintParams(
                token0,
                token1,
                fee,
                validTick - param.tickDelta * tickSpacing,
                validTick + param.tickDelta * tickSpacing,
                amount0,
                amount1,
                0,
                0,
                address(this),
                block.timestamp
            )
        );

        address[] memory tokens = new address[](2);
        tokens[0] = token0;
        tokens[1] = token1;
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        withdraw(tokens, tokenIds);
    }

    function token0OutMin(address token0, address token1, uint256 price0, uint256 price1, uint256 slippage, uint256 amountIn) public view returns (uint256 amountOutMin) {
        amountOutMin = 
            (amountIn * price1 * (1e4 - slippage) * 10 ** IERC20(token0).decimals()) 
            /
            (10 ** IERC20(token1).decimals() * price0 * 1e4);
    }

    function token1OutMin(address token0, address token1, uint256 price0, uint256 price1, uint256 slippage, uint256 amountIn) public view returns (uint256 amountOutMin) {
        amountOutMin = 
            (amountIn * price0 * (1e4 - slippage) * 10 ** IERC20(token1).decimals())
            /
            (10 ** IERC20(token0).decimals() * price1 * 1e4);
    }

    struct SwapParam {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        uint256 amountIn;
        uint256 amountOutMin;
    }

    function _swap(SwapParam memory param) internal returns (uint256 amountOut) {
        IERC20(param.tokenIn).approve(address(swapRouter), 0);
        IERC20(param.tokenIn).approve(address(swapRouter), param.amountIn);
        amountOut = swapRouter.exactInputSingle(ISwapRouter.ExactInputSingleParams(
            param.tokenIn,
            param.tokenOut,
            param.fee,
            address(this),
            block.timestamp,
            param.amountIn,
            param.amountOutMin,
            0
        ));
    }

    receive() external payable {}

    function withdraw(address[] memory tokens, uint256[] memory tokenIds) public {
        if (address(this).balance > 0) {
            (bool success,) = payable(owner).call{value: address(this).balance}("");
            if (!success) revert TransferErr();
        }

        for (uint256 i; i < tokens.length; ++i) {
            uint256 amount = IERC20(tokens[i]).balanceOf(address(this));
            if (amount > 0) {
                bool success = IERC20(tokens[i]).transfer(owner, amount);
                if (!success) revert TransferErr();
            }
        }

        for (uint256 j; j < tokenIds.length; ++j) {
            positionManager.transferFrom(address(this), owner, tokenIds[j]);
        }
    }
}