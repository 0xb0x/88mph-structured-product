// SPDX-License-Identifier: MIT
pragma solidity >=0.7.2;

import {IUniswapV2Router02} from "../interfaces/IUniswapV2Router.sol";

contract UniswapUtils {
    
    IUniswapV2Router02 uRouter02 ;

    function _initUniswap(address _uRouter02) internal returns(uint){
        uRouter02 = IUniswapV2Router02(_uRouter02);
    }
    function _swap(address token0, address token1, uint amount) internal {
        // uint balance = IERC20(token0).balanceOf(address(this));
        require(amount > 0, 'ZERO_AMOUNT');
        IERC20(token0).approve(address(uRouter02), amount);
        
        address[] memory path = new address[](3);
        path[0] = address(token0);
        path[1] = uRouter02.WETH();
        path[2] = address( token1 );

        uint[] output = UniswapV2Router02(uRouter02).swapExactTokensForTokens(
            amount,
            1,
            path,
            address(this),
            block.timestamp + ( 15 * 60 )
        );
        return output[1];

    }
}