pragma solidity ^0.6.7;

import "ds-test/test.sol";

import {GebDeployTestBase} from "geb-deploy/test/GebDeploy.t.base.sol";
import "../DebtAuctionInitialParameterSetter.sol";

abstract contract WethLike {
    function balanceOf(address) virtual public view returns (uint);
    function approve(address, uint) virtual public;
    function transfer(address, uint) virtual public;
    function transferFrom(address, address, uint) virtual public;
    function deposit() virtual public payable;
    function withdraw(uint) virtual public;
}

contract Attacker {
    function doManualSetDebtAuctionParameters(address setter, uint256 debtAuctionBidSize, uint256 initialDebtAuctionMintedTokens) public {
        DebtAuctionInitialParameterSetter(setter).manualSetDebtAuctionParameters(debtAuctionBidSize, initialDebtAuctionMintedTokens);
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

contract DebtAuctionInitialParameterSetterTest is GebDeployTestBase {

    Feed sysCoinFeed;
    Feed protocolTokenFeed;

    DebtAuctionInitialParameterSetter setter;

    uint256 periodSize = 3600;
    uint256 baseUpdateCallerReward = 5E18;
    uint256 maxUpdateCallerReward  = 10E18;
    uint256 perSecondCallerRewardIncrease = 1000192559420674483977255848; // 100% per hour

    uint256 minProtocolTokenAmountOffered = 0.5 ether;
    uint256 protocolTokenPremium = 700; // 30%
    uint256 bidTargetValue = 100000 ether; // 100K

    uint256 coinsToMint = 1000 ether;

    uint RAY = 10 ** 27;

    function setUp() public override {
        super.setUp();
        hevm.warp(604411200);

        deployIndexWithCreatorPermissions(bytes32("FIXED-DISCOUNT"));

        sysCoinFeed = new Feed(2.015 ether, true);
        protocolTokenFeed = new Feed(1000 ether, true);

        //

        setter = new DebtAuctionInitialParameterSetter(
            address(protocolTokenFeed),
            address(sysCoinFeed),
            address(accountingEngine),
            address(stabilityFeeTreasury),
            periodSize,
            baseUpdateCallerReward,
            maxUpdateCallerReward,
            perSecondCallerRewardIncrease,
            minProtocolTokenAmountOffered,
            protocolTokenPremium,
            bidTargetValue
        );

        accountingEngine.addAuthorization(address(setter));

        // generating coin to feed StabilityFeeTreasury
        WethLike(address(ethJoin.collateral())).deposit{value: 100 ether}();
        WethLike(address(ethJoin.collateral())).approve(address(ethJoin), 100 ether);
        ethJoin.join(address(this), 100 ether);
        safeEngine.modifySAFECollateralization(
            "ETH",
            address(this),
            address(this),
            address(this),
            100 ether,
            int(coinsToMint)
        );
        safeEngine.approveSAFEModification(address(coinJoin));
        coinJoin.exit(address(stabilityFeeTreasury), coinsToMint);

        // auth in stabilityFeeTreasury
        address      usr = address(govActions);
        bytes32      tag;  assembly { tag := extcodehash(usr) }
        bytes memory fax = abi.encodeWithSignature("addAuthorization(address,address)", address(stabilityFeeTreasury), address(this));
        uint         eta = now;
        pause.scheduleTransaction(usr, tag, fax, eta);
        pause.executeTransaction(usr, tag, fax, eta);

        // setting allowances
        stabilityFeeTreasury.setTotalAllowance(address(setter), uint(-1));
        stabilityFeeTreasury.setPerBlockAllowance(address(setter), 10E45);
    }

    function test_setup() public {
        assertEq(setter.authorizedAccounts(address(this)), 1);

        assertTrue(address(setter.protocolTokenOrcl()) == address(protocolTokenFeed));
        assertTrue(address(setter.systemCoinOrcl()) == address(sysCoinFeed));
        assertTrue(address(setter.accountingEngine()) == address(accountingEngine));
        assertTrue(address(setter.treasury()) == address(stabilityFeeTreasury));

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
        assertEq(safeEngine.coinBalance(address(this)), 10 ether * RAY);
    }
    function test_set_params_get_self_rewarded() public {
        assertEq(coin.balanceOf(address(this)), 0);
        assertEq(coin.balanceOf(address(stabilityFeeTreasury)), coinsToMint);

        setter.setDebtAuctionInitialParameters(address(0));
        assertEq(safeEngine.coinBalance(address(this)), 5 ether * RAY);
        assertEq(safeEngine.coinBalance(address(stabilityFeeTreasury)), (coinsToMint - 5 ether) * RAY);
    }
    function test_set_params_get_other_rewarded() public {
        assertEq(coin.balanceOf(address(1)), 0);
        assertEq(coin.balanceOf(address(stabilityFeeTreasury)), coinsToMint);

        setter.setDebtAuctionInitialParameters(address(1));
        assertEq(safeEngine.coinBalance(address(1)), 5 ether * RAY);
        assertEq(safeEngine.coinBalance(address(stabilityFeeTreasury)), (coinsToMint - 5 ether) * RAY);
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
}
