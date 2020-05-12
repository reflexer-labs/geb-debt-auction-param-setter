pragma solidity ^0.5.15;

contract AccountingEngineLike {
    function debtAuctionBidTarget() external view returns (uint);
    function modifyParameters(bytes32, uint) external;
}
contract OracleLike {
    function getPriceWithValidity() external view returns (bytes32, bool);
}
contract DebtAuctionLotSetterLike {
    function setAuctionedAmount() external;
}

contract DebtBidTargetSetter {
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

    OracleLike               public systemCoinOrcl;
    AccountingEngineLike     public accountingEngine;
    DebtAuctionLotSetterLike public debtAuctionLotSetter;

    constructor(
      address systemCoinOrcl_,
      address accountingEngine_,
      address debtAuctionLotSetter_
    ) public {
        authorizedAccounts[msg.sender] = 1;
        systemCoinOrcl = OracleLike(systemCoinOrcl_);
        accountingEngine = AccountingEngineLike(accountingEngine_);
        debtAuctionLotSetter = DebtAuctionLotSetterLike(debtAuctionLotSetter_);
    }

    // --- Administration ---
    function modifyParameters(bytes32 parameter, address addr) external emitLog isAuthorized {
        if (parameter == "systemCoinOrcl") systemCoinOrcl = OracleLike(addr);
        else if (parameter == "accountingEngine") accountingEngine = AccountingEngineLike(addr);
        else if (parameter == "debtAuctionLotSetter") debtAuctionLotSetter = DebtAuctionLotSetterLike(addr);
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
        (bytes32 systemCoinPrice, bool validPrice) = systemCoinOrcl.getPriceWithValidity();
        require(validPrice, "DebtBidTargetSetter/invalid-orcl-price");

        accountingEngine.modifyParameters(
          "debtAuctionBidSize",
          rayToRad(div(accountingEngine.debtAuctionBidTarget(), uint(systemCoinPrice)))
        );

        debtAuctionLotSetter.setAuctionedAmount();
    }
}
