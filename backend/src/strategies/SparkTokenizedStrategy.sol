// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

using SafeTransferLib for ERC20;

import {TokenizedStrategyBase} from "./TokenizedStrategyBase.sol";

interface ISparkPool {
    function deposit(address asset, uint256 amount, address onBehalfOf) external;

    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
}

contract SparkTokenizedStrategy is TokenizedStrategyBase {
    ISparkPool public immutable pool;
    ERC20 public immutable sToken;

    constructor(
        ERC20 underlying,
        ERC20 _sToken,
        ISparkPool _pool,
        address vault,
        address strategist,
        string memory name,
        string memory symbol,
        uint8 decimals
    ) TokenizedStrategyBase(underlying, vault, strategist, name, symbol, decimals) {
        pool = _pool;
        sToken = _sToken;
    }

    function _afterDeposit(uint256 assets) internal override {
        if (assets == 0) return;
        underlying.safeApprove(address(pool), assets);
        pool.deposit(address(underlying), assets, address(this));
        underlying.safeApprove(address(pool), 0);
        idleAssets -= assets;
    }

    function _beforeWithdraw(uint256 assets) internal override {
        if (assets <= idleAssets) return;

        uint256 shortfall = assets - idleAssets;
        uint256 withdrawn = pool.withdraw(address(underlying), shortfall, address(this));
        if (withdrawn < shortfall) revert Strategy__InvalidAmount();

        idleAssets += withdrawn;
    }

    function _investedAssets() internal view override returns (uint256) {
        return sToken.balanceOf(address(this));
    }
}
