// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Owned} from "solmate/auth/Owned.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";

import {IOctantPaymentSplitter} from "./interfaces/IOctantPaymentSplitter.sol";

contract OctantPaymentSplitter is IOctantPaymentSplitter, Owned, ReentrancyGuard {
    using SafeTransferLib for ERC20;

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    uint256 internal totalShares_;
    mapping(address => uint256) internal shares_;
    mapping(address => bool) public payeeExists;

    mapping(address => uint256) internal totalReceived_;
    mapping(address => mapping(address => uint256)) internal released_;

    address public vault;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error PaymentSplitter__PayeeExists();

    constructor(address _owner, address _vault, address[] memory payees, uint256[] memory shareValues) Owned(_owner) {
        if (_vault == address(0)) revert PaymentSplitter__ZeroAddress();
        if (payees.length != shareValues.length) revert PaymentSplitter__InvalidArrayLength();
        if (payees.length == 0) revert PaymentSplitter__InvalidArrayLength();

        vault = _vault;

        for (uint256 i = 0; i < payees.length; i++) {
            _addPayee(payees[i], shareValues[i]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                ADMIN API
    //////////////////////////////////////////////////////////////*/

    function setVault(address _vault) external onlyOwner {
        if (_vault == address(0)) revert PaymentSplitter__ZeroAddress();
        vault = _vault;
    }

    function addPayee(address account, uint256 shareValue) external onlyOwner {
        _addPayee(account, shareValue);
    }

    /*//////////////////////////////////////////////////////////////
                                 CORE API
    //////////////////////////////////////////////////////////////*/

    function notifyFeeReceived(address token, uint256 amount) external override {
        if (msg.sender != vault) revert PaymentSplitter__Unauthorized();
        if (amount == 0) return;
        if (totalShares_ == 0) revert PaymentSplitter__ZeroShares();

        ERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        totalReceived_[token] += amount;

        emit FeeNotified(token, amount);
    }

    function release(address token, address account) external override nonReentrant returns (uint256 payment) {
        if (shares_[account] == 0) revert PaymentSplitter__ZeroShares();

        (payment,) = _pendingPayment(token, account);
        if (payment == 0) revert PaymentSplitter__NothingToRelease();

        released_[token][account] += payment;

        ERC20(token).safeTransfer(account, payment);

        emit PaymentReleased(token, account, payment);
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    function pending(address token, address account) external view returns (uint256 payment, uint256 totalIncome) {
        return _pendingPayment(token, account);
    }

    /*//////////////////////////////////////////////////////////////
                               INTERNALS
    //////////////////////////////////////////////////////////////*/

    function _pendingPayment(address token, address account)
        internal
        view
        returns (uint256 payment, uint256 totalIncome)
    {
        uint256 totalReceivedForToken = totalReceived_[token];
        totalIncome = totalReceivedForToken;
        uint256 alreadyReleased = released_[token][account];

        payment = (totalReceivedForToken * shares_[account]) / totalShares_ - alreadyReleased;
    }

    function _addPayee(address account, uint256 shareValue) internal {
        if (account == address(0)) revert PaymentSplitter__ZeroAddress();
        if (shareValue == 0) revert PaymentSplitter__ZeroShares();
        if (payeeExists[account]) revert PaymentSplitter__PayeeExists();

        payeeExists[account] = true;
        shares_[account] = shareValue;
        totalShares_ += shareValue;

        emit PayeeAdded(account, shareValue);
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    function totalShares() external view override returns (uint256) {
        return totalShares_;
    }

    function shares(address account) external view override returns (uint256) {
        return shares_[account];
    }

    function totalReceived(address token) external view override returns (uint256) {
        return totalReceived_[token];
    }

    function released(address token, address account) external view override returns (uint256) {
        return released_[token][account];
    }
}
