pragma solidity ^0.5.15;

import "ds-test/test.sol";

import "./DebtAuctionLotSetter.sol";

contract DebtAuctionLotSetterTest is DSTest {
    DebtAuctionLotSetter setter;

    function setUp() public {
        //setter = new DebtAuctionLotSetter();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
