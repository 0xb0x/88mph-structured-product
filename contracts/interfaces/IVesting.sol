// SPDX-License-Identifier: MIT
pragma solidity >=0.7.2;

interface IVesting {

    function withdraw(uint64 vestID)
        external
        returns (uint256 withdrawnAmount);

    function depositIDToVestID(address pool, uint64 deposit_id) external returns (uint64);
}