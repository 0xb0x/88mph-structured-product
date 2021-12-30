// SPDX-License-Identifier: MIT
pragma solidity >=0.7.2;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IVesting02} from "../interfaces/IVesting02.sol";
import {DInterest} from "../interfaces/DInterest.sol";
interface ZeroCouponBond {

    function pool() external view returns(DInterest);
    function vesting() external view returns(IVesting02);
    function depositID() external view returns(uint64);
    function stablecoin() external view returns(ERC20);
    function maturationTimestamp() external view returns(uint64);

    function decimals() external view returns (uint8);

    /**
        @notice Mint zero coupon bonds by depositing `depositAmount` stablecoins.
        @param depositAmount The amount to deposit for minting zero coupon bonds
        @return mintedAmount The amount of bonds minted
     */
    function mint(uint256 depositAmount)
        external
        returns (uint256 mintedAmount);
  
    /**
        @notice Mint zero coupon bonds by depositing `depositAmount` stablecoins.
        @param depositAmount The amount to deposit for minting zero coupon bonds
        @param minInterestAmount The minimum amount of fixed rate interest received
        @return mintedAmount The amount of bonds minted
     */
    function mint(uint256 depositAmount, uint256 minInterestAmount)
        external
        returns (uint256 mintedAmount);

    /**
        @notice Withdraws the underlying deposit from the DInterest pool.
     */
    function withdrawDeposit() external ;

    /**
        @notice Redeems zero coupon bonds 1-for-1 for the underlying stablecoins.
        @param amount The amount of zero coupon bonds to burn
        @param withdrawDepositIfNeeded True if withdrawDeposit() should be called if needed, false otherwise (to save gas)
     */
    function redeem(uint256 amount, bool withdrawDepositIfNeeded)
        external;


    /**
        Public getter functions
     */

    /**
        @notice Checks whether withdrawDeposit() needs to be called.
        @return True if withdrawDeposit() should be called, false otherwise.
     */
    function withdrawDepositNeeded() external view returns (bool) ;
}