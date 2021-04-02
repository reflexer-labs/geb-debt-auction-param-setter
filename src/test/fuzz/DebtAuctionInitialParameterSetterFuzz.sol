pragma solidity 0.6.7;

import "../Mock/MockTreasury.sol";
import "./DebtAuctionInitialParameterSetterMock.sol";

contract AccountingEngine {
    uint256 public initialDebtAuctionMintedTokens;
    uint256 public debtAuctionBidSize;

    function modifyParameters(bytes32 parameter, uint data) external {
        if (parameter == "debtAuctionBidSize") debtAuctionBidSize = data;
        else if (parameter == "initialDebtAuctionMintedTokens") initialDebtAuctionMintedTokens = data;
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

contract TokenMock {
    uint constant maxUint = uint(0) - 1;
    mapping (address => uint256) public received;
    mapping (address => uint256) public sent;

    function totalSupply() public view returns (uint) {
        return maxUint;
    }
    function balanceOf(address src) public view returns (uint) {
        return maxUint;
    }
    function allowance(address src, address guy) public view returns (uint) {
        return maxUint;
    }

    function transfer(address dst, uint wad) public returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }

    function transferFrom(address src, address dst, uint wad)
        public
        returns (bool)
    {
        received[dst] += wad;
        sent[src]     += wad;
        return true;
    }

    function approve(address guy, uint wad) virtual public returns (bool) {
        return true;
    }
}

// @notice Fuzz the whole thing, failures will show bounds (run with checkAsserts: on)
contract FuzzBounds is DebtAuctionInitialParameterSetterMock {

    TokenMock systemCoin;

    uint256 _coinsToMint = 1E40;

    constructor() DebtAuctionInitialParameterSetterMock(
            address(new Feed(1000 ether, true)),
            address(new Feed(2.015 ether, true)),
            address(new AccountingEngine()),
            address(new MockTreasury(address(new TokenMock()))),
            3600, // periodSize
            5E18, // baseUpdateCallerReward
            10E18, // maxUpdateCallerReward
            1000192559420674483977255848, // perSecondCallerRewardIncrease, 100%/h
            0.5 ether, // minProtocolTokenAmountOffered
            700, // protocolTokenPremium, 30%
            100000 ether // bidTargetValue, 100k
    ) public {

        systemCoin = TokenMock(address(treasury.systemCoin()));

        MockTreasury(address(treasury)).setTotalAllowance(address(this), uint(-1));
        MockTreasury(address(treasury)).setPerBlockAllowance(address(this), 10E45);
        maxRewardIncreaseDelay = 6 hours;
    }

    function fuzzParams(uint protPrice, uint coinPrice, uint _bidTargetValue, uint _protocolTokenPremium) public {
        Feed(address(protocolTokenOrcl)).set_val(protPrice);
        Feed(address(systemCoinOrcl)).set_val(coinPrice);
        bidTargetValue = _bidTargetValue;
        protocolTokenPremium = _protocolTokenPremium;
    }
}

// // @notice Fuzz the contracts testing properties
// contract Fuzz is SingleDebtFloorAdjusterMock {

//     constructor() SingleDebtFloorAdjusterMock(
//             address(new SAFEEngine()),
//             address(new OracleRelayer(address(0x1))),
//             address(0x0),
//             address(new OracleMock(120000000000)),
//             address(new OracleMock(5000 * 10**18)),
//             "ETH",
//             5 ether,
//             10 ether,
//             1000192559420674483977255848,
//             1 hours,
//             600000,
//             1000 * 10**45,
//             100 * 10**45
//     ) public {
//         TokenMock token = new TokenMock();
//         oracleRelayer = OracleRelayerLike(address(new OracleRelayer(address(safeEngine))));
//         treasury = StabilityFeeTreasuryLike(address(new MockTreasury(address(token))));

//         safeEngine.modifyParameters(collateralName, "debtCeiling", 1000000 * 10**45);
//         OracleRelayer(address (oracleRelayer)).modifyParameters("redemptionPrice", 3.14 ether);

//         maxRewardIncreaseDelay = 5 hours;
//     }

//     modifier recompute() {
//         _;
//         recomputeCollateralDebtFloor(address(0xfab));
//     }

//     function notNull(uint val) internal returns (uint) {
//         return val == 0 ? 1 : val;
//     }

//     function maximum(uint a, uint b) internal returns (uint) {
//         return (b >= a) ? b : a;
//     }

//     function fuzzEthPrice(uint ethPrice) public recompute {
//         OracleMock(address(ethPriceOracle)).setPrice(notNull(ethPrice % 1000 ether)); // up to 100k
//     }

//     function fuzzGasPrice(uint gasPrice) public recompute {
//         OracleMock(address(gasPriceOracle)).setPrice(notNull(gasPrice % 10000000000000)); // up to 10000 gwei
//     }

//     function fuzzGasAmountForLiquidation(uint _gasAmountForLiquidation) public recompute {
//         gasAmountForLiquidation = notNull(_gasAmountForLiquidation % block.gaslimit); // up to block gas limit
//     }

//     function fuzzRedemptionPrice(uint redemptionPrice) public recompute {
//         OracleRelayer(address(oracleRelayer)).modifyParameters("redemptionPrice", maximum(redemptionPrice % 10**39, 10**24));
//     }

//     // properties
//     function echidna_debt_floor() public returns (bool) {
//         (,,,, uint256 debtFloor) = safeEngine.collateralTypes(collateralName);
//         return (debtFloor == getNextCollateralFloor() || lastUpdateTime == 0);
//     }

//     function echidna_debt_floor_bounds() public returns (bool) {
//         (,,,, uint256 debtFloor) = safeEngine.collateralTypes(collateralName);
//         return (debtFloor >= minDebtFloor && debtFloor <= maxDebtFloor) || lastUpdateTime == 0;
//     }
// }

// contract SAFEEngineMock is SAFEEngine {
//     function modifyFuzzParameters(
//         bytes32 collateralType,
//         bytes32 parameter,
//         uint256 data
//     ) external isAuthorized {
//         if (parameter == "debtAmount") collateralTypes[collateralType].debtAmount = data;
//         else if (parameter == "accumulatedRate") collateralTypes[collateralType].accumulatedRate = data;
//         else revert();
//     }
// }
