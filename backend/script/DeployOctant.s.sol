// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {AggregatorVault} from "../src/AggregatorVault.sol";
import {Leaderboard} from "../src/Leaderboard.sol";
import {OctantPaymentSplitter} from "../src/OctantPaymentSplitter.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

contract DeployOctant is Script {
    struct DeploymentConfig {
        address owner;
        address keeper;
        address publicGoodsTreasury;
        address protocolPayee;
        ERC20 asset;
        uint16 protocolFeeBps;
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        DeploymentConfig memory cfg;
        cfg.owner = vm.envAddress("OWNER_ADDRESS");
        cfg.keeper = vm.envAddress("KEEPER_ADDRESS");
        cfg.publicGoodsTreasury = vm.envAddress("PUBLIC_GOODS_TREASURY");
        cfg.protocolPayee = vm.envAddress("PROTOCOL_PAYEE");
        cfg.asset = ERC20(vm.envAddress("ASSET_ADDRESS"));
        cfg.protocolFeeBps = uint16(vm.envUint("PROTOCOL_FEE_BPS"));

        vm.startBroadcast(deployerPrivateKey);

        Leaderboard.BadgeConfig[] memory badges = new Leaderboard.BadgeConfig[](3);
        badges[0] = Leaderboard.BadgeConfig({id: 1, threshold: 1e18, uri: "ipfs://badge-tier-1"});
        badges[1] = Leaderboard.BadgeConfig({id: 2, threshold: 10e18, uri: "ipfs://badge-tier-2"});
        badges[2] = Leaderboard.BadgeConfig({id: 3, threshold: 50e18, uri: "ipfs://badge-tier-3"});

        Leaderboard leaderboard = new Leaderboard(cfg.owner, cfg.owner, badges);

        address[] memory payees = new address[](1);
        payees[0] = cfg.protocolPayee;

        uint256[] memory shares = new uint256[](1);
        shares[0] = 100;

        OctantPaymentSplitter paymentSplitter = new OctantPaymentSplitter(cfg.owner, cfg.owner, payees, shares);

        uint64[] memory lockDurations = new uint64[](4);
        lockDurations[0] = 90 days;
        lockDurations[1] = 180 days;
        lockDurations[2] = 270 days;
        lockDurations[3] = 360 days;

        uint8[] memory planIds = new uint8[](3);
        planIds[0] = 1; // Basic
        planIds[1] = 2; // Standard
        planIds[2] = 3; // Premium

        uint32[] memory rebalanceIntervals = new uint32[](3);
        rebalanceIntervals[0] = 30 days;
        rebalanceIntervals[1] = 14 days;
        rebalanceIntervals[2] = 7 days;

        AggregatorVault vault = new AggregatorVault(
            cfg.asset,
            cfg.owner,
            cfg.keeper,
            cfg.publicGoodsTreasury,
            paymentSplitter,
            leaderboard,
            cfg.protocolFeeBps,
            lockDurations,
            planIds,
            rebalanceIntervals
        );

        leaderboard.setAggregator(address(vault));
        paymentSplitter.setVault(address(vault));

        vm.stopBroadcast();

        console2.log("AggregatorVault", address(vault));
        console2.log("Leaderboard", address(leaderboard));
        console2.log("OctantPaymentSplitter", address(paymentSplitter));
    }
}
