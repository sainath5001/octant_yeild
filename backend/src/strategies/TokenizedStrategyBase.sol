// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {ITokenizedStrategy} from "../interfaces/ITokenizedStrategy.sol";

abstract contract TokenizedStrategyBase is ERC20, ReentrancyGuard, ITokenizedStrategy {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    ERC20 public immutable underlying;
    address public immutable vault;
    address public strategist;

    uint256 internal idleAssets;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event StrategistUpdated(address indexed newStrategist);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyVault() {
        if (msg.sender != vault) revert Strategy__Unauthorized();
        _;
    }

    modifier onlyStrategist() {
        if (msg.sender != strategist) revert Strategy__Unauthorized();
        _;
    }

    constructor(
        ERC20 _underlying,
        address _vault,
        address _strategist,
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) ERC20(_name, _symbol, _decimals) {
        if (address(_underlying) == address(0) || _vault == address(0) || _strategist == address(0)) {
            revert Strategy__Unauthorized();
        }
        underlying = _underlying;
        vault = _vault;
        strategist = _strategist;
    }

    /*//////////////////////////////////////////////////////////////
                                ADMIN API
    //////////////////////////////////////////////////////////////*/

    function setStrategist(address newStrategist) external onlyStrategist {
        if (newStrategist == address(0)) revert Strategy__Unauthorized();
        strategist = newStrategist;
        emit StrategistUpdated(newStrategist);
    }

    /*//////////////////////////////////////////////////////////////
                               VAULT API
    //////////////////////////////////////////////////////////////*/

    function deposit(uint256 assets, address receiver)
        external
        override
        onlyVault
        nonReentrant
        returns (uint256 shares)
    {
        if (assets == 0) revert Strategy__InvalidAmount();

        shares = previewDeposit(assets);
        if (shares == 0) revert Strategy__ZeroShares();

        underlying.safeTransferFrom(msg.sender, address(this), assets);
        idleAssets += assets;

        _afterDeposit(assets);

        _mint(receiver, shares);
    }

    function withdraw(uint256 assets, address receiver, address owner)
        external
        override
        onlyVault
        nonReentrant
        returns (uint256 sharesBurned)
    {
        if (assets == 0) revert Strategy__InvalidAmount();

        sharesBurned = previewWithdraw(assets);
        if (sharesBurned == 0) revert Strategy__ZeroShares();

        _burn(owner, sharesBurned);

        _beforeWithdraw(assets);

        if (idleAssets < assets) revert Strategy__InvalidAmount();
        idleAssets -= assets;

        underlying.safeTransfer(receiver, assets);
    }

    function redeem(uint256 shares, address receiver, address owner)
        external
        override
        onlyVault
        nonReentrant
        returns (uint256 assets)
    {
        if (shares == 0) revert Strategy__InvalidAmount();

        assets = previewRedeem(shares);
        if (assets == 0) revert Strategy__InvalidAmount();

        _burn(owner, shares);

        _beforeWithdraw(assets);

        if (idleAssets < assets) revert Strategy__InvalidAmount();
        idleAssets -= assets;

        underlying.safeTransfer(receiver, assets);
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    function asset() external view override returns (address) {
        return address(underlying);
    }

    function totalAssets() public view override returns (uint256) {
        return idleAssets + _investedAssets();
    }

    function convertToShares(uint256 assets) public view override returns (uint256) {
        uint256 supply = totalSupply;
        if (supply == 0) {
            return assets;
        }
        uint256 total = totalAssets();
        if (total == 0) {
            return assets;
        }
        return assets.mulDivDown(supply, total);
    }

    function convertToAssets(uint256 shares) public view override returns (uint256) {
        uint256 supply = totalSupply;
        if (supply == 0) {
            return shares;
        }
        return shares.mulDivDown(totalAssets(), supply);
    }

    function previewDeposit(uint256 assets) public view override returns (uint256) {
        return convertToShares(assets);
    }

    function previewWithdraw(uint256 assets) public view override returns (uint256) {
        uint256 supply = totalSupply;
        uint256 total = totalAssets();
        if (supply == 0 || total == 0) return assets;
        return assets.mulDivUp(supply, total);
    }

    function previewRedeem(uint256 shares) public view override returns (uint256) {
        uint256 supply = totalSupply;
        if (supply == 0) return shares;
        return shares.mulDivDown(totalAssets(), supply);
    }

    function maxWithdraw(address owner) external view override returns (uint256) {
        uint256 sharesOwned = balanceOf[owner];
        if (sharesOwned == 0) return 0;
        return convertToAssets(sharesOwned);
    }

    function maxRedeem(address owner) external view override returns (uint256) {
        return balanceOf[owner];
    }

    /*//////////////////////////////////////////////////////////////
                               HOOKS
    //////////////////////////////////////////////////////////////*/

    function report(uint256 assetsGained) external onlyStrategist {
        _report(assetsGained);
    }

    function _afterDeposit(uint256 assets) internal virtual {}

    function _beforeWithdraw(uint256 assets) internal virtual {}

    function _investedAssets() internal view virtual returns (uint256);

    function _report(uint256 assetsDelta) internal virtual {
        if (assetsDelta > 0) {
            idleAssets += assetsDelta;
        }
    }
}
