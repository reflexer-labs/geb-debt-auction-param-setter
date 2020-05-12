pragma solidity ^0.5.15;

import "ds-test/test.sol";

import "../DebtBidTargetSetter.sol";
import {DebtAuctionLotSetter} from "../DebtAuctionLotSetter.sol";

contract Oracle is OracleLike {
    uint price;
    bool validity;

    constructor(uint value) public {
        price = value;
    }

    function modifyParameters(bytes32 parameter, uint value) external {
        price = value;
    }
    function getPriceWithValidity() external view returns (bytes32, bool) {
        return (bytes32(price), price > 0);
    }
}
contract AccountingEngine is AccountingEngineLike {
    uint public initialDebtAuctionAmount;
    uint public debtAuctionBidSize;
    uint public debtAuctionBidTarget;

    constructor(uint debtAuctionBidSize_, uint debtAuctionBidTarget_) public {
        debtAuctionBidSize = debtAuctionBidSize_;
        debtAuctionBidTarget = debtAuctionBidTarget_;
    }

    function modifyParameters(bytes32 parameter, uint val) external {
        if (parameter == "initialDebtAuctionAmount") initialDebtAuctionAmount = val;
        else if (parameter == "debtAuctionBidSize") debtAuctionBidSize = val;
        else revert();
    }
}

contract DebtBidTargetSetterTest is DSTest {
    Oracle protocolTokenOrcl;
    Oracle systemCoinOrcl;
    AccountingEngine accountingEngine;
    DebtBidTargetSetter bidTargetSetter;
    DebtAuctionLotSetter lotSetter;

    function setUp() public {
        accountingEngine = new AccountingEngine(rad(50 ether), rad(1000 ether));
        protocolTokenOrcl = new Oracle(1 ether);
        systemCoinOrcl = new Oracle(42 ether);
        lotSetter = new DebtAuctionLotSetter(
          address(protocolTokenOrcl),
          address(systemCoinOrcl),
          address(accountingEngine),
          0.5 ether,
          200
        );
        bidTargetSetter = new DebtBidTargetSetter(
          address(systemCoinOrcl),
          address(accountingEngine),
          address(lotSetter)
        );
    }

    uint WAD = 1 ether;
    uint RAD = 10 ** 45;
    function ray(uint x) internal pure returns (uint z) {
        z = x * 10 ** 9;
    }
    function rad(uint x) internal pure returns (uint z) {
        z = x * 10 ** 27;
    }

    function testFail_invalid_system_coin_price() public {
        accountingEngine = new AccountingEngine(rad(50 ether), rad(1000 ether));
        protocolTokenOrcl = new Oracle(1 ether);
        systemCoinOrcl = new Oracle(0);
        lotSetter = new DebtAuctionLotSetter(
          address(protocolTokenOrcl),
          address(systemCoinOrcl),
          address(accountingEngine),
          0.5 ether,
          200
        );
        bidTargetSetter = new DebtBidTargetSetter(
          address(systemCoinOrcl),
          address(accountingEngine),
          address(lotSetter)
        );
        bidTargetSetter.adjustBidTarget();
    }
    function test_adjust_rate() public {
        bidTargetSetter.adjustBidTarget();
        assertEq(accountingEngine.debtAuctionBidSize(), 23809523809523809523809523809000000000000000000);
        assertEq(accountingEngine.debtAuctionBidSize() / RAD, 23);
        assertEq(accountingEngine.initialDebtAuctionAmount(), 1199999999999999999999);
    }
}
