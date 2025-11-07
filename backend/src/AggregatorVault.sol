// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";

import {ITokenizedStrategy} from "./interfaces/ITokenizedStrategy.sol";
import {ILeaderboard} from "./interfaces/ILeaderboard.sol";
import {IOctantPaymentSplitter} from "./interfaces/IOctantPaymentSplitter.sol";

contract AggregatorVault is ReentrancyGuard {
    using SafeTransferLib for ERC20;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event PlanConfigured(uint8 indexed planId, uint32 rebalanceInterval, bool active);
    event StrategyAdded(address indexed strategy);
    event StrategyUpdated(address indexed strategy, bool active, uint16 targetWeightBps);
    event DepositPosition(
        uint256 indexed positionId,
        address indexed owner,
        uint256 assets,
        uint256 shares,
        uint16 donationBps,
        uint64 lockupEnd,
        uint8 planId
    );
    event WithdrawPosition(
        uint256 indexed positionId,
        address indexed owner,
        uint256 assetsReturned,
        uint256 donationAmount,
        uint256 protocolFee
    );
    event Harvest(uint256 amount, address indexed paymentSplitter);
    event KeeperUpdated(address indexed newKeeper);
    event TreasuryUpdated(address indexed newTreasury);
    event PaymentSplitterUpdated(address indexed newPaymentSplitter);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error Aggregator__Unauthorized();
    error Aggregator__InvalidDonationBps();
    error Aggregator__InvalidPlan();
    error Aggregator__InvalidLockDuration();
    error Aggregator__InvalidAmount();
    error Aggregator__LockupActive();
    error Aggregator__PositionNotFound();
    error Aggregator__PositionClosed();
    error Aggregator__StrategyInactive();
    error Aggregator__StrategyMismatch();
    error Aggregator__InsufficientLiquidity();
    error Aggregator__ZeroAddress();
    error Aggregator__ArrayLengthMismatch();
    error Aggregator__StrategyAlreadyRegistered();

    /*//////////////////////////////////////////////////////////////
                                 STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct Plan {
        bool active;
        uint32 rebalanceInterval;
    }

    struct Position {
        address owner;
        uint256 shares;
        uint256 principal;
        uint256 donationBps;
        uint64 lockupEnd;
        uint8 planId;
        bool exited;
    }

    struct StrategyMeta {
        bool active;
        uint16 targetWeightBps;
        uint256 sharesOwned;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 public constant MAX_BPS = 10_000;

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    ERC20 public immutable asset;
    address public owner;
    address public keeper;
    address public publicGoodsTreasury;

    IOctantPaymentSplitter public paymentSplitter;
    ILeaderboard public leaderboard;

    uint16 public protocolFeeBps;

    uint256 public totalShares;
    uint256 public nextPositionId = 1;
    uint256 public accruedProtocolFees;

    mapping(uint8 => Plan) public plans;
    mapping(uint64 => bool) public allowedLockDurations;
    mapping(uint256 => Position) public positions;

    address[] public strategies;
    mapping(address => StrategyMeta) public strategyMeta;

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyOwner() {
        if (msg.sender != owner) revert Aggregator__Unauthorized();
        _;
    }

    modifier onlyKeeperOrOwner() {
        if (msg.sender != owner && msg.sender != keeper) revert Aggregator__Unauthorized();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        ERC20 _asset,
        address _owner,
        address _keeper,
        address _publicGoodsTreasury,
        IOctantPaymentSplitter _paymentSplitter,
        ILeaderboard _leaderboard,
        uint16 _protocolFeeBps,
        uint64[] memory _allowedLockDurations,
        uint8[] memory _planIds,
        uint32[] memory _rebalanceIntervals
    ) {
        if (address(_asset) == address(0)) revert Aggregator__ZeroAddress();
        if (_owner == address(0)) revert Aggregator__ZeroAddress();
        if (_publicGoodsTreasury == address(0)) revert Aggregator__ZeroAddress();
        if (address(_paymentSplitter) == address(0)) revert Aggregator__ZeroAddress();
        if (address(_leaderboard) == address(0)) revert Aggregator__ZeroAddress();
        if (_planIds.length != _rebalanceIntervals.length) revert Aggregator__ArrayLengthMismatch();

        asset = _asset;
        owner = _owner;
        keeper = _keeper;
        publicGoodsTreasury = _publicGoodsTreasury;
        paymentSplitter = _paymentSplitter;
        leaderboard = _leaderboard;
        protocolFeeBps = _protocolFeeBps;

        for (uint256 i = 0; i < _allowedLockDurations.length; i++) {
            allowedLockDurations[_allowedLockDurations[i]] = true;
        }

        for (uint256 i = 0; i < _planIds.length; i++) {
            plans[_planIds[i]] = Plan({active: true, rebalanceInterval: _rebalanceIntervals[i]});
            emit PlanConfigured(_planIds[i], _rebalanceIntervals[i], true);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                OWNER API
    //////////////////////////////////////////////////////////////*/

    function updateKeeper(address newKeeper) external onlyOwner {
        keeper = newKeeper;
        emit KeeperUpdated(newKeeper);
    }

    function updatePublicGoodsTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0)) revert Aggregator__ZeroAddress();
        publicGoodsTreasury = newTreasury;
        emit TreasuryUpdated(newTreasury);
    }

    function updatePaymentSplitter(IOctantPaymentSplitter newPaymentSplitter) external onlyOwner {
        if (address(newPaymentSplitter) == address(0)) revert Aggregator__ZeroAddress();
        paymentSplitter = newPaymentSplitter;
        emit PaymentSplitterUpdated(address(newPaymentSplitter));
    }

    function setProtocolFeeBps(uint16 newProtocolFeeBps) external onlyOwner {
        if (newProtocolFeeBps > MAX_BPS) revert Aggregator__InvalidDonationBps();
        protocolFeeBps = newProtocolFeeBps;
    }

    function configurePlan(uint8 planId, uint32 rebalanceInterval, bool active) external onlyOwner {
        plans[planId] = Plan({active: active, rebalanceInterval: rebalanceInterval});
        emit PlanConfigured(planId, rebalanceInterval, active);
    }

    function setAllowedLockDuration(uint64 lockDuration, bool allowed) external onlyOwner {
        allowedLockDurations[lockDuration] = allowed;
    }

    function addStrategy(address strategy) external onlyOwner {
        if (strategy == address(0)) revert Aggregator__ZeroAddress();
        if (strategyMeta[strategy].active) revert Aggregator__StrategyAlreadyRegistered();
        strategies.push(strategy);
        strategyMeta[strategy].active = true;
        emit StrategyAdded(strategy);
    }

    function updateStrategy(address strategy, bool active, uint16 targetWeightBps) external onlyOwner {
        StrategyMeta storage meta = strategyMeta[strategy];
        if (!meta.active && !active) revert Aggregator__StrategyInactive();
        meta.active = active;
        meta.targetWeightBps = targetWeightBps;
        emit StrategyUpdated(strategy, active, targetWeightBps);
    }

    /*//////////////////////////////////////////////////////////////
                                USER API
    //////////////////////////////////////////////////////////////*/

    function deposit(uint256 assets, uint16 donationBps, uint64 lockDuration, uint8 planId, address receiver)
        external
        nonReentrant
        returns (uint256 positionId)
    {
        if (assets == 0) revert Aggregator__InvalidAmount();
        if (donationBps > MAX_BPS) revert Aggregator__InvalidDonationBps();
        if (!allowedLockDurations[lockDuration]) revert Aggregator__InvalidLockDuration();
        if (!plans[planId].active) revert Aggregator__InvalidPlan();

        uint256 shares = _previewDeposit(assets);
        if (shares == 0) revert Aggregator__InvalidAmount();

        positionId = nextPositionId++;
        uint64 lockupEnd = uint64(block.timestamp + lockDuration);

        positions[positionId] = Position({
            owner: receiver,
            shares: shares,
            principal: assets,
            donationBps: donationBps,
            lockupEnd: lockupEnd,
            planId: planId,
            exited: false
        });

        totalShares += shares;

        asset.safeTransferFrom(msg.sender, address(this), assets);

        emit DepositPosition(positionId, receiver, assets, shares, donationBps, lockupEnd, planId);
    }

    function withdraw(uint256 positionId, address recipient) external nonReentrant returns (uint256 payout) {
        Position storage position = positions[positionId];
        if (position.owner == address(0)) revert Aggregator__PositionNotFound();
        if (position.exited) revert Aggregator__PositionClosed();
        if (msg.sender != position.owner) revert Aggregator__Unauthorized();
        if (block.timestamp < position.lockupEnd) revert Aggregator__LockupActive();

        uint256 assets = _previewRedeem(position.shares);

        _ensureLiquidity(assets);

        uint256 profit = assets > position.principal ? assets - position.principal : 0;
        uint256 donationAmount = (profit * position.donationBps) / MAX_BPS;
        uint256 protocolFee = (profit * protocolFeeBps) / MAX_BPS;

        if (donationAmount + protocolFee > profit) {
            uint256 excess = donationAmount + protocolFee - profit;
            if (protocolFee >= excess) {
                protocolFee -= excess;
            } else {
                donationAmount -= (excess - protocolFee);
                protocolFee = 0;
            }
        }

        accruedProtocolFees += protocolFee;

        payout = assets - donationAmount - protocolFee;

        totalShares -= position.shares;
        position.exited = true;

        if (donationAmount > 0) {
            asset.safeTransfer(publicGoodsTreasury, donationAmount);
            leaderboard.notifyDonation(position.owner, donationAmount, position.planId);
        }

        asset.safeTransfer(recipient, payout);

        emit WithdrawPosition(positionId, position.owner, assets, donationAmount, protocolFee);
    }

    function previewDeposit(uint256 assets) external view returns (uint256) {
        return _previewDeposit(assets);
    }

    function previewRedeem(uint256 shares) external view returns (uint256) {
        return _previewRedeem(shares);
    }

    /*//////////////////////////////////////////////////////////////
                              STRATEGY API
    //////////////////////////////////////////////////////////////*/

    function depositIntoStrategy(address strategy, uint256 assets) external onlyKeeperOrOwner nonReentrant {
        StrategyMeta storage meta = strategyMeta[strategy];
        if (!meta.active) revert Aggregator__StrategyInactive();
        if (assets == 0) revert Aggregator__InvalidAmount();
        if (ITokenizedStrategy(strategy).asset() != address(asset)) revert Aggregator__StrategyMismatch();

        asset.safeApprove(strategy, assets);
        uint256 sharesOut = ITokenizedStrategy(strategy).deposit(assets, address(this));
        asset.safeApprove(strategy, 0);

        if (sharesOut == 0) revert Aggregator__InvalidAmount();
        meta.sharesOwned += sharesOut;
    }

    function withdrawFromStrategy(address strategy, uint256 assets) external onlyKeeperOrOwner nonReentrant {
        StrategyMeta storage meta = strategyMeta[strategy];
        if (!meta.active) revert Aggregator__StrategyInactive();
        if (assets == 0) revert Aggregator__InvalidAmount();
        if (ITokenizedStrategy(strategy).asset() != address(asset)) revert Aggregator__StrategyMismatch();

        uint256 sharesNeeded = ITokenizedStrategy(strategy).previewWithdraw(assets);
        if (sharesNeeded > meta.sharesOwned) {
            sharesNeeded = meta.sharesOwned;
        }

        if (sharesNeeded == 0) revert Aggregator__InsufficientLiquidity();

        uint256 assetsReceived = ITokenizedStrategy(strategy).redeem(sharesNeeded, address(this), address(this));
        meta.sharesOwned -= sharesNeeded;

        if (assetsReceived < assets) revert Aggregator__InsufficientLiquidity();
    }

    function harvest() external onlyKeeperOrOwner nonReentrant {
        uint256 amount = accruedProtocolFees;
        if (amount == 0) return;

        accruedProtocolFees = 0;
        asset.safeApprove(address(paymentSplitter), amount);
        paymentSplitter.notifyFeeReceived(address(asset), amount);
        asset.safeApprove(address(paymentSplitter), 0);

        emit Harvest(amount, address(paymentSplitter));
    }

    /*//////////////////////////////////////////////////////////////
                               VIEW HELPERS
    //////////////////////////////////////////////////////////////*/

    function strategiesLength() external view returns (uint256) {
        return strategies.length;
    }

    function totalAssets() public view returns (uint256 assetsTotal) {
        assetsTotal = asset.balanceOf(address(this));

        for (uint256 i = 0; i < strategies.length; i++) {
            address strategy = strategies[i];
            StrategyMeta storage meta = strategyMeta[strategy];
            if (!meta.active || meta.sharesOwned == 0) continue;

            uint256 strategyAssets = ITokenizedStrategy(strategy).convertToAssets(meta.sharesOwned);
            assetsTotal += strategyAssets;
        }
    }

    /*//////////////////////////////////////////////////////////////
                               INTERNALS
    //////////////////////////////////////////////////////////////*/

    function _ensureLiquidity(uint256 requiredAssets) internal {
        uint256 balance = asset.balanceOf(address(this));
        if (balance >= requiredAssets) {
            return;
        }

        uint256 deficit = requiredAssets - balance;

        for (uint256 i = 0; i < strategies.length && deficit > 0; i++) {
            address strategy = strategies[i];
            StrategyMeta storage meta = strategyMeta[strategy];
            if (!meta.active || meta.sharesOwned == 0) continue;
            if (ITokenizedStrategy(strategy).asset() != address(asset)) continue;

            uint256 sharesNeeded = ITokenizedStrategy(strategy).previewWithdraw(deficit);
            if (sharesNeeded > meta.sharesOwned) {
                sharesNeeded = meta.sharesOwned;
            }

            if (sharesNeeded == 0) continue;

            uint256 assetsReceived = ITokenizedStrategy(strategy).redeem(sharesNeeded, address(this), address(this));
            meta.sharesOwned -= sharesNeeded;

            if (assetsReceived >= deficit) {
                deficit = 0;
            } else if (assetsReceived < deficit) {
                deficit -= assetsReceived;
            }
        }

        if (deficit > 0) revert Aggregator__InsufficientLiquidity();
    }

    function _previewDeposit(uint256 assets) internal view returns (uint256) {
        if (totalShares == 0) return assets;
        uint256 totalAssetValue = totalAssets();
        if (totalAssetValue == 0) return assets;
        return (assets * totalShares) / totalAssetValue;
    }

    function _previewRedeem(uint256 shares) internal view returns (uint256) {
        if (totalShares == 0) return 0;
        uint256 totalAssetValue = totalAssets();
        return (shares * totalAssetValue) / totalShares;
    }
}
