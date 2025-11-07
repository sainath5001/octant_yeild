// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {AggregatorVault} from "../src/AggregatorVault.sol";
import {Leaderboard} from "../src/Leaderboard.sol";
import {OctantPaymentSplitter} from "../src/OctantPaymentSplitter.sol";
import {ITokenizedStrategy} from "../src/interfaces/ITokenizedStrategy.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_, decimals_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockTokenizedStrategy is ITokenizedStrategy {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    ERC20 public immutable underlying;
    address public immutable vault;

    uint256 public totalShares;
    mapping(address => uint256) public shareBalance;

    constructor(ERC20 _underlying, address _vault) {
        underlying = _underlying;
        vault = _vault;
    }

    modifier onlyVault() {
        if (msg.sender != vault) revert Strategy__Unauthorized();
        _;
    }

    function asset() external view override returns (address) {
        return address(underlying);
    }

    function totalAssets() public view override returns (uint256) {
        return underlying.balanceOf(address(this));
    }

    function convertToShares(uint256 assets) public view override returns (uint256) {
        uint256 supply = totalShares;
        if (supply == 0) return assets;
        uint256 total = totalAssets();
        if (total == 0) return assets;
        return assets.mulDivDown(supply, total);
    }

    function convertToAssets(uint256 shares) public view override returns (uint256) {
        uint256 supply = totalShares;
        if (supply == 0) return shares;
        return shares.mulDivDown(totalAssets(), supply);
    }

    function deposit(uint256 assets, address receiver) external override onlyVault returns (uint256 sharesOut) {
        if (assets == 0) revert Strategy__InvalidAmount();
        sharesOut = convertToShares(assets);
        if (sharesOut == 0) revert Strategy__ZeroShares();

        underlying.safeTransferFrom(msg.sender, address(this), assets);

        totalShares += sharesOut;
        shareBalance[receiver] += sharesOut;
    }

    function withdraw(uint256 assets, address receiver, address owner)
        external
        override
        onlyVault
        returns (uint256 sharesBurned)
    {
        if (assets == 0) revert Strategy__InvalidAmount();
        sharesBurned = previewWithdraw(assets);
        if (sharesBurned == 0) revert Strategy__ZeroShares();
        if (shareBalance[owner] < sharesBurned) revert Strategy__InvalidAmount();

        shareBalance[owner] -= sharesBurned;
        totalShares -= sharesBurned;

        underlying.safeTransfer(receiver, assets);
    }

    function redeem(uint256 shares, address receiver, address owner)
        external
        override
        onlyVault
        returns (uint256 assetsOut)
    {
        if (shares == 0) revert Strategy__InvalidAmount();
        if (shareBalance[owner] < shares) revert Strategy__InvalidAmount();

        assetsOut = convertToAssets(shares);
        if (assetsOut == 0) revert Strategy__InvalidAmount();

        shareBalance[owner] -= shares;
        totalShares -= shares;

        underlying.safeTransfer(receiver, assetsOut);
    }

    function previewDeposit(uint256 assets) external view override returns (uint256) {
        return convertToShares(assets);
    }

    function previewWithdraw(uint256 assets) public view override returns (uint256) {
        uint256 supply = totalShares;
        uint256 total = totalAssets();
        if (supply == 0 || total == 0) return assets;
        return assets.mulDivUp(supply, total);
    }

    function previewRedeem(uint256 shares) external view override returns (uint256) {
        return convertToAssets(shares);
    }

    function maxWithdraw(address owner) external view override returns (uint256) {
        return convertToAssets(shareBalance[owner]);
    }

    function maxRedeem(address owner) external view override returns (uint256) {
        return shareBalance[owner];
    }

    function balanceOf(address owner) external view returns (uint256) {
        return shareBalance[owner];
    }
}

