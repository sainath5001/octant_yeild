// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ILeaderboard {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event DonationRecorded(address indexed donor, uint256 amount, uint8 planId, uint256 cumulative);
    event BadgeMinted(address indexed donor, uint256 indexed badgeId, uint256 threshold);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error Leaderboard__Unauthorized();

    /*//////////////////////////////////////////////////////////////
                                 LOGIC
    //////////////////////////////////////////////////////////////*/

    function notifyDonation(address donor, uint256 amount, uint8 planId) external;

    function totalDonated(address donor) external view returns (uint256);

    function badgeThreshold(uint256 badgeId) external view returns (uint256);
}
