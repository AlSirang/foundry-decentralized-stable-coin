// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity 0.8.19;

/**
 * @title DSCEngine
 * @author Al Sirang
 * This system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg.
 * Stablecoin properties:
 * - Exogenous Collateral
 * - Dollar Pegged
 * - Algorithmically stable
 * This stable coin is only backed by wETH and wBTC. The DSC should be always "Overcollaterlized". At no point, should the value of all collateral <= the dollar($) backed value of all the DSC.
 *
 * @notice This is the core contract of the DSC system. it handles all the logic for minting and redeeming DSC, as well as the the depositing and withdrawing collateral.
 *
 * @notice this contract is VERY loosely based on the MakerDAO DSS (DAI) system.
 */
import {IDSCEngine} from "./interfaces/IDSCEngine.sol";
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzepplin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzepplin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract DSCEngine is IDSCEngine, ReentrancyGuard {
    /////////////////////////////////////////////
    ////////////////// Errors ///////////////////
    /////////////////////////////////////////////
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TransferFailed();
    error DSCEngine__MintFailed();
    error DSCEngine__BreakHealthFactor(uint256 healthFactor);
    error DSCEngine__TokenAddressesLengthIsNotEqualPriceFeedAddressLength();

    /////////////////////////////////////////////
    ////////////// State Variables //////////////
    /////////////////////////////////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    /// 200% overcollateralized
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 collateral)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DscMinted;

    address[] s_collateralTokens;
    DecentralizedStableCoin private immutable i_decentralizedStableCoin;

    /////////////////////////////////////////////
    /////////////////// Events //////////////////
    /////////////////////////////////////////////

    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    /////////////////////////////////////////////
    ///////////////// Modifiers /////////////////
    /////////////////////////////////////////////

    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    /////////////////////////////////////////////
    ///////////////// Functions /////////////////
    /////////////////////////////////////////////
    constructor(address[] memory tokenAddress, address[] memory priceFeedAddress, address dscAddress) {
        if (tokenAddress.length != priceFeedAddress.length) {
            revert DSCEngine__TokenAddressesLengthIsNotEqualPriceFeedAddressLength();
        }

        /// USD Price Feed
        /// E.g. ETH/USD, BTC/USD
        for (uint256 i = 0; i < tokenAddress.length; i++) {
            s_priceFeeds[tokenAddress[i]] = priceFeedAddress[i];
            s_collateralTokens.push(tokenAddress[i]);
        }

        i_decentralizedStableCoin = DecentralizedStableCoin(dscAddress);
    }

    /////////////////////////////////////////////
    //////////// External Functions /////////////
    /////////////////////////////////////////////

    function depositCollateralAndMintDSC() external {}

    /**
     * @dev See {IDSCEngine-depositCollateral}
     * @notice follows CEI
     *
     * Emits an {CollateralDeposited} event.
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;

        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);

        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateralForDSC() external {}

    function redeemCollateral() external {}

    /**
     * @notice follows CEI
     * @notice they must have more collateral value than  minimum threshold
     * @param amountDscToMint the amount of DSC to mint
     */
    function mintDSC(uint256 amountDscToMint) external moreThanZero(amountDscToMint) nonReentrant {
        s_DscMinted[msg.sender] += amountDscToMint;

        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_decentralizedStableCoin.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDSC() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}

    /////////////////////////////////////////////
    ///// Private & Internal View Functions /////
    /////////////////////////////////////////////

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUSD)
    {
        totalDscMinted = s_DscMinted[user];

        collateralValueInUSD = getAccountCollateralValue(user);
    }

    /**
     *
     * @notice Returns how close to liquidation a user is. If a user goes below 1, then they can get liquidated.
     */
    function _healthFactor(address user) internal view returns (uint256) {
        /// total DSC minted
        /// total collateral value
        (uint256 totalDscMinted, uint256 collateralValueInUSD) = _getAccountInformation(user);

        uint256 collateralAdjustedForThreshold = (collateralValueInUSD * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        /// $150 ETH / 100 DSC = 1.5
        /// 150 * 50  = 7500 /100  (75 / 100 DSC)  < 1

        /// 1000 ETH / 100 DSC
        /// 1000 * 50 = 50,000 /100 = (500 / 100 DSC)  > 1

        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    /**
     * @notice
     * 1. check health factor (do they have enough collateral?).
     * 2. Revert if health factor is broken
     *
     */
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);

        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreakHealthFactor(userHealthFactor);
        }
    }

    /////////////////////////////////////////////
    ///// Public & External View Functions //////
    /////////////////////////////////////////////

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        /// loop through each collateral token, get the amount they have deposited,
        /// and map it to the price, to the the USD value.

        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];

            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);

        (, int256 price,,,) = priceFeed.latestRoundData();

        // conversion:
        /// 1 ETH  = $1000
        /// the returned value from chainlink will be  1000 * 1e8

        /// (1000 * 1e{decimals} * (1e10))  1000 * 1e18
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }
}
