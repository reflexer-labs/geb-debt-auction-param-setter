pragma solidity ^0.6.7;

import "ds-test/test.sol";
import "ds-token/token.sol";

import "./mock/MockTreasury.sol";
import "../DebtAuctionInitialParameterSetter.sol";

abstract contract Hevm {
    function warp(uint256) virtual public;
}

contract Feed {
    uint256 public priceFeedValue;
    bool public hasValidValue;
    constructor(uint256 initPrice, bool initHas) public {
        priceFeedValue = uint(initPrice);
        hasValidValue = initHas;
    }
    function set_val(uint newPrice) external {
        priceFeedValue = newPrice;
    }
    function set_has(bool newHas) external {
        hasValidValue = newHas;
    }
    function getResultWithValidity() external returns (uint256, bool) {
        return (priceFeedValue, hasValidValue);
    }
}

contract AccountingEngine {
    uint256 public initialDebtAuctionMintedTokens;
    uint256 public debtAuctionBidSize;

    function modifyParameters(bytes32 parameter, uint data) external {
        if (parameter == "debtAuctionBidSize") debtAuctionBidSize = data;
        else if (parameter == "initialDebtAuctionMintedTokens") initialDebtAuctionMintedTokens = data;
    }
}

contract DebtAuctionInitialParameterSetterTest is DSTest {
    Hevm hevm;

    DSToken systemCoin;

    Feed sysCoinFeed;
    Feed protocolTokenFeed;

    AccountingEngine accountingEngine;
    MockTreasury treasury;

    DebtAuctionInitialParameterSetter setter;

    uint256 periodSize = 3600;
    uint256 baseUpdateCallerReward = 5E18;
    uint256 maxUpdateCallerReward  = 10E18;
    uint256 perSecondCallerRewardIncrease = 1000192559420674483977255848; // 100% per hour

    uint256 minProtocolTokenAmountOffered = 0.5 ether;
    uint256 protocolTokenPremium = 700; // 30%
    uint256 bidTargetValue = 100000 ether; // 100K

    uint256 coinsToMint = 1E40;

    uint RAY = 10 ** 27;
    uint WAD = 10 ** 18;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        systemCoin = new DSToken("RAI");
        treasury = new MockTreasury(address(systemCoin));
        accountingEngine = new AccountingEngine();

        sysCoinFeed = new Feed(2.015 ether, true);
        protocolTokenFeed = new Feed(1000 ether, true);

        setter = new DebtAuctionInitialParameterSetter(
            address(protocolTokenFeed),
            address(sysCoinFeed),
            address(accountingEngine),
            address(treasury),
            periodSize,
            baseUpdateCallerReward,
            maxUpdateCallerReward,
            perSecondCallerRewardIncrease,
            minProtocolTokenAmountOffered,
            protocolTokenPremium,
            bidTargetValue
        );

        systemCoin.mint(address(treasury), coinsToMint);

        treasury.setTotalAllowance(address(setter), uint(-1));
        treasury.setPerBlockAllowance(address(setter), 10E45);
    }

    function test_setup() public {

    }
    function test_change_parameters() public {

    }
    function test_getNewDebtBid_null_price() public {

    }
    function test_getNewDebtBid_invalid_price() public {

    }
    function test_getNewDebtBid() public {

    }
    function test_getRawProtocolTokenAmount_null_price() public {

    }
    function test_getRawProtocolTokenAmount_invalid_price() public {

    }
    function test_getRawProtocolTokenAmount() public {

    }
    function test_getPremiumAdjustedProtocolTokenAmount_null_price() public {

    }
    function test_getPremiumAdjustedProtocolTokenAmount_invalid_price() public {

    }
    function test_getPremiumAdjustedProtocolTokenAmount() public {

    }
    function test_set_params_invalid_prices() public {

    }
    function test_set_params_null_prices() public {

    }
    function test_set_params_in_accounting_engine() public {

    }
    function test_set_params_get_rewarded() public {

    }
}
