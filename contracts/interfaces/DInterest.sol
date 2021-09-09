// SPDX-License-Identifier: MIT
pragma solidity >=0.7.2;
pragma experimental ABIEncoderV2;

interface DInterest {

    struct Deposit {
        uint256 virtualTokenTotalSupply; // depositAmount + interestAmount, behaves like a zero coupon bond
        uint256 interestRate; // interestAmount = interestRate * depositAmount
        uint256 feeRate; // feeAmount = feeRate * depositAmount
        uint256 averageRecordedIncomeIndex; // Average income index at time of deposit, used for computing deposit surplus
        uint64 maturationTimestamp; // Unix timestamp after which the deposit may be withdrawn, in seconds
        uint64 fundingID; // The ID of the associated Funding struct. 0 if not funded.
    }

    function deposit(
        uint256 depositAmount, 
        uint64 maturationTimestamp
    ) external returns (
        uint64 depositID, 
        uint256 interestAmount
    );

    function topupDeposit(
        uint64 depositID, 
        uint256 depositAmount
    ) external returns (
        uint256 interestAmount
    );

    function rolloverDeposit(uint64 depositID, uint64 maturationTimestamp) external returns (uint256 newDepositID, uint256 interestAmount);

    function withdraw(uint64 depositID, uint256 virtualTokenAmount, bool early) external returns (uint256 withdrawnStablecoinAmount);

    function calculateInterestAmount(uint256 depositAmount, uint256 depositPeriodInSeconds) external returns (uint256 interestAmount);

    function depositsLength() external returns (uint256);

    function getDeposit(uint64 depositID) external returns (DInterest.Deposit memory);

}