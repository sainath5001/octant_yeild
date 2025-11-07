// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

using SafeTransferLib for ERC20;

import {TokenizedStrategyBase} from "./TokenizedStrategyBase.sol";

interface IMorphoVault {
    function deposit(uint256 assets, address receiver) external returns (uint256);

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256);

    function convertToAssets(uint256 shares) external view returns (uint256);

    function convertToShares(uint256 assets) external view returns (uint256);
}

contract MorphoTokenizedStrategy is TokenizedStrategyBase {
    IMorphoVault public immutable morphoVault;
    uint256 public morphoShares;

    constructor(
        ERC20 underlying,
        IMorphoVault _morphoVault,
        address vault,
        address strategist,
        string memory name,
        string memory symbol,
        uint8 decimals
    ) TokenizedStrategyBase(underlying, vault, strategist, name, symbol, decimals) {
        morphoVault = _morphoVault;
    }

    function _afterDeposit(uint256 assets) internal override {
        if (assets == 0) return;
        underlying.safeApprove(address(morphoVault), assets);
        uint256 sharesOut = morphoVault.deposit(assets, address(this));
        underlying.safeApprove(address(morphoVault), 0);

        morphoShares += sharesOut;
        idleAssets -= assets;
    }

    function _beforeWithdraw(uint256 assets) internal override {
        if (assets <= idleAssets) return;

        uint256 shortfall = assets - idleAssets;
        uint256 sharesNeeded = morphoVault.convertToShares(shortfall);
        if (sharesNeeded > morphoShares) {
            sharesNeeded = morphoShares;
        }

        if (sharesNeeded == 0) revert Strategy__InvalidAmount();

        uint256 assetsOut = morphoVault.redeem(sharesNeeded, address(this), address(this));
        morphoShares -= sharesNeeded;
        idleAssets += assetsOut;

        if (idleAssets < assets) revert Strategy__InvalidAmount();
    }

    function _investedAssets() internal view override returns (uint256) {
        return morphoVault.convertToAssets(morphoShares);
    }
}
