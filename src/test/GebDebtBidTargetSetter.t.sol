pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "../GebDebtBidTargetSetter.sol";
import {GebDebtAuctionLotSetter} from "../GebDebtAuctionLotSetter.sol";

contract Oracle is OracleLike {
    uint price;
    bool validity;

    constructor(uint value) public {
        price = value;
    }

    function modifyParameters(bytes32 parameter, uint value) external {
        price = value;
    }
    function getResultWithValidity() override external view returns (bytes32, bool) {
        return (bytes32(price), price > 0);
    }
}
contract AccountingEngine is AccountingEngineLike {
    uint _initialDebtAuctionAmount;
    uint _debtAuctionBidSize;

    constructor(uint debtAuctionBidSize_) public {
        _debtAuctionBidSize = debtAuctionBidSize_;
    }

    function modifyParameters(bytes32 parameter, uint val) override external {
        if (parameter == "initialDebtAuctionAmount") _initialDebtAuctionAmount = val;
        else if (parameter == "debtAuctionBidSize") _debtAuctionBidSize = val;
        else revert();
    }
    function debtAuctionBidSize() public view returns (uint) {
        return _debtAuctionBidSize;
    }
    function initialDebtAuctionAmount() public view returns (uint) {
        return _initialDebtAuctionAmount;
    }
}

contract GebDebtBidTargetSetterTest is DSTest {
    Oracle protocolTokenOrcl;
    Oracle systemCoinOrcl;
    AccountingEngine accountingEngine;
    GebDebtBidTargetSetter bidTargetSetter;
    GebDebtAuctionLotSetter lotSetter;

    function setUp() public {
        accountingEngine = new AccountingEngine(rad(50 ether));
        protocolTokenOrcl = new Oracle(1 ether);
        systemCoinOrcl = new Oracle(42 ether);
        lotSetter = new GebDebtAuctionLotSetter(
          address(protocolTokenOrcl),
          address(systemCoinOrcl),
          address(accountingEngine),
          0.5 ether,
          200
        );
        bidTargetSetter = new GebDebtBidTargetSetter(
          rad(1000 ether),
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
        accountingEngine = new AccountingEngine(rad(50 ether));
        protocolTokenOrcl = new Oracle(1 ether);
        systemCoinOrcl = new Oracle(0);
        lotSetter = new GebDebtAuctionLotSetter(
          address(protocolTokenOrcl),
          address(systemCoinOrcl),
          address(accountingEngine),
          0.5 ether,
          200
        );
        bidTargetSetter = new GebDebtBidTargetSetter(
          rad(1000 ether),
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
