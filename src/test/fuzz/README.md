# Security Tests

The contracts in this folder are the fuzz scripts for the ESM Threshold Setter.

To run the fuzzer, set up Echidna (https://github.com/crytic/echidna) on your machine.

Then run
```
echidna-test src/test/fuzz/<name of file>.sol --contract <Name of contract> --config src/test/fuzz/echidna.yaml
```

Configs are in this folder (echidna.yaml).

The contracts in this folder are modified versions of the originals in the _src_ folder. They have assertions added to test for invariants, visibility of functions modified. Running the Fuzz against modified versions without the assertions is still possible, general properties on the Fuzz contract can be executed against unmodified contracts.

Tests should be run one at a time because they interfere with each other.

For all contracts being fuzzed, we tested the following:

1. Writing assertions and/or turning "requires" into "asserts" within the smart contract itself. This will cause echidna to fail fuzzing, and upon failures echidna finds the lowest value that causes the assertion to fail. This is useful to test bounds of functions (i.e.: modifying safeMath functions to assertions will cause echidna to fail on overflows, giving insight on the bounds acceptable). This is useful to find out when these functions revert. Although reverting will not impact the contract's state, it could cause a denial of service (or the contract not updating state when necessary and getting stuck). We check the found bounds against the expected usage of the system.
2. For contracts that have state, we also force the contract into common states and fuzz common actions.

Echidna will generate random values and call all functions failing either for violated assertions, or for properties (functions starting with echidna_) that return false. Sequence of calls is limited by seqLen in the config file. Calls are also spaced over time (both block number and timestamp) in random ways. Once the fuzzer finds a new execution path, it will explore it by trying execution with values close to the ones that opened the new path.

# Results

### 1. Fuzzing for overflows (FuzzBounds)

In this test we want failures, as they will show us what are the bounds in which the contract operates safely.

Failures flag where overflows happen, and should be compared to expected inputs (to avoid overflows frm causing DoS).

```
Analyzing contract: /Users/fabio/Documents/reflexer/geb-debt-auction-param-setter/src/test/fuzz/DebtAuctionInitialParameterSetterFuzz.sol:FuzzBounds
assertion in fuzzParams: passed! 🎉
assertion in rmultiply: failed!💥
  Call sequence:
    rmultiply(4,28958322629934027388478141341387589783968741811476195402180025798662620043902)

assertion in ray: failed!💥
  Call sequence:
    ray(115839689627912034857851657245170453849463076823500907210208364782520)

assertion in bidTargetValue: passed! 🎉
assertion in multiply: failed!💥
  Call sequence:
    multiply(11514164294927458563283,10195967103405823516195663586289421812301005116502142254)

assertion in protocolTokenPremium: passed! 🎉
assertion in baseUpdateCallerReward: passed! 🎉
assertion in maxRewardIncreaseDelay: passed! 🎉
assertion in authorizedAccounts: passed! 🎉
assertion in treasuryAllowance: passed! 🎉
assertion in addAuthorization: passed! 🎉
assertion in wmultiply: failed!💥
  Call sequence:
    wmultiply(874620678382695853556653800711941912,132974611220910809214165801660783339703224)

assertion in subtract: failed!💥
  Call sequence:
    subtract(0,1)

assertion in perSecondCallerRewardIncrease: passed! 🎉
assertion in rad: failed!💥
  Call sequence:
    rad(115793775520743184135304365296795382682318901518744)

assertion in manualSetDebtAuctionParameters: passed! 🎉
assertion in minProtocolTokenAmountOffered: passed! 🎉
assertion in getPremiumAdjustedProtocolTokenAmount: failed!💥
  Call sequence:
    fuzzParams(1,3886334908547733802599940878433142601135711175657670,474,244788209938902489582862550094750087022641147196422491811)
    getPremiumAdjustedProtocolTokenAmount()

assertion in addition: failed!💥
  Call sequence:
    addition(36542869777176826691345451642803920824339307642384007560775457856963326230546,80711948321622779564703848381455250409738382795083160283201643365426144665978)

assertion in RAY: passed! 🎉
assertion in updateDelay: passed! 🎉
assertion in treasury: passed! 🎉
assertion in modifyParameters: passed! 🎉
assertion in maxUpdateCallerReward: passed! 🎉
assertion in WAD: passed! 🎉
assertion in getRawProtocolTokenAmount: failed!💥
  Call sequence:
    fuzzParams(154,1857692599704741517700186240702146839342607664967771871995251,115793626425617270750949810470307571266346017116911267526473,0)
    getRawProtocolTokenAmount()

assertion in removeAuthorization: passed! 🎉
assertion in accountingEngine: passed! 🎉
assertion in protocolTokenOrcl: passed! 🎉
assertion in rdivide: failed!💥
  Call sequence:
    rdivide(115811926061445553173043251576447236435010971650728,54627399523106031914765732457227202981153775283951)

assertion in getNewDebtBid: failed!💥
  Call sequence:
    fuzzParams(0,462138492308152527756142713789,115792112494395429221218146734185,0)
    getNewDebtBid()

assertion in setDebtAuctionInitialParameters: failed!💥
  Call sequence:
    fuzzParams(1,18046030131257421360465858558172379077951846051349734200741,132,884914232195452324324623542175758958865865302229822720230)
    setDebtAuctionInitialParameters(0x0)

assertion in systemCoinOrcl: passed! 🎉
assertion in lastUpdateTime: passed! 🎉
assertion in rpower: failed!💥
  Call sequence:
    rpower(2,256,1)

assertion in minimum: passed! 🎉
assertion in getCallerReward: passed! 🎉
assertion in wdivide: failed!💥
  Call sequence:
    wdivide(115822318455922692650184045352585873203819954647117433380743,881910763737265075202278574661917659166037104063)

assertion in modifyParameters: passed! 🎉

Seed: 8954960791065063548
```


#### Conclusion: No exceptions found, all overflows are expected (from teh public functions in GebMath).


### Fuzz Properties (Fuzz)

In this case we setup the setter, and check properties.

Here we are not looking for bounds, but instead checking the properties that either should remain constant:

- debtFloor bounds and value
- debtFloor bounds and value
- debtFloor bounds and value
- debtFloor bounds and value

These properties are verified in between all calls.

```
Analyzing contract: /Users/fabio/Documents/reflexer/geb-debt-auction-param-setter/src/test/fuzz/DebtAuctionInitialParameterSetterFuzz.sol:Fuzz
echidna_debt_auction_bid_size_bound: passed! 🎉
echidna_initial_debt_auction_minted_tokens: failed!💥
  Call sequence:
    fuzzParams(3,1,1,1518)

echidna_initial_debt_auction_minted_tokens_bound: passed! 🎉
echidna_debt_auction_bid_size: passed! 🎉

Seed: -4159651621258571812
```

#### Conclusion: getPremiumAdjustedProtocolTokenAmount does not match setDebtAuctionInitialParameters, TBD
