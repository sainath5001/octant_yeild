// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC1155} from "solmate/tokens/ERC1155.sol";
import {Owned} from "solmate/auth/Owned.sol";

import {ILeaderboard} from "./interfaces/ILeaderboard.sol";

contract Leaderboard is ERC1155, Owned, ILeaderboard {
    /*//////////////////////////////////////////////////////////////
                                 STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct BadgeConfig {
        uint256 id;
        uint256 threshold;
        string uri;
    }

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    address public aggregator;
    BadgeConfig[] public badges;
    mapping(address => uint256) public override totalDonated;
    mapping(uint256 => uint256) public override badgeThreshold;
    mapping(uint256 => string) internal _badgeUris;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error Leaderboard__BadgeExists();

    constructor(address _owner, address _aggregator, BadgeConfig[] memory _badges) Owned(_owner) {
        aggregator = _aggregator;

        for (uint256 i = 0; i < _badges.length; i++) {
            _addBadge(_badges[i]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                ADMIN API
    //////////////////////////////////////////////////////////////*/

    function setAggregator(address _aggregator) external onlyOwner {
        aggregator = _aggregator;
    }

    function addBadge(BadgeConfig calldata config) external onlyOwner {
        _addBadge(config);
    }

    /*//////////////////////////////////////////////////////////////
                                 CORE API
    //////////////////////////////////////////////////////////////*/

    function notifyDonation(address donor, uint256 amount, uint8 planId) external override {
        if (msg.sender != aggregator) revert Leaderboard__Unauthorized();
        if (amount == 0) return;

        uint256 cumulative = totalDonated[donor] + amount;
        totalDonated[donor] = cumulative;

        emit DonationRecorded(donor, amount, planId, cumulative);

        _maybeMintBadges(donor, cumulative);
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    function uri(uint256 id) public view override returns (string memory) {
        return _badgeUris[id];
    }

    function badgesLength() external view returns (uint256) {
        return badges.length;
    }

    /*//////////////////////////////////////////////////////////////
                               INTERNALS
    //////////////////////////////////////////////////////////////*/

    function _maybeMintBadges(address donor, uint256 cumulative) internal {
        for (uint256 i = 0; i < badges.length; i++) {
            BadgeConfig memory badge = badges[i];
            if (cumulative >= badge.threshold && balanceOf[donor][badge.id] == 0) {
                _mint(donor, badge.id, 1, "");
                emit BadgeMinted(donor, badge.id, badge.threshold);
            }
        }
    }

    function _addBadge(BadgeConfig memory config) internal {
        if (config.threshold == 0) revert Leaderboard__BadgeExists();
        if (badgeThreshold[config.id] != 0) revert Leaderboard__BadgeExists();
        badges.push(config);
        badgeThreshold[config.id] = config.threshold;
        _badgeUris[config.id] = config.uri;
    }
}
