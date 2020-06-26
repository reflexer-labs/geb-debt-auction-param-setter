pragma solidity ^0.6.7;

abstract contract AccountingEngineLike {
    function modifyParameters(bytes32, uint) virtual external;
}
abstract contract OracleLike {
    function getResultWithValidity() virtual external view returns (bytes32, bool);
}
abstract contract GebDebtAuctionLotSetterLike {
    function setAuctionedAmount() virtual external;
}

contract GebDebtBidTargetSetter {
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
        require(authorizedAccounts[msg.sender] == 1, "DebtBidTargetSetter/account-not-authorized");
        _;
    }

    modifier emitLog {
        _;
        assembly {
            // log an 'anonymous' event with a constant 6 words of calldata
            // and four indexed topics: the selector and the first three args
            let mark := msize()                       // end of memory ensures zero
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

    uint256                     public debtAuctionBidTarget;

    OracleLike                  public systemCoinOrcl;
    AccountingEngineLike        public accountingEngine;
    GebDebtAuctionLotSetterLike public debtAuctionLotSetter;

    constructor(
      uint debtAuctionBidTarget_,
      address systemCoinOrcl_,
      address accountingEngine_,
      address debtAuctionLotSetter_
    ) public {
        require(debtAuctionBidTarget_ > 0, "DebtBidTargetSetter/null-debtAuctionBidTarget");
        authorizedAccounts[msg.sender] = 1;
        debtAuctionBidTarget = debtAuctionBidTarget_;
        systemCoinOrcl = OracleLike(systemCoinOrcl_);
        accountingEngine = AccountingEngineLike(accountingEngine_);
        debtAuctionLotSetter = GebDebtAuctionLotSetterLike(debtAuctionLotSetter_);
    }

    // --- Administration ---
    function modifyParameters(bytes32 parameter, address addr) external emitLog isAuthorized {
        if (parameter == "systemCoinOrcl") systemCoinOrcl = OracleLike(addr);
        else if (parameter == "accountingEngine") accountingEngine = AccountingEngineLike(addr);
        else if (parameter == "debtAuctionLotSetter") debtAuctionLotSetter = GebDebtAuctionLotSetterLike(addr);
        else revert("DebtBidTargetSetter/modify-unrecognized-param");
    }
    function modifyParameters(bytes32 parameter, uint data) external emitLog isAuthorized {
        if (parameter == "debtAuctionBidTarget") debtAuctionBidTarget = data;
        else revert("DebtBidTargetSetter/modify-unrecognized-param");
    }

    // --- Math ---
    uint256 constant WAD = 1 ether;
    function div(uint x, uint y) internal pure returns (uint z) {
        require(y > 0);
        z = x / y;
        require(z <= x);
    }
    function rayToRad(uint x) internal pure returns (uint z) {
        z = x * WAD;
        require(z >= x);
    }

    // --- Adjustment ---
    function adjustBidTarget() public emitLog {
        (bytes32 systemCoinPrice, bool validPrice) = systemCoinOrcl.getResultWithValidity();
        require(validPrice, "DebtBidTargetSetter/invalid-orcl-price");
        require(debtAuctionBidTarget > 0, "DebtBidTargetSetter/invalid-debt-auction-target");

        accountingEngine.modifyParameters(
          "debtAuctionBidSize",
          rayToRad(div(debtAuctionBidTarget, uint(systemCoinPrice)))
        );

        debtAuctionLotSetter.setAuctionedAmount();
    }
}
