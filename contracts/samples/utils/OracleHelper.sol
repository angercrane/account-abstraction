// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import "./IOracle.sol";

/// @title Helper functions for dealing with various forms of price feed oracles.
/// @notice Maintains a price cache and updates the current price if needed.
/// In the best case scenario we have a direct oracle from the token to the native asset.
/// Also support tokens that have no direct price oracle to the native asset.
/// Sometimes oracles provide the price in the opposite direction of what we need in the moment.
abstract contract OracleHelper {

    event TokenPriceUpdated(uint256 currentPrice, uint256 previousPrice);

    uint256 internal constant PRICE_DENOMINATOR = 1e6;

    /// @notice Actually equals 10^(token.decimals) value used for the price calculation
    uint256 private immutable tokenDecimals;

    /// @notice The Oracle contract used to fetch the latest token prices
    IOracle private tokenOracle;

    /// @notice The Oracle contract used to fetch the latest ETH prices
    IOracle private nativeOracle;

    /// @notice if 'true' we will fetch price directly from tokenOracle
    /// @notice if 'false' we will use nativeOracle to establish a token price through a shared third currency
    bool private tokenToNativeOracle;

    /// @notice 'true' if price is dollars-per-token, 'false' if price is tokens-per-dollar
    bool private tokenOracleReverse;

    /// @notice 'true' if price is dollars-per-ether, 'false' if price is ether-per-dollar
    bool private nativeOracleReverse;

    /// @notice The price update threshold percentage that triggers a price update (1e6 = 100%)
    uint256 private priceUpdateThreshold;

    /// @notice The price cache will be returned without even fetching the oracles for this number of seconds
    uint256 private cacheTimeToLive;

    /// @notice The cached token price from the Oracle
    uint256 public cachedPrice;

    /// @notice The timestamp of a block when the cached price was updated
    uint256 public cachedPriceTimestamp;

    constructor (
        IOracle _tokenOracle,
        IOracle _nativeAssetOracle,
        uint256 _tokenDecimals,
        uint256 _updateThreshold,
        uint256 _cacheTimeToLive,
        bool _tokenToNativeOracle,
        bool _tokenOracleReverse,
        bool _nativeOracleReverse
    ) {
        tokenDecimals = _tokenDecimals;
        _setOracleConfiguration(
            _tokenOracle,
            _nativeAssetOracle,
            _updateThreshold,
            _cacheTimeToLive,
            _tokenToNativeOracle,
            _tokenOracleReverse,
            _nativeOracleReverse);
    }

    function _setOracleConfiguration(
        IOracle _tokenOracle,
        IOracle _nativeAssetOracle,
        uint256 _updateThreshold,
        uint256 _cacheTimeToLive,
        bool _tokenToNativeOracle,
        bool _tokenOracleReverse,
        bool _nativeOracleReverse
    ) internal {
        require(_updateThreshold <= 1e6, "TPM: update threshold too high");
        require(_tokenOracle.decimals() == 8, "TPM:token oracle decimals not 8"); // TODO: support arbitrary oracle decimals
        // TODO: this is only needed if not direct feed
        //        require(_nativeAssetOracle.decimals() == 8, "TPM:native oracle decimals not 8");
    }

    /// @notice Updates the token price by fetching the latest price from the Oracle.
    function updatePrice(bool force) public returns (uint256 newPrice) {
        // TODO: if not 'force' also check age of cached price - no need to update every 5 seconds
        uint256 _cachedPrice = cachedPrice;
        uint256 tokenPrice = fetchPrice(tokenOracle);
        uint256 nativeAssetPrice = fetchPrice(nativeOracle);
        uint256 price = nativeAssetPrice * uint256(tokenDecimals) / tokenPrice;

        bool updateRequired = force ||
        uint256(price) * PRICE_DENOMINATOR / _cachedPrice > PRICE_DENOMINATOR + priceUpdateThreshold ||
        uint256(price) * PRICE_DENOMINATOR / _cachedPrice < PRICE_DENOMINATOR - priceUpdateThreshold;
        if (!updateRequired) {
            return _cachedPrice;
        }
        uint256 previousPrice = _cachedPrice;
        _cachedPrice = nativeAssetPrice * uint256(tokenDecimals) / tokenPrice;
        cachedPrice = _cachedPrice;
        emit TokenPriceUpdated(_cachedPrice, previousPrice);
        return _cachedPrice;
    }

    /// @notice Fetches the latest price from the given Oracle.
    /// @dev This function is used to get the latest price from the tokenOracle or nativeOracle.
    /// @param _oracle The Oracle contract to fetch the price from.
    /// @return price The latest price fetched from the Oracle.
    function fetchPrice(IOracle _oracle) internal view returns (uint256 price) {
        (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) = _oracle.latestRoundData();
        require(answer > 0, "TPM: Chainlink price <= 0");
        // 2 days old price is considered stale since the price is updated every 24 hours
        // solhint-disable-next-line not-rely-on-time
        require(updatedAt >= block.timestamp - 60 * 60 * 24 * 2, "TPM: Incomplete round");
        require(answeredInRound >= roundId, "TPM: Stale price");
        price = uint256(uint256(answer));
    }
}
