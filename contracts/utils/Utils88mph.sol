// SPDX-License-Identifier: MIT
pragma solidity >=0.7.2;
pragma experimental ABIEncoderV2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

import {IWETH} from "../interfaces/IWETH.sol";
import {DInterest} from "../interfaces/DInterest.sol";
import {IZeroCouponBond} from "../interfaces/IZeroCouponBond.sol";

contract Utils88mph {

    IZeroCouponBond public zcb;
    DInterest public firb;
    IVesting public mph_vesting;
    /// amount of zero coupon bond minted
    uint256 zcb_minted;

    /// 
    function _init88mphUtils(
        address zero_coupon_bond,
        address _mph_vesting
    ) internal {
        zcb = IZeroCouponBond(zero_coupon_bond);
        firb = DInterest(zcb.pool());
        mph_vesting = IVesting(mph_vesting);
    }

    function _mintZcb(uint256 deposit_amt) internal returns (uint256) {
        require(deposit_amt > 0);
        uint256 amt_minted = zcb.mint(deposit_amt);
        return amt_minted;
    }

    function _redeemZcb(){
        require(zcb_minted > 0);
        zcb.redeem(uint(-1), true);
    }

    /// this calculation might be incorrect NOTE***
    function _getInterestRate(uint256 amt ) internal view returns(uint256) {
         uint256 interest_amt = firb.calculateInterestAmount(amt, zcb.maturationTimestamp - block.timestamp);
         return interest_amt.div(amt).mul(100);
    }

}