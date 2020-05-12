pragma solidity ^0.5.15;

contract OracleLike {
    function getPriceWithValidity() external view returns (bytes32, bool);
}
contract AccountingEngineLike {
    function debtAuctionBidSize() external view returns (uint);
    function modifyParameters(bytes32, uint) external;
}

contract DebtAuctionLotSetter {
    // --- Auth ---
    mapping (address => uint) public authorizedAccounts;
    /**
     * @notice Add auth to an account
     * @param account Account to add auth to
     */
    function addAuthorization(address account) external emitLog isAuthorized {
        authorizedAccounts[account] = 1;
    }
    /**
     * @notice Remove auth from an account
     * @param account Account to remove auth from
     */
    function removeAuthorization(address account) external emitLog isAuthorized {
        authorizedAccounts[account] = 0;
    }
    /**
    * @notice Checks whether msg.sender can call an authed function
    **/
    modifier isAuthorized {
        require(authorizedAccounts[msg.sender] == 1, "DebtAuctionLotSetter/account-not-authorized");
        _;
    }

    OracleLike           public protocolTokenOrcl;
    OracleLike           public systemCoinOrcl;
    AccountingEngineLike public accountingEngine;

    uint256 public minAuctionedAmount;
    uint256 public protocolTokenDiscount;

    modifier emitLog {
        _;
        assembly {
            // log an 'anonymous' event with a constant 6 words of calldata
            // and four indexed topics: the selector and the first three args
            let mark := msize                         // end of memory ensures zero
            mstore(0x40, add(mark, 288))              // update free memory pointer
            mstore(mark, 0x20)                        // bytes type data offset
            mstore(add(mark, 0x20), 224)              // bytes size (padded)
            calldatacopy(add(mark, 0x40), 0, 224)     // bytes payload
            log4(mark, 288,                           // calldata
                 shl(224, shr(224, calldataload(0))), // msg.sig
                 calldataload(4),                     // arg1
                 calldataload(36),                    // arg2
                 calldataload(68)                     // arg3
                )
        }
    }

    constructor(
      address protocolTokenOrcl_,
      address systemCoinOrcl_,
      address accountingEngine_,
      uint256 minAuctionedAmount_,
      uint256 protocolTokenDiscount_
    ) public {
        require(minAuctionedAmount_ > 0, "DebtAuctionLotSetter/null-min-auctioned-amt");

        authorizedAccounts[msg.sender] = 1;

        protocolTokenOrcl     = OracleLike(protocolTokenOrcl_);
        systemCoinOrcl        = OracleLike(systemCoinOrcl_);
        accountingEngine      = AccountingEngineLike(accountingEngine_);

        minAuctionedAmount    = minAuctionedAmount_;
        protocolTokenDiscount = protocolTokenDiscount_;
    }

    // --- Math ---
    uint public WAD = 10 ** 18;
    uint public THOUSAND = 10 ** 3;
    function add(uint x, uint y) internal pure returns (uint z) {
        z = x + y;
        require(z >= x);
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        z = x - y;
        require(z <= x);
    }
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }
    function div(uint x, uint y) internal pure returns (uint z) {
        require(y > 0);
        z = x / y;
        require(z <= x);
    }

    // --- Administration ---
    function modifyParameters(bytes32 parameter, address addr) external emitLog isAuthorized {
        if (parameter == "protocolTokenOrcl") protocolTokenOrcl = OracleLike(addr);
        else if (parameter == "systemCoinOrcl") systemCoinOrcl = OracleLike(addr);
        else if (parameter == "accountingEngine") accountingEngine = AccountingEngineLike(addr);
        else revert("DebtAuctionLotSetter/modify-unrecognized-param");
    }
    function modifyParameters(bytes32 parameter, uint256 val) external emitLog isAuthorized {
        if (parameter == "minAuctionedAmount") {
          require(val > 0, "DebtAuctionLotSetter/null-min-auctioned-amt");
          minAuctionedAmount = val;
        }
        else if (parameter == "protocolTokenDiscount") protocolTokenDiscount = val;
        else revert("DebtAuctionLotSetter/modify-unrecognized-param");
    }

    function both(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := and(x, y)}
    }

    // --- Setter ---
    function setAuctionedAmount() external emitLog {
        (bytes32 protocolTknPrice, bool validProtocolPrice) = protocolTokenOrcl.getPriceWithValidity();
        (bytes32 systemCoinPrice, bool validSysCoinPrice) = systemCoinOrcl.getPriceWithValidity();
        require(both(validProtocolPrice, validSysCoinPrice), "DebtAuctionLotSetter/invalid-prices");

        uint baseAuctionedAmount = div(
          mul(div(accountingEngine.debtAuctionBidSize(), WAD), uint(systemCoinPrice)),
          uint(protocolTknPrice)
        );

        baseAuctionedAmount = add(
          baseAuctionedAmount,
          div(mul(baseAuctionedAmount, protocolTokenDiscount), THOUSAND)
        );

        baseAuctionedAmount = div(baseAuctionedAmount, 10 ** 9);
        baseAuctionedAmount = (baseAuctionedAmount == 0) ? minAuctionedAmount : baseAuctionedAmount;

        accountingEngine.modifyParameters("initialDebtAuctionAmount", baseAuctionedAmount);
    }
}