contract AggregatorVaultTest is Test {
    using SafeTransferLib for ERC20;

    AggregatorVault internal vault;
    MockERC20 internal asset;
    Leaderboard internal leaderboard;
    OctantPaymentSplitter internal paymentSplitter;

    address internal owner = address(this);
    address internal keeper = address(0x10);
    address internal publicGoodsTreasury = address(0x20);
    address internal protocolPayee = address(0x30);
    address internal user = address(0x40);

    uint16 internal constant PROTOCOL_FEE_BPS = 500; // 5%
    uint8 internal constant PLAN_BASIC = 1;
    uint8 internal constant PLAN_STANDARD = 2;
    uint8 internal constant PLAN_PREMIUM = 3;
    uint64 internal constant LOCK_3_MONTHS = 90 days;
    uint64 internal constant LOCK_6_MONTHS = 180 days;
    uint64 internal constant LOCK_9_MONTHS = 270 days;
    uint64 internal constant LOCK_12_MONTHS = 360 days;
    uint256 internal constant INITIAL_USER_FUNDS = 1_000e18;

    uint256 internal badgeId = 1;
    uint16 internal constant DONATION_BPS = 2_000; // 20%

    function setUp() public {
        asset = new MockERC20("Mock USD", "mUSD", 18);

        uint64[] memory lockDurations = new uint64[](4);
        lockDurations[0] = LOCK_3_MONTHS;
        lockDurations[1] = LOCK_6_MONTHS;
        lockDurations[2] = LOCK_9_MONTHS;
        lockDurations[3] = LOCK_12_MONTHS;

        uint8[] memory planIds = new uint8[](3);
        planIds[0] = PLAN_BASIC;
        planIds[1] = PLAN_STANDARD;
        planIds[2] = PLAN_PREMIUM;

        uint32[] memory rebalanceIntervals = new uint32[](3);
        rebalanceIntervals[0] = 30 days;
        rebalanceIntervals[1] = 14 days;
        rebalanceIntervals[2] = 7 days;

        Leaderboard.BadgeConfig[] memory badgeConfigs = new Leaderboard.BadgeConfig[](1);
        badgeConfigs[0] = Leaderboard.BadgeConfig({id: badgeId, threshold: 3e18, uri: "ipfs://badge"});

        leaderboard = new Leaderboard(owner, address(this), badgeConfigs);

        address[] memory payees = new address[](1);
        payees[0] = protocolPayee;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 100;
        paymentSplitter = new OctantPaymentSplitter(owner, address(this), payees, shares);

        vault = new AggregatorVault(
            asset,
            owner,
            keeper,
            publicGoodsTreasury,
            paymentSplitter,
            leaderboard,
            PROTOCOL_FEE_BPS,
            lockDurations,
            planIds,
            rebalanceIntervals
        );

        leaderboard.setAggregator(address(vault));
        paymentSplitter.setVault(address(vault));

        asset.mint(user, INITIAL_USER_FUNDS);
        vm.startPrank(user);
        asset.approve(address(vault), type(uint256).max);
        vm.stopPrank();
    }

    function testDepositCreatesPosition() public {
        uint256 depositAmount = 100e18;

        vm.prank(user);
        uint256 positionId = vault.deposit(depositAmount, DONATION_BPS, LOCK_3_MONTHS, PLAN_BASIC, user);

        AggregatorVault.Position memory position = _getPosition(positionId);
        assertEq(position.owner, user, "owner mismatch");
        assertEq(position.principal, depositAmount, "principal mismatch");
        assertEq(position.shares, depositAmount, "shares mismatch");
        assertEq(position.donationBps, DONATION_BPS, "donation bps mismatch");
        assertEq(position.planId, PLAN_BASIC, "plan mismatch");
        assertFalse(position.exited, "should not be exited");

        assertEq(asset.balanceOf(address(vault)), depositAmount, "vault asset balance");
        assertEq(vault.totalShares(), depositAmount, "total shares");
        assertEq(asset.balanceOf(user), INITIAL_USER_FUNDS - depositAmount, "user balance after deposit");
    }

    function testWithdrawSplitsYieldDonatesAndBadges() public {
        uint256 depositAmount = 100e18;
        uint256 profitAmount = 20e18;

        vm.prank(user);
        uint256 positionId = vault.deposit(depositAmount, DONATION_BPS, LOCK_3_MONTHS, PLAN_BASIC, user);

        vm.warp(block.timestamp + LOCK_3_MONTHS + 1);

        asset.mint(address(vault), profitAmount);

        uint256 userBalanceBefore = asset.balanceOf(user);

        vm.prank(user);
        uint256 payout = vault.withdraw(positionId, user);

        uint256 donation = (profitAmount * DONATION_BPS) / 10_000;
        uint256 protocolFee = (profitAmount * PROTOCOL_FEE_BPS) / 10_000;
        uint256 expectedPayout = depositAmount + profitAmount - donation - protocolFee;

        assertEq(payout, expectedPayout, "payout mismatch");
        assertEq(asset.balanceOf(user), userBalanceBefore + expectedPayout, "user balance");
        assertEq(asset.balanceOf(publicGoodsTreasury), donation, "treasury balance");
        assertEq(vault.accruedProtocolFees(), protocolFee, "accrued fees");
        assertEq(leaderboard.totalDonated(user), donation, "total donated");
        assertEq(leaderboard.balanceOf(user, badgeId), 1, "badge not minted");
    }

    function testHarvestAndPaymentSplitterRelease() public {
        uint256 depositAmount = 100e18;
        uint256 profitAmount = 20e18;

        vm.prank(user);
        uint256 positionId = vault.deposit(depositAmount, DONATION_BPS, LOCK_3_MONTHS, PLAN_BASIC, user);

        vm.warp(block.timestamp + LOCK_3_MONTHS + 1);
        asset.mint(address(vault), profitAmount);

        uint256 userBalanceBefore = asset.balanceOf(user);

        vm.prank(user);
        vault.withdraw(positionId, user);

        uint256 donation = (profitAmount * DONATION_BPS) / 10_000;
        uint256 protocolFee = (profitAmount * PROTOCOL_FEE_BPS) / 10_000;

        vm.prank(owner);
        vault.harvest();

        assertEq(vault.accruedProtocolFees(), 0, "fees not cleared");
        assertEq(asset.balanceOf(address(paymentSplitter)), protocolFee, "splitter balance");
        assertEq(paymentSplitter.totalReceived(address(asset)), protocolFee, "total received");
        assertEq(asset.balanceOf(address(vault)), 0, "vault residual");

        vm.prank(protocolPayee);
        uint256 releasedAmount = paymentSplitter.release(address(asset), protocolPayee);

        assertEq(releasedAmount, protocolFee, "released amount");
        assertEq(asset.balanceOf(protocolPayee), protocolFee, "payee balance");
        assertEq(
            asset.balanceOf(user),
            userBalanceBefore + depositAmount + profitAmount - donation - protocolFee,
            "user balance after release unaffected"
        );
    }

    function testStrategyDepositsAndWithdrawals() public {
        uint256 depositAmount = 200e18;
        vm.prank(user);
        vault.deposit(depositAmount, DONATION_BPS, LOCK_3_MONTHS, PLAN_STANDARD, user);

        MockTokenizedStrategy strategy = new MockTokenizedStrategy(asset, address(vault));

        vm.prank(owner);
        vault.addStrategy(address(strategy));

        uint256 strategyDeposit = 120e18;
        vm.prank(owner);
        vault.depositIntoStrategy(address(strategy), strategyDeposit);

        AggregatorVault.StrategyMeta memory meta = _getStrategyMeta(address(strategy));
        assertEq(meta.sharesOwned, strategyDeposit, "strategy shares");
        assertEq(asset.balanceOf(address(vault)), depositAmount - strategyDeposit, "vault idle balance");
        assertEq(strategy.totalAssets(), strategyDeposit, "strategy assets");

        uint256 withdrawAmount = 50e18;
        vm.prank(owner);
        vault.withdrawFromStrategy(address(strategy), withdrawAmount);

        meta = _getStrategyMeta(address(strategy));
        assertEq(meta.sharesOwned, strategyDeposit - withdrawAmount, "shares after withdraw");
        assertEq(
            asset.balanceOf(address(vault)),
            depositAmount - strategyDeposit + withdrawAmount,
            "vault balance after withdraw"
        );
        assertEq(strategy.totalAssets(), strategyDeposit - withdrawAmount, "strategy assets after withdraw");
    }

    function testWithdrawPullsLiquidityFromStrategies() public {
        uint256 depositAmount = 100e18;

        vm.prank(user);
        uint256 positionId = vault.deposit(depositAmount, DONATION_BPS, LOCK_3_MONTHS, PLAN_PREMIUM, user);

        MockTokenizedStrategy strategy = new MockTokenizedStrategy(asset, address(vault));
        vm.prank(owner);
        vault.addStrategy(address(strategy));

        vm.prank(owner);
        vault.depositIntoStrategy(address(strategy), depositAmount);

        // simulate yield generated inside the strategy
        asset.mint(address(strategy), 20e18);

        vm.warp(block.timestamp + LOCK_3_MONTHS + 1);

        vm.prank(user);
        vault.withdraw(positionId, user);

        AggregatorVault.StrategyMeta memory meta = _getStrategyMeta(address(strategy));
        assertEq(meta.sharesOwned, 0, "strategy shares should be zero");
        assertEq(asset.balanceOf(address(strategy)), 0, "strategy residual balance");
    }

    function _getPosition(uint256 positionId) internal view returns (AggregatorVault.Position memory position) {
        (
            position.owner,
            position.shares,
            position.principal,
            position.donationBps,
            position.lockupEnd,
            position.planId,
            position.exited
        ) = vault.positions(positionId);
    }

    function _getStrategyMeta(address strategy) internal view returns (AggregatorVault.StrategyMeta memory meta) {
        (meta.active, meta.targetWeightBps, meta.sharesOwned) = vault.strategyMeta(strategy);
    }
}
