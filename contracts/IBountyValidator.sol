// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

interface IBountyValidator {
    // In all validator contracts, this function should only be callable by the BountyProtocol smart contract, and no one else!
    function setBountyId(uint _bountyId) external;
}