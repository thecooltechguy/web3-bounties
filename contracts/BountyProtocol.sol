// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IBountyValidator.sol";

// TODO: 
//  - Add logic for the protocol's fee/revenue
//  - Make all math operations safe with floating-point percentages/proportions, etc.
//  - Optimize contract for minimal gas
contract BountyProtocol {

    struct Winner {
        // address of the user that won the bounty
        address user;
        // timestamp for when the user won the bounty
        uint timestamp;
    }

    struct StakedSecurity {
        // the *total* amount of security tokens this user has staked for this bounty
        uint securityTokenAmount;
        
        // the *latest* timestamp for when this user staked some security
        uint stakedAt;

        // whether this user has claimed back their staked security tokens 
        // (which is only possible after a bounty expires, and if the bounty has no winner & has a positive number of staked security tokens
        bool claimed;
    }
   
    struct Bounty {
        // address of the user that created this bounty
        address creator;

        // the address of the validator smart contract for this bounty
        address validatorContractAddress;

        // the reward associated with this bounty
        address rewardTokenAddress;
        uint rewardTokenAmount;

        // the amount of reward tokens that have already been claimed by users (once a bounty expires without any winners)
        uint claimedRewardTokenAmount;

        // timestamp for when this bounty was created
        uint createdAt;

        // timestamp for when this bounty expires
        uint expiresAt;

        // mapping from user address to their corresponding staked security for this bounty

        // todo: should the number of unique users that can stake security for any given bounty woud be upper-bounded by the amount of reward tokens 
        // (since a single unit token is not further fractionally divisible).
        // if so, ensure that we meet this constraint as we update this mapping for this bounty during its lifetime
        mapping (address => StakedSecurity) stakedSecurities;
        uint totalStakedSecurityTokenAmount; // the total amount of staked security tokens across all users

        // the user, if any, that cracked this bounty & won its reward.
        Winner winner;

        // whether this bounty was cancelled.
        // note: a bounty can only be cancelled by the creator after its expiry, if this bounty was never won by anyone & no one staked any security (totalStakedSecurityTokenAmount > 0).
        bool cancelled;

        // timestamp for when this bounty was cancelled
        uint cancelledAt;
    }

    address public securityTokenAddress;

    uint public numBounties;
    mapping(uint => Bounty) public bounties;

    event BountyCreated(
        address indexed creator, 
        uint indexed bountyId, 
        address validatorContractAddress, 
        address rewardTokenAddress,
        uint rewardTokenAmount,
        uint createdAt,
        uint indexed expiresAt
    );

    event BountySecurityStaked(
        uint indexed bountyId, 
        address indexed user,
        uint userStakedSecurityTokenAmount,
        uint indexed userTotalStakedSecurityTokenAmount,
        uint bountyTotalStakedSecurityTokenAmount,
        uint stakedAt
    );

    event BountyAwarded(
        address indexed winner, 
        uint indexed bountyId, 
        uint indexed timestamp,
        address rewardTokenAddress,
        uint rewardTokenAmount,
        uint totalStakedSecurityTokenAmount
    );

    event BountyCancelled(
        uint indexed bountyId, 
        address indexed creator,
        uint indexed cancelledAt
    );

    constructor(address _securityTokenAddress) {
        securityTokenAddress = _securityTokenAddress;
    }

    function createBounty(address _validatorContractAddress, address _rewardTokenAddress, uint _rewardTokenAmount, uint _expiresAt) external returns(uint) {
        // verify that expiresAt is in the future
        require(_expiresAt > block.timestamp, "The bounty's expiry timestamp must be in the future.");

        uint bountyId = numBounties;

        Bounty storage bounty = bounties[bountyId];

        bounty.creator = msg.sender;
        bounty.validatorContractAddress = _validatorContractAddress;
        bounty.rewardTokenAddress = _rewardTokenAddress;
        bounty.rewardTokenAmount = _rewardTokenAmount;
        bounty.createdAt = block.timestamp;
        bounty.expiresAt = _expiresAt;

        // Call the validator contract to set its stored bounty id to be equal to this bounty's id
        IBountyValidator(_validatorContractAddress).setBountyId(bountyId);

        // Transfer the bounty's reward to this smart contract
        require(IERC20(_rewardTokenAddress).transferFrom(msg.sender, address(this), _rewardTokenAmount), "Couldn't transfer the bounty's reward to this smart contract.");
        
        // increment the number of bounties
        numBounties++;

        emit BountyCreated(
            bounty.creator, 
            bountyId, 
            bounty.validatorContractAddress, 
            bounty.rewardTokenAddress,
            bounty.rewardTokenAmount,
            bounty.createdAt,
            bounty.expiresAt
        );

        return bountyId;
    }

    function claimStakedBountyReward(uint bountyId) external {
        Bounty storage bounty = bounties[bountyId];
        require(block.timestamp > bounty.expiresAt, "Can only claim staked rewards for bounties that have expired.");
        require(bounty.winner.user == address(0), "Cannot claim staked rewards for a bounty that has a winner.");
        require(bounty.stakedSecurities[msg.sender].securityTokenAmount > 0, "Can only claim rewards for a positive number of staked security tokens.");
        require(!bounty.stakedSecurities[msg.sender].claimed, "Cannot re-claim staked rewards.");
        
        // note: the require check below should NEVER be triggerred, since, if a bounty has any staked security tokens, then it cannot be marked as cancelled.
        require(!bounty.cancelled, "Cannot claim staked rewards for a cancelled bounty.");

        // at this point, we know:
        // 1. the bounty has expired
        // 2. the bounty has no winner
        // 3. the user staked a positive number of security tokens for this bounty

        // first, let's transfer all of the user's staked security tokens back to them
        require(IERC20(securityTokenAddress).transfer(msg.sender, bounty.stakedSecurities[msg.sender].securityTokenAmount), "Couldn't transfer the security tokens back to this user.");

        // next, let's calculate the portion of the bounty's total reward to send to this user
        // todo: need to incorporate the protocol's fee/revenue
        // todo: need to take into account of the staked reward's timestamp

        // Stakes with more security tokens get a higher portion of the bounty's reward than stakes with fewer security tokens.
        // Once we add support for taking into account of the staked security timestamps, earlier stakes will get a higher portion than later stakes.
        
        // TODO: Need to verify math safety here with floating point numbers, etc.!!!
        uint amountRewardLeftToClaim = bounty.rewardTokenAmount - bounty.claimedRewardTokenAmount;
        uint bountyRewardForUser = bounty.rewardTokenAmount * bounty.stakedSecurities[msg.sender].securityTokenAmount / bounty.totalStakedSecurityTokenAmount;
        if (bountyRewardForUser > amountRewardLeftToClaim) {
            bountyRewardForUser = amountRewardLeftToClaim;
        }

        // transfer the user's potion of the bounty's total reward to them
        require(IERC20(bounty.rewardTokenAddress).transfer(msg.sender, bountyRewardForUser), "Couldn't transfer the user's portion of the bounty's reward to them.");
        
        // update this bounty's total amount of claimed reward tokens
        bounty.claimedRewardTokenAmount += bountyRewardForUser;

        // finally, mark that this user has claimed their staked reward for this bounty,
        // so that they cannot re-claim any staked rewards.
        bounty.stakedSecurities[msg.sender].claimed = true;
    }

    function stakeBountySecurity(uint bountyId, uint _securityTokenAmount) external {
        Bounty storage bounty = bounties[bountyId];

        require(block.timestamp < bounty.expiresAt, "Cannot stake security for an expired bounty.");
        require(bounty.winner.user == address(0), "Cannot stake security for a bounty that already has a winner.");
        require(_securityTokenAmount > 0, "You can only stake a positive amount of security tokens.");

        // todo: should the number of unique users that can stake security for any given bounty woud be upper-bounded by the amount of reward tokens 
        // (since a single unit token is not further fractionally divisible).
        // if so, ensure that we meet this constraint as we update this mapping for this bounty during its lifetime

        require(IERC20(securityTokenAddress).transferFrom(msg.sender, address(this), _securityTokenAmount), "Couldn't transfer the security tokens to this contract.");

        bounty.stakedSecurities[msg.sender].securityTokenAmount += _securityTokenAmount;
        bounty.totalStakedSecurityTokenAmount += _securityTokenAmount;
        bounty.stakedSecurities[msg.sender].stakedAt = block.timestamp;

        emit BountySecurityStaked(
            bountyId, 
            msg.sender,
            _securityTokenAmount,
            bounty.stakedSecurities[msg.sender].securityTokenAmount,
            bounty.totalStakedSecurityTokenAmount,
            bounty.stakedSecurities[msg.sender].stakedAt
        );
    }

    function setBountyWinner(uint bountyId, address winner) external {
        Bounty storage bounty = bounties[bountyId];

        require(msg.sender == bounty.validatorContractAddress, "You are unauthorized to set this bounty's winner.");
        require(bounty.expiresAt > block.timestamp, "Cannot set the winner for an expired bounty.");
        require(bounty.winner.user == address(0), "Cannot set the winner for a bounty that already has a winner.");

        // at this point, we know the following:
        // 1. the bounty's validator contract has asked us to set this bounty's winner
        // 2. the bounty hasn't expired yet
        // 3. the bounty doesn't have a winner set yet

        // therefore, let's set this bounty's winner!
        bounty.winner.user = winner;
        bounty.winner.timestamp = block.timestamp;

        // transfer the bounty's reward to the winner
        // todo: figure out the protocol's fee/revenue
        require(IERC20(bounty.rewardTokenAddress).transfer(winner, bounty.rewardTokenAmount), "Couldn't transfer the bounty's reward to the winner");

        // if the bounty has any staked security, then transfer all of the staked security to the winner as well
        if (bounty.totalStakedSecurityTokenAmount > 0) {
            require(IERC20(securityTokenAddress).transfer(winner, bounty.totalStakedSecurityTokenAmount), "Couldn't transfer the bounty's staked security tokens to the winner");
        }

        emit BountyAwarded(
            bounty.winner.user, 
            bountyId, 
            bounty.winner.timestamp,
            bounty.rewardTokenAddress,
            bounty.rewardTokenAmount,
            bounty.totalStakedSecurityTokenAmount
        );
    }

    function cancelBounty(uint bountyId) external {
        Bounty storage bounty = bounties[bountyId];

        require(msg.sender == bounty.creator, "You are unauthorized to cancel this bounty.");
        require(block.timestamp > bounty.expiresAt, "Can only cancel bounties that have expired.");

        // ensure that this bounty has no winner or staked security
        require (bounty.winner.user == address(0) && bounty.totalStakedSecurityTokenAmount == 0, "Cannot cancel a bounty that has a winner or some staked security.");

        // now, we know that the bounty has expired and has no winner or staked security.
        // before we proceed with cancelling this bounty, ensure that this bounty is not already cancelled.
        require(!bounty.cancelled, "Cannot re-cancel a cancelled bounty.");

        // at this point, we can cancel the bounty

        // return the bounty's reward back to the creator
        require(IERC20(bounty.rewardTokenAddress).transfer(msg.sender, bounty.rewardTokenAmount), "Couldn't return the bounty's reward back to the creator.");

        // finally, mark the bounty as cancelled
        bounty.cancelled = true;
        bounty.cancelledAt = block.timestamp;

        emit BountyCancelled(
            bountyId, 
            bounty.creator,
            bounty.cancelledAt
        );
    }
}