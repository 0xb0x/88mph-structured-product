// SPDX-License-Identifier: MIT
pragma solidity >=0.7.2;

import {ZeroCouponBond} from "../interfaces/ZeroCouponBond.sol";
import {IVesting02} from "../interfaces/IVesting02.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

contract ZCBVault {
    using SafeMath for uint256;

    /// @dev address of the zcb vault
    ZeroCouponBond zeroCouponBond;

    /// @dev minimum interest to earn on bonds
    uint256 MIN_INTEREST;

    /// @dev percentage of assets to deposit into vault
    uint256 DEPOSIT_PERCENT;

    /// @dev amount of bonds minted
    uint256 bondsAmount;

    /// @dev amount of assets deposited
    uint256 assetDeposited;

    /// @dev address of mph token
    address MPH_TOKEN;

    event MintZCB(uint256 _amt, uint64 maturity);
    event WithdrawVestedMPH(uint256 amt);


    function __init_vault(address _zcb, address mph, uint256 minInterest, uint256 depositPercent) internal {
        require(_zcb != address(0));
        zeroCouponBond = ZeroCouponBond(_zcb);
        MPH_TOKEN = mph;
        MIN_INTEREST = minInterest;
        DEPOSIT_PERCENT = depositPercent;
    }

    function _mintZCB(uint256 amount) internal {
        require(amount > 0);
        zeroCouponBond.stablecoin().approve(address(zeroCouponBond, amount));

        uint256 amtMinted = zeroCouponBond.mint(amount, MIN_INTEREST);

        assetDeposited = assetDeposited.add(amount);
        bondsAmount = bondsAmount.add(amtMinted);

        emit MintZCB(amount, bondMaturity());
    }

    function redeemZcb() internal {
        // redeem all bonds
        zeroCouponBond.redeem(bondsAmount, true);
        bondsAmount = 0;
    }

    function _withdrawVestedMPH() internal returns(uint256) {
        address _pool = address(zeroCouponBond.pool());
        uint64 _deposit_id = ZeroCouponBond.depositID();
        uint64 _vestID = zeroCouponBond.vesting().depositIDToVestID(_pool, _deposit_id);
        uint256 vRewards = zeroCouponBond.vesting().withdraw(_vestID);

        emit WithdrawVestedMPH(vRewards);
        return vRewards;
    }

    function bondMaturity() public view returns(uint64){
        return zeroCouponBond.maturationTimestamp();
    }
    function bondReedemable() public view returns(bool){
        return block.timestamp > bondMaturity();
    }
}