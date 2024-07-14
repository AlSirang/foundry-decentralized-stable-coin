// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

interface IDSCEngine {
    function depositCollateralAndMintDSC() external;

    /**
     * @param tokenCollateralAddress the address of the token to deposit as collateral
     * @param amountCollateral the amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral) external;

    function redeemCollateralForDSC() external;

    function redeemCollateral() external;

    function mintDSC(uint256 amountDscToMint) external;

    function burnDSC() external;

    function liquidate() external;

    function getHealthFactor() external view;
}
