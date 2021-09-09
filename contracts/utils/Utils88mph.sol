// SPDX-License-Identifier: MIT
pragma solidity >=0.7.2;
pragma experimental ABIEncoderV2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

import {IWETH} from "../interfaces/IWETH.sol";
import {DInterest} from "../interfaces/DInterest.sol";
import {IVesting} from "../interfaces/IVesting.sol";
import {IUniswapV2Router02} from "../interfaces/IUniswapV2Router.sol";

contract Utils88mph {

    // IZeroCouponBond public zcb;
    DInterest public firb;
    IVesting public mph_vesting;
   
    IUniswapV2Router02 uRouterV2 ;

    uint64 firbDepositId;

    uint256 firbMaturationTimestamp;

    address public MPH_TOKEN;

    /// 
    function _init88mphUtils(
        address _firb,
        address _mph_vesting,
        address mph_token,
        address uRouter
    ) internal {
        firb = DInterest(_firb);
        mph_vesting = IVesting(mph_vesting);
        MPH_TOKEN = mph_token;
        uRouterV2 = IUniswapV2Router02(uRouter);
    }


    function _mintFirb(uint256 depositAmount, uint64 maturationTimestamp) internal returns (uint256){
        // ToDO approve FIRB contract to spend underlying
         (uint64 deposit_id,) = firb.deposit(depositAmount, maturationTimestamp);
         firbDepositId = deposit_id;
         firbMaturationTimestamp = _getDepositDetails().maturationTimestamp;
         return depositAmount;

    }
    function _withdrawAndSwapVestedMph(address to) internal {
        uint64 vestId = mph_vesting.depositIDToVestID(address(firb), firbDepositId);
        uint256 mph_withdrawn = mph_vesting.withdraw(vestId);
        _swap(MPH_TOKEN, to, mph_withdrawn);
    }

    function _getDepositDetails() internal returns (DInterest.Deposit memory) {
        return firb.getDeposit(firbDepositId);
    }

    function _firb_redeemable() internal view returns (bool){
        return block.timestamp > firbMaturationTimestamp ;
    }

    function _withdrawFirb() internal {
        require(_firb_redeemable());
        firb.withdraw(
            firbDepositId,
            uint(-1),
            false
        );
    }

    function _swap(address token0, address token1, uint amount) internal {
        // uint balance = IERC20(token0).balanceOf(address(this));
        require(amount > 0, 'ZERO_AMOUNT');
        IERC20(token0).approve(address(uRouterV2), amount);
        
        address[] memory path = new address[](3);
        path[0] = address(token0);
        path[1] = uRouterV2.WETH();
        path[2] = address( token1 );

        IUniswapV2Router02(uRouterV2).swapExactTokensForTokens(
            amount,
            1,
            path,
            address(this),
            block.timestamp + ( 15 * 60 )
        );

    }

}