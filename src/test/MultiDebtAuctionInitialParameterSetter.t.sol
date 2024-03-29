pragma solidity ^0.6.7;

import "ds-test/test.sol";
import "ds-token/token.sol";

import "./mock/MockTreasury.sol";
import "../MultiDebtAuctionInitialParameterSetter.sol";

abstract contract Hevm {
    function warp(uint256) virtual public;
}

contract Attacker {
    function doManualSetDebtAuctionParameters(address setter, uint256 debtAuctionBidSize, uint256 initialDebtAuctionMintedTokens) public {
        MultiDebtAuctionInitialParameterSetter(setter).manualSetDebtAuctionParameters(debtAuctionBidSize, initialDebtAuctionMintedTokens);
    }
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

    function modifyParameters(bytes32, bytes32 parameter, uint data) external {
        if (parameter == "debtAuctionBidSize") debtAuctionBidSize = data;
        else if (parameter == "initialDebtAuctionMintedTokens") initialDebtAuctionMintedTokens = data;
    }
}

contract MultiDebtAuctionInitialParameterSetterTest is DSTest {
    Hevm hevm;

    DSToken systemCoin;

    Feed sysCoinFeed;
    Feed protocolTokenFeed;

    AccountingEngine accountingEngine;
    MultiMockTreasury treasury;

    MultiDebtAuctionInitialParameterSetter setter;

    uint256 periodSize = 3600;
    uint256 baseUpdateCallerReward = 5E18;
    uint256 maxUpdateCallerReward  = 10E18;
    uint256 perSecondCallerRewardIncrease = 1000192559420674483977255848; // 100% per hour
    uint256 maxRewardIncreaseDelay = 3 hours;

    uint256 minProtocolTokenAmountOffered = 0.5 ether;
    uint256 protocolTokenPremium = 700; // 30%
    uint256 bidTargetValue = 100000 ether; // 100K

    uint256 coinsToMint = 1E40;

    bytes32 coinName = "BAI";

    uint RAY = 10 ** 27;
    uint WAD = 10 ** 18;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        systemCoin = new DSToken("RAI", "RAI");
        treasury = new MultiMockTreasury(address(systemCoin));
        accountingEngine = new AccountingEngine();

        sysCoinFeed = new Feed(2.015 ether, true);
        protocolTokenFeed = new Feed(1000 ether, true);

        setter = new MultiDebtAuctionInitialParameterSetter(
            coinName,
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

        treasury.setTotalAllowance(coinName, address(setter), uint(-1));
        treasury.setPerBlockAllowance(coinName, address(setter), 10E45);
    }

    function test_setup() public {
        assertEq(setter.authorizedAccounts(address(this)), 1);

        assertTrue(address(setter.protocolTokenOrcl()) == address(protocolTokenFeed));
        assertTrue(address(setter.systemCoinOrcl()) == address(sysCoinFeed));
        assertTrue(address(setter.accountingEngine()) == address(accountingEngine));
        assertTrue(address(setter.treasury()) == address(treasury));

        assertEq(setter.coinName(), coinName);
        assertEq(setter.updateDelay(), periodSize);
        assertEq(setter.minProtocolTokenAmountOffered(), minProtocolTokenAmountOffered);
        assertEq(setter.protocolTokenPremium(), protocolTokenPremium);
        assertEq(setter.baseUpdateCallerReward(), baseUpdateCallerReward);
        assertEq(setter.maxUpdateCallerReward(), maxUpdateCallerReward);

        assertEq(setter.perSecondCallerRewardIncrease(), perSecondCallerRewardIncrease);
        assertEq(setter.bidTargetValue(), bidTargetValue);
    }
    function testFail_getNewDebtBid_null_price() public {
        sysCoinFeed.set_val(0);
        setter.getNewDebtBid();
    }
    function testFail_getNewDebtBid_invalid_price() public {
        sysCoinFeed.set_has(false);
        setter.getNewDebtBid();
    }
    function test_getNewDebtBid() public {
        assertEq(setter.getNewDebtBid(), 49627791563275434243176178660049627791563275434243);
    }
    function testFail_getRawProtocolTokenAmount_null_price() public {
        protocolTokenFeed.set_val(0);
        setter.getRawProtocolTokenAmount();
    }
    function testFail_getRawProtocolTokenAmount_invalid_price() public {
        protocolTokenFeed.set_has(false);
        setter.getRawProtocolTokenAmount();
    }
    function test_getRawProtocolTokenAmount() public {
        assertEq(setter.getRawProtocolTokenAmount(), 100 ether);
    }
    function testFail_getPremiumAdjustedProtocolTokenAmount_null_price() public {
        protocolTokenFeed.set_val(0);
        setter.getPremiumAdjustedProtocolTokenAmount();
    }
    function testFail_getPremiumAdjustedProtocolTokenAmount_invalid_price() public {
        protocolTokenFeed.set_has(false);
        setter.getPremiumAdjustedProtocolTokenAmount();
    }
    function test_getPremiumAdjustedProtocolTokenAmount() public {
        assertEq(setter.getPremiumAdjustedProtocolTokenAmount(), 70 ether);
    }
    function testFail_set_params_invalid_prot_price() public {
        protocolTokenFeed.set_has(false);
        setter.setDebtAuctionInitialParameters(address(this));
    }
    function testFail_set_params_invalid_sys_coin_price() public {
        sysCoinFeed.set_has(false);
        setter.setDebtAuctionInitialParameters(address(this));
    }
    function testFail_set_params_null_sys_coin_price() public {
        sysCoinFeed.set_val(0);
        setter.setDebtAuctionInitialParameters(address(this));
    }
    function testFail_set_params_null_prot_price() public {
        protocolTokenFeed.set_val(0);
        setter.setDebtAuctionInitialParameters(address(this));
    }
    function testFail_set_params_before_period_elapsed() public {
        setter.setDebtAuctionInitialParameters(address(this));
        setter.setDebtAuctionInitialParameters(address(this));
    }
    function test_set_params_in_accounting_engine() public {
        setter.setDebtAuctionInitialParameters(address(this));
        assertEq(accountingEngine.debtAuctionBidSize(), 49627791563275434243176178660049627791563275434243);
        assertEq(accountingEngine.initialDebtAuctionMintedTokens(), 70 ether);
    }
    function test_set_params_after_delay() public {
        setter.setDebtAuctionInitialParameters(address(this));
        hevm.warp(now + periodSize);
        setter.setDebtAuctionInitialParameters(address(this));
        assertEq(systemCoin.balanceOf(address(this)), 10 ether);
    }
    function test_set_params_get_self_rewarded() public {
        assertEq(systemCoin.balanceOf(address(this)), 0);
        assertEq(systemCoin.balanceOf(address(treasury)), coinsToMint);

        setter.setDebtAuctionInitialParameters(address(0));
        assertEq(systemCoin.balanceOf(address(this)), 5 ether);
        assertEq(systemCoin.balanceOf(address(treasury)), coinsToMint - 5 ether);
    }
    function test_set_params_get_other_rewarded() public {
        assertEq(systemCoin.balanceOf(address(1)), 0);
        assertEq(systemCoin.balanceOf(address(treasury)), coinsToMint);

        setter.setDebtAuctionInitialParameters(address(1));
        assertEq(systemCoin.balanceOf(address(1)), 5 ether);
        assertEq(systemCoin.balanceOf(address(treasury)), coinsToMint - 5 ether);
    }
    function test_manually_set_debt_initial_params() public {
        setter.manualSetDebtAuctionParameters(100E27, 2E18);
        assertEq(accountingEngine.debtAuctionBidSize(), 100E27);
        assertEq(accountingEngine.initialDebtAuctionMintedTokens(), 2E18);
    }
    function testFail_manually_set_params_by_unauthorized() public {
        Attacker attacker = new Attacker();
        attacker.doManualSetDebtAuctionParameters(address(setter), 100E27, 2E18);
    }
    function test_set_lastUpdateTime() public {
        setter.modifyParameters("lastUpdateTime", now + 1 days);
        assertEq(setter.lastUpdateTime(), now + 1 days);

        setter.modifyParameters("lastUpdateTime", now + 1000 weeks);
        assertEq(setter.lastUpdateTime(), now + 1000 weeks);
    }

    function test_set_params_once_with_inflation() public {
        setter.modifyParameters("bidValueInflationDelay", 1 days);
        setter.modifyParameters("bidValueTargetInflation", 10);

        uint currentTargetValue = setter.bidTargetValue();

        hevm.warp(now + 1 hours);
        setter.setDebtAuctionInitialParameters(address(0x1));
        assertEq(setter.bidValueLastInflationUpdateTime(), now - 1 hours);

        hevm.warp(now + 23 hours);
        setter.setDebtAuctionInitialParameters(address(0x1));
        assertEq(setter.bidValueLastInflationUpdateTime(), now);

        assertEq(setter.bidTargetValue(), currentTargetValue + currentTargetValue * 10 / 100);
    }
    function test_set_params_first_update_with_inflation_large_delay() public {
        setter.modifyParameters("bidValueInflationDelay", 1 days);
        setter.modifyParameters("bidValueTargetInflation", 10);

        uint currentTargetValue = setter.bidTargetValue();

        hevm.warp(now + 10 days);
        setter.setDebtAuctionInitialParameters(address(0x1));
        assertEq(setter.bidValueLastInflationUpdateTime(), now);
    }
    function test_multi_set_params_with_inflation() public {
        setter.modifyParameters("maxRewardIncreaseDelay", maxRewardIncreaseDelay);

        setter.modifyParameters("bidValueInflationDelay", 1 days);
        setter.modifyParameters("bidValueTargetInflation", 10);

        uint currentTargetValue = setter.bidTargetValue();

        hevm.warp(now + 1 hours);
        setter.setDebtAuctionInitialParameters(address(0x1));
        assertEq(setter.bidValueLastInflationUpdateTime(), now - 1 hours);

        hevm.warp(now + 95 hours);
        setter.setDebtAuctionInitialParameters(address(0x1));
        assertEq(setter.bidValueLastInflationUpdateTime(), now);

        for (uint i = 0; i < 4; i++) {
            currentTargetValue = currentTargetValue + currentTargetValue / 100 * 10;
        }

        assertEq(setter.bidTargetValue(), currentTargetValue);
    }
    function testFail_multi_set_params_large_delay() public {
        setter.modifyParameters("maxRewardIncreaseDelay", maxRewardIncreaseDelay);

        setter.modifyParameters("bidValueInflationDelay", 1 days);
        setter.modifyParameters("bidValueTargetInflation", 10);

        uint currentTargetValue = setter.bidTargetValue();

        hevm.warp(now + 1 hours);
        setter.setDebtAuctionInitialParameters(address(0x1));
        assertEq(setter.bidValueLastInflationUpdateTime(), now - 1 hours);

        hevm.warp(now + 3650 days);
        setter.setDebtAuctionInitialParameters(address(0x1));
        assertEq(setter.bidValueLastInflationUpdateTime(), now);
    }
}
