// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IOctantPaymentSplitter {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event PayeeAdded(address indexed account, uint256 shares);
    event PaymentReleased(address indexed token, address indexed to, uint256 amount);
    event FeeNotified(address indexed token, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error PaymentSplitter__Unauthorized();
    error PaymentSplitter__ZeroAddress();
    error PaymentSplitter__ZeroShares();
    error PaymentSplitter__InvalidArrayLength();
    error PaymentSplitter__NothingToRelease();

    /*//////////////////////////////////////////////////////////////
                                 LOGIC
    //////////////////////////////////////////////////////////////*/

    function notifyFeeReceived(address token, uint256 amount) external;

    function release(address token, address account) external returns (uint256);

    function shares(address account) external view returns (uint256);

    function totalShares() external view returns (uint256);

    function totalReceived(address token) external view returns (uint256);

    function released(address token, address account) external view returns (uint256);
}
