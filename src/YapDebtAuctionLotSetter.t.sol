pragma solidity ^0.5.15;

import "ds-test/test.sol";

import "./YapDebtAuctionLotSetter.sol";

contract YapDebtAuctionLotSetterTest is DSTest {
    YapDebtAuctionLotSetter setter;

    function setUp() public {
        setter = new YapDebtAuctionLotSetter();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
