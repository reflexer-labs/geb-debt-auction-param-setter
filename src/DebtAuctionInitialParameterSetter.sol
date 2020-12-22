pragma solidity ^0.6.7;

abstract contract OracleLike {
    function getResultWithValidity() virtual external view returns (uint256, bool);
}
abstract contract AccountingEngineLike {
    function modifyParameters(bytes32, uint256) virtual external;
}
abstract contract StabilityFeeTreasuryLike {
    function getAllowance(address) virtual external view returns (uint256, uint256);
    function systemCoin() virtual external view returns (address);
    function pullFunds(address, address, uint256) virtual external;
}

contract DebtAuctionInitialParameterSetter {
    // --- Auth ---
    mapping (address => uint) public authorizedAccounts;
    /**
     * @notice Add auth to an account
     * @param account Account to add auth to
     */
    function addAuthorization(address account) external isAuthorized {
        authorizedAccounts[account] = 1;
        emit AddAuthorization(msg.sender);
    }
    /**
     * @notice Remove auth from an account
     * @param account Account to remove auth from
     */
    function removeAuthorization(address account) external isAuthorized {
        authorizedAccounts[account] = 0;
        emit RemoveAuthorization(msg.sender);
    }
    /**
    * @notice Checks whether msg.sender can call an authed function
    **/
    modifier isAuthorized {
        require(authorizedAccounts[msg.sender] == 1, "DebtAuctionInitialParameterSetter/account-not-authorized");
        _;
    }

    // Delay between updates after which the reward starts to increase
    uint256 public updateDelay;
    // Starting reward for the feeReceiver
    uint256 public baseUpdateCallerReward;                                                      // [wad]
    // Max possible reward for the feeReceiver
    uint256 public maxUpdateCallerReward;                                                       // [wad]
    // Max delay taken into consideration when calculating the adjusted reward
    uint256 public maxRewardIncreaseDelay;                                                      // [seconds]
    // Rate applied to baseUpdateCallerReward every extra second passed beyond updateDelay seconds since the last update call
    uint256 public perSecondCallerRewardIncrease;                                               // [ray]
    // Last timestamp when the median was updated
    uint256 public lastUpdateTime;                                                              // [unix timestamp]
    // Min amount of protocol tokens that should be offered in the auction
    uint256 public minProtocolTokenAmountOffered;                                               // [wad]
    // Premium subtracted from the new amount of protocol tokens to be offered
    uint256 public protocolTokenPremium;                                                        // [thousand]
    // Value of the initial debt bid
    uint256 public bidTargetValue;                                                              // [wad]

    OracleLike               public protocolTokenOrcl;
    OracleLike               public systemCoinOrcl;
    AccountingEngineLike     public accountingEngine;
    StabilityFeeTreasuryLike public treasury;

    // --- Events ---
    event ModifyParameters(bytes32 parameter, address addr);
    event ModifyParameters(bytes32 parameter, uint256 data);
    event AddAuthorization(address account);
    event SetDebtAuctionInitialParameters(uint256 debtAuctionBidSize, uint256 initialDebtAuctionMintedTokens);
    event RemoveAuthorization(address account);
    event RewardCaller(address feeReceiver, uint256 amount);
    event FailRewardCaller(bytes revertReason, address finalFeeReceiver, uint256 reward);

    constructor(
      address protocolTokenOrcl_,
      address systemCoinOrcl_,
      address accountingEngine_,
      address treasury_,
      uint256 updateDelay_,
      uint256 baseUpdateCallerReward_,
      uint256 maxUpdateCallerReward_,
      uint256 perSecondCallerRewardIncrease_,
      uint256 minProtocolTokenAmountOffered_,
      uint256 protocolTokenPremium_,
      uint256 bidTargetValue_
    ) public {
        require(minProtocolTokenAmountOffered_ > 0, "DebtAuctionInitialParameterSetter/null-min-prot-amt");
        require(protocolTokenPremium_ < THOUSAND, "DebtAuctionInitialParameterSetter/invalid-prot-token-premium");
        require(both(both(protocolTokenOrcl_ != address(0), systemCoinOrcl_ != address(0)), accountingEngine_ != address(0)), "DebtAuctionInitialParameterSetter/invalid-contract-address");
        require(maxUpdateCallerReward_ > baseUpdateCallerReward_, "DebtAuctionInitialParameterSetter/invalid-max-reward");
        require(perSecondCallerRewardIncrease_ >= RAY, "DebtAuctionInitialParameterSetter/invalid-reward-increase");
        require(updateDelay_ > 0, "DebtAuctionInitialParameterSetter/null-update-delay");
        require(bidTargetValue_ > 0, "DebtAuctionInitialParameterSetter/invalid-bid-target-value");

        authorizedAccounts[msg.sender] = 1;

        protocolTokenOrcl              = OracleLike(protocolTokenOrcl_);
        systemCoinOrcl                 = OracleLike(systemCoinOrcl_);
        accountingEngine               = AccountingEngineLike(accountingEngine_);
        treasury                       = StabilityFeeTreasuryLike(treasury_);

        minProtocolTokenAmountOffered  = minProtocolTokenAmountOffered_;
        protocolTokenPremium           = protocolTokenPremium_;
        baseUpdateCallerReward         = baseUpdateCallerReward_;
        maxUpdateCallerReward          = maxUpdateCallerReward_;
        perSecondCallerRewardIncrease  = perSecondCallerRewardIncrease_;
        updateDelay                    = updateDelay_;
        bidTargetValue                 = bidTargetValue_;
        maxRewardIncreaseDelay         = uint(-1);

        emit AddAuthorization(msg.sender);
        emit ModifyParameters(bytes32("protocolTokenOrcl"), protocolTokenOrcl_);
        emit ModifyParameters(bytes32("systemCoinOrcl"), systemCoinOrcl_);
        emit ModifyParameters(bytes32("accountingEngine"), accountingEngine_);
        emit ModifyParameters(bytes32("treasury"), treasury_);
        emit ModifyParameters(bytes32("bidTargetValue"), bidTargetValue);
        emit ModifyParameters(bytes32("minProtocolTokenAmountOffered"), minProtocolTokenAmountOffered);
        emit ModifyParameters(bytes32("protocolTokenPremium"), protocolTokenPremium);
        emit ModifyParameters(bytes32("maxRewardIncreaseDelay"), uint(-1));
        emit ModifyParameters(bytes32("updateDelay"), updateDelay);
        emit ModifyParameters(bytes32("baseUpdateCallerReward"), baseUpdateCallerReward);
        emit ModifyParameters(bytes32("maxUpdateCallerReward"), maxUpdateCallerReward);
        emit ModifyParameters(bytes32("perSecondCallerRewardIncrease"), perSecondCallerRewardIncrease);
    }

    // --- Boolean Logic ---
    function both(bool x, bool y) internal pure returns (bool z) {
      assembly{ z := and(x, y)}
    }
    function either(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := or(x, y)}
    }

    // --- Math ---
    uint internal constant WAD      = 10 ** 18;
    uint internal constant RAY      = 10 ** 27;
    uint internal constant THOUSAND = 10 ** 3;
    function minimum(uint x, uint y) internal pure returns (uint z) {
        z = (x <= y) ? x : y;
    }
    function addition(uint x, uint y) internal pure returns (uint z) {
        z = x + y;
        require(z >= x);
    }
    function subtract(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }
    function multiply(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }
    function divide(uint x, uint y) internal pure returns (uint z) {
        require(y > 0);
        z = x / y;
        require(z <= x);
    }
    function wmultiply(uint x, uint y) internal pure returns (uint z) {
        z = multiply(x, y) / WAD;
    }
    function rmultiply(uint x, uint y) internal pure returns (uint z) {
        z = multiply(x, y) / RAY;
    }
    function rpower(uint x, uint n, uint base) internal pure returns (uint z) {
        assembly {
            switch x case 0 {switch n case 0 {z := base} default {z := 0}}
            default {
                switch mod(n, 2) case 0 { z := base } default { z := x }
                let half := div(base, 2)  // for rounding.
                for { n := div(n, 2) } n { n := div(n,2) } {
                    let xx := mul(x, x)
                    if iszero(eq(div(xx, x), x)) { revert(0,0) }
                    let xxRound := add(xx, half)
                    if lt(xxRound, xx) { revert(0,0) }
                    x := div(xxRound, base)
                    if mod(n,2) {
                        let zx := mul(z, x)
                        if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) { revert(0,0) }
                        let zxRound := add(zx, half)
                        if lt(zxRound, zx) { revert(0,0) }
                        z := div(zxRound, base)
                    }
                }
            }
        }
    }

    // --- Administration ---
    function modifyParameters(bytes32 parameter, address addr) external isAuthorized {
        require(addr != address(0), "DebtAuctionInitialParameterSetter/null-addr");
        if (parameter == "protocolTokenOrcl") protocolTokenOrcl = OracleLike(addr);
        else if (parameter == "systemCoinOrcl") systemCoinOrcl = OracleLike(addr);
        else if (parameter == "accountingEngine") accountingEngine = AccountingEngineLike(addr);
        else if (parameter == "treasury") {
          require(StabilityFeeTreasuryLike(addr).systemCoin() != address(0), "DebtAuctionInitialParameterSetter/treasury-coin-not-set");
      	  treasury = StabilityFeeTreasuryLike(addr);
        }
        else revert("DebtAuctionInitialParameterSetter/modify-unrecognized-param");
        emit ModifyParameters(parameter, addr);
    }
    function modifyParameters(bytes32 parameter, uint256 val) external isAuthorized {
        if (parameter == "minProtocolTokenAmountOffered") {
          require(val > 0, "DebtAuctionInitialParameterSetter/null-min-prot-amt");
          minProtocolTokenAmountOffered = val;
        }
        else if (parameter == "protocolTokenPremium") {
          require(val < THOUSAND, "DebtAuctionInitialParameterSetter/invalid-prot-token-premium");
          protocolTokenPremium = val;
        }
        else if (parameter == "baseUpdateCallerReward") {
            require(val < maxUpdateCallerReward, "DebtAuctionInitialParameterSetter/invalid-base-caller-reward");
            baseUpdateCallerReward = val;
        }
        else if (parameter == "maxUpdateCallerReward") {
          require(val > baseUpdateCallerReward, "DebtAuctionInitialParameterSetter/invalid-max-reward");
          maxUpdateCallerReward = val;
        }
        else if (parameter == "perSecondCallerRewardIncrease") {
          require(val >= RAY, "DebtAuctionInitialParameterSetter/invalid-reward-increase");
          perSecondCallerRewardIncrease = val;
        }
        else if (parameter == "maxRewardIncreaseDelay") {
          require(val > 0, "DebtAuctionInitialParameterSetter/invalid-max-increase-delay");
          maxRewardIncreaseDelay = val;
        }
        else if (parameter == "updateDelay") {
          require(val > 0, "DebtAuctionInitialParameterSetter/null-update-delay");
          updateDelay = val;
        }
        else if (parameter == "bidTargetValue") {
          require(val > 0, "DebtAuctionInitialParameterSetter/invalid-bid-target-value");
          bidTargetValue = val;
        }
        else if (parameter == "lastUpdateTime") {
          require(val > now, "DebtAuctionInitialParameterSetter/");
          lastUpdateTime = val;
        }
        else revert("DebtAuctionInitialParameterSetter/modify-unrecognized-param");
        emit ModifyParameters(parameter, val);
    }

    // --- Treasury Utils ---
    function treasuryAllowance() public view returns (uint256) {
        (uint total, uint perBlock) = treasury.getAllowance(address(this));
        return minimum(total, perBlock);
    }
    function getCallerReward() public view returns (uint256) {
        if (lastUpdateTime == 0) return baseUpdateCallerReward;
        uint256 timeElapsed = subtract(now, lastUpdateTime);
        if (timeElapsed < updateDelay) {
            return 0;
        }
        uint256 baseReward   = baseUpdateCallerReward;
        uint256 adjustedTime = subtract(timeElapsed, updateDelay);
        if (adjustedTime > 0) {
            adjustedTime = (adjustedTime > maxRewardIncreaseDelay) ? maxRewardIncreaseDelay : adjustedTime;
            baseReward = rmultiply(rpower(perSecondCallerRewardIncrease, adjustedTime, RAY), baseReward);
        }
        uint256 maxReward = minimum(maxUpdateCallerReward, treasuryAllowance() / RAY);
        if (baseReward > maxReward) {
            baseReward = maxReward;
        }
        return baseReward;
    }
    function rewardCaller(address proposedFeeReceiver, uint256 reward) internal {
        if (address(treasury) == proposedFeeReceiver) return;
        if (either(address(treasury) == address(0), reward == 0)) return;
        address finalFeeReceiver = (proposedFeeReceiver == address(0)) ? msg.sender : proposedFeeReceiver;
        try treasury.pullFunds(finalFeeReceiver, treasury.systemCoin(), reward) {
            emit RewardCaller(finalFeeReceiver, reward);
        }
        catch(bytes memory revertReason) {
            emit FailRewardCaller(revertReason, finalFeeReceiver, reward);
        }
    }

    // --- Setter ---
    function getNewDebtBid() external view returns (uint256 debtAuctionBidSize) {
        // Get token price
        (uint256 systemCoinPrice, bool validSysCoinPrice)   = systemCoinOrcl.getResultWithValidity();
        require(both(systemCoinPrice > 0, validSysCoinPrice), "DebtAuctionInitialParameterSetter/invalid-price");

        // Compute the bid size
        debtAuctionBidSize = divide(multiply(multiply(bidTargetValue, WAD), RAY), systemCoinPrice);
        if (debtAuctionBidSize < RAY) {
          debtAuctionBidSize = RAY;
        }
    }
    function getRawProtocolTokenAmount() external view returns (uint256 debtAuctionMintedTokens) {
        // Get token price
        (uint256 protocolTknPrice, bool validProtocolPrice) = protocolTokenOrcl.getResultWithValidity();
        require(both(validProtocolPrice, protocolTknPrice > 0), "DebtAuctionInitialParameterSetter/invalid-price");

        // Compute the amont of protocol tokens without the premium
        debtAuctionMintedTokens = divide(multiply(bidTargetValue, WAD), protocolTknPrice);

        // Take into account the minimum amount of protocol tokens to offer
        if (debtAuctionMintedTokens < minProtocolTokenAmountOffered) {
          debtAuctionMintedTokens = minProtocolTokenAmountOffered;
        }
    }
    function getPremiumAdjustedProtocolTokenAmount() external view returns (uint256 debtAuctionMintedTokens) {
        // Get token price
        (uint256 protocolTknPrice, bool validProtocolPrice) = protocolTokenOrcl.getResultWithValidity();
        require(both(validProtocolPrice, protocolTknPrice > 0), "DebtAuctionInitialParameterSetter/invalid-price");

        // Compute the amont of protocol tokens without the premium and apply it
        debtAuctionMintedTokens = divide(divide(multiply(multiply(bidTargetValue, WAD), protocolTokenPremium), protocolTknPrice), THOUSAND);

        // Take into account the minimum amount of protocol tokens to offer
        if (debtAuctionMintedTokens < minProtocolTokenAmountOffered) {
          debtAuctionMintedTokens = minProtocolTokenAmountOffered;
        }
    }
    function setDebtAuctionInitialParameters(address feeReceiver) external {
        // Check delay between calls
        require(either(subtract(now, lastUpdateTime) >= updateDelay, lastUpdateTime == 0), "DebtAuctionInitialParameterSetter/wait-more");
        // Get the caller's reward
        uint256 callerReward = getCallerReward();
        // Store the timestamp of the update
        lastUpdateTime = now;

        // Get token prices
        (uint256 protocolTknPrice, bool validProtocolPrice) = protocolTokenOrcl.getResultWithValidity();
        (uint256 systemCoinPrice, bool validSysCoinPrice)   = systemCoinOrcl.getResultWithValidity();
        require(both(validProtocolPrice, validSysCoinPrice), "DebtAuctionInitialParameterSetter/invalid-prices");
        require(both(protocolTknPrice > 0, systemCoinPrice > 0), "DebtAuctionInitialParameterSetter/null-prices");

        // Compute the scaled bid target value
        uint256 scaledBidTargetValue = multiply(bidTargetValue, WAD);

        // Compute the amont of protocol tokens without the premium
        uint256 initialDebtAuctionMintedTokens = divide(scaledBidTargetValue, protocolTknPrice);

        // Apply the premium
        initialDebtAuctionMintedTokens = divide(multiply(initialDebtAuctionMintedTokens, protocolTokenPremium), THOUSAND);

        // Take into account the minimum amount of protocol tokens to offer
        if (initialDebtAuctionMintedTokens < minProtocolTokenAmountOffered) {
          initialDebtAuctionMintedTokens = minProtocolTokenAmountOffered;
        }

        // Compute the debtAuctionBidSize as a RAD taking into account the minimum amount to bid
        uint256 debtAuctionBidSize = divide(multiply(scaledBidTargetValue, RAY), systemCoinPrice);
        if (debtAuctionBidSize < RAY) {
          debtAuctionBidSize = RAY;
        }

        // Set the debt bid and the associated protocol token amount in the accounting engine
        accountingEngine.modifyParameters("debtAuctionBidSize", debtAuctionBidSize);
        accountingEngine.modifyParameters("initialDebtAuctionMintedTokens", initialDebtAuctionMintedTokens);

        // Emit an event
        emit SetDebtAuctionInitialParameters(debtAuctionBidSize, initialDebtAuctionMintedTokens);

        // Pay the caller for updating the rate
        rewardCaller(feeReceiver, callerReward);
    }

    /*
    * @notice Manually set initial debt auction parameters
    * @param debtAuctionBidSize The initial debt auction bid size
    * @param initialDebtAuctionMintedTokens The initial amount of protocol tokens to mint in exchange for debtAuctionBidSize system coins
    */
    function manualSetDebtAuctionParameters(uint256 debtAuctionBidSize, uint256 initialDebtAuctionMintedTokens)
      external isAuthorized {
        accountingEngine.modifyParameters("debtAuctionBidSize", debtAuctionBidSize);
        accountingEngine.modifyParameters("initialDebtAuctionMintedTokens", initialDebtAuctionMintedTokens);
        emit SetDebtAuctionInitialParameters(debtAuctionBidSize, initialDebtAuctionMintedTokens);
    }
}
