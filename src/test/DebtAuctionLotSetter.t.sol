pragma solidity ^0.5.15;

import "ds-test/test.sol";

import "../DebtAuctionLotSetter.sol";

contract Oracle is OracleLike {
    uint price;
    bool validity;

    constructor(uint value) public {
        price = value;
    }

    function modifyParameters(bytes32 parameter, uint value) external {
        price = value;
    }
    function getResultWithValidity() external view returns (bytes32, bool) {
        return (bytes32(price), price > 0);
    }
}
contract AccountingEngine is AccountingEngineLike {
    uint public initialDebtAuctionAmount;
    uint public debtAuctionBidSize;

    constructor(uint debtAuctionBidSize_) public {
        debtAuctionBidSize = debtAuctionBidSize_;
    }

    function modifyParameters(bytes32 parameter, uint val) external {
        require(parameter == "initialDebtAuctionAmount");
        initialDebtAuctionAmount = val;
    }
}

contract DebtAuctionLotSetterTest is DSTest {
    Oracle protocolTokenOrcl;
    Oracle systemCoinOrcl;
    AccountingEngine accountingEngine;
    DebtAuctionLotSetter lotSetter;

    function setUp() public {
        accountingEngine = new AccountingEngine(rad(50 ether));
        protocolTokenOrcl = new Oracle(1 ether);
        systemCoinOrcl = new Oracle(42 ether);
        lotSetter = new DebtAuctionLotSetter(
          address(protocolTokenOrcl),
          address(systemCoinOrcl),
          address(accountingEngine),
          0.5 ether,
          200
        );
    }

    function ray(uint x) internal pure returns (uint z) {
        z = x * 10 ** 9;
    }
    function rad(uint x) internal pure returns (uint z) {
        z = x * 10 ** 27;
    }

    function testFail_invalid_protocol_tkn_price() public {
        accountingEngine = new AccountingEngine(rad(50 ether));
        protocolTokenOrcl = new Oracle(0);
        systemCoinOrcl = new Oracle(42 ether);
        lotSetter = new DebtAuctionLotSetter(
          address(protocolTokenOrcl),
          address(systemCoinOrcl),
          address(accountingEngine),
          0.5 ether,
          200
        );

        lotSetter.setAuctionedAmount();
    }
    function testFail_invalid_system_coin_price() public {
        accountingEngine = new AccountingEngine(rad(50 ether));
        protocolTokenOrcl = new Oracle(1 ether);
        systemCoinOrcl = new Oracle(0);
        lotSetter = new DebtAuctionLotSetter(
          address(protocolTokenOrcl),
          address(systemCoinOrcl),
          address(accountingEngine),
          0.5 ether,
          200
        );

        lotSetter.setAuctionedAmount();
    }
    function test_sys_coin_more_expensive_than_protocol() public {
        lotSetter.setAuctionedAmount();
        assertEq(accountingEngine.initialDebtAuctionAmount(), 2520 ether);
    }
    function test_sys_coin_cheaper_than_protocol() public {
        accountingEngine = new AccountingEngine(rad(50 ether));
        protocolTokenOrcl = new Oracle(420 ether);
        systemCoinOrcl = new Oracle(42 ether);
        lotSetter = new DebtAuctionLotSetter(
          address(protocolTokenOrcl),
          address(systemCoinOrcl),
          address(accountingEngine),
          0.5 ether,
          200
        );
        lotSetter.setAuctionedAmount();
        assertEq(accountingEngine.initialDebtAuctionAmount(), 6 ether);
    }
    function test_lot_amount_cannot_be_null() public {
        accountingEngine = new AccountingEngine(rad(50 ether));
        protocolTokenOrcl = new Oracle(420 * (10 ** 19) * 1 ether);
        systemCoinOrcl = new Oracle(42 ether);
        lotSetter = new DebtAuctionLotSetter(
          address(protocolTokenOrcl),
          address(systemCoinOrcl),
          address(accountingEngine),
          0.5 ether,
          200
        );
        lotSetter.setAuctionedAmount();
        assertEq(accountingEngine.initialDebtAuctionAmount(), 0.5 ether);
    }
}
