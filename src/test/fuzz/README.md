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
    rmultiply(1886862567290639455494083118563938007875568565228677809922401407928,61432131875)

assertion in ray: failed!💥
  Call sequence:
    ray(115838625957299645116210531330288243514068797874068363881394747195438)

assertion in bidTargetValue: passed! 🎉
assertion in multiply: failed!💥
  Call sequence:
    multiply(84738433903651669835086864455560631118,1373660203072137022014593776562802845924)

assertion in protocolTokenPremium: passed! 🎉
assertion in baseUpdateCallerReward: passed! 🎉
assertion in maxRewardIncreaseDelay: passed! 🎉
assertion in authorizedAccounts: passed! 🎉
assertion in treasuryAllowance: passed! 🎉
assertion in addAuthorization: passed! 🎉
assertion in wmultiply: failed!💥
  Call sequence:
    wmultiply(6,19320937987666812181372576059885341284906746889896447637539555517467584779627)

assertion in subtract: failed!💥
  Call sequence:
    subtract(0,1)

assertion in perSecondCallerRewardIncrease: passed! 🎉
assertion in rad: failed!💥
  Call sequence:
    rad(115797647851213479584784131810300845157547487814836)

assertion in manualSetDebtAuctionParameters: passed! 🎉
assertion in minProtocolTokenAmountOffered: passed! 🎉
assertion in getPremiumAdjustedProtocolTokenAmount: failed!💥
  Call sequence:
    fuzzParams(2,7696469028944939096644330046923983291495366604588268,115926436795955985160419997568026068982163811880113870634,120642387219613518400626400807383327335171361243)
    getPremiumAdjustedProtocolTokenAmount()

assertion in addition: failed!💥
  Call sequence:
    addition(69283910323076536737177054055878245993002006983063280384022497764255494804394,47080639969898934449045348269198192176182836801942186854009601028867546925623)

assertion in RAY: passed! 🎉
assertion in updateDelay: passed! 🎉
assertion in treasury: passed! 🎉
assertion in modifyParameters: passed! 🎉
assertion in maxUpdateCallerReward: passed! 🎉
assertion in WAD: passed! 🎉
assertion in getRawProtocolTokenAmount: failed!💥
  Call sequence:
    fuzzParams(12363724300,488908949313535191735025544936183155531510918229770825230,115799820230258254532230319774482720304531772204312158718461,1504229331527011360703020412954109405186050922765518291569)
    getRawProtocolTokenAmount()

assertion in removeAuthorization: passed! 🎉
assertion in accountingEngine: passed! 🎉
assertion in protocolTokenOrcl: passed! 🎉
assertion in rdivide: failed!💥
  Call sequence:
    rdivide(115801293773509174099879556091275542391650331378185,15306824106411220738589132040698562060097783)

assertion in getNewDebtBid: failed!💥
  Call sequence:
    fuzzParams(17657843745536337527512516605525074,1589585014227748301395367,115804424984310826176615835225343,0)
    getNewDebtBid()

assertion in setDebtAuctionInitialParameters: failed!💥
  Call sequence:
    fuzzParams(3614393598515173946989974365,20657823283493783720108499,115803057612405542733808860688740,0)
    setDebtAuctionInitialParameters(0x0)

assertion in systemCoinOrcl: passed! 🎉
assertion in lastUpdateTime: passed! 🎉
assertion in range: passed! 🎉
assertion in rpower: failed!💥
  Call sequence:
    rpower(4,128,1)

assertion in minimum: passed! 🎉
assertion in getCallerReward: passed! 🎉
assertion in wdivide: failed!💥
  Call sequence:
    wdivide(0,0)

assertion in modifyParameters: passed! 🎉

Seed: -4391526086924522122
```

Most of these failures are well known (math functions), we will focus on the ones specific to this contract:

```
assertion in getPremiumAdjustedProtocolTokenAmount: failed!💥
  Call sequence:
    fuzzParams(2,7696469028944939096644330046923983.291495366604588268,115926436795955985160419997568026068982.163811880113870634,120642387219613518400626400807383327335171361243)
    getPremiumAdjustedProtocolTokenAmount()
```

Prot Price of 2, bid target value of 115926436795955985160419997568026068982.163811880113870634 and protocolTokenPremium of 999
(coin price does not affect it).

Here the fuzzer reduced the prot price to two, but what actually causes the overflow are the consecutive multiplications up front (bidTargetValue * WAD * protocolTokenPremium). This bound could be increased by reordering the arythmetic operations (the way they are in setDebtAuctionInitialParameters()), with the added benefit of alighning both results (though diferrences are minimal, refer to the next test for more details).

Bounds are plentiful still even with this limitation.

```
assertion in getRawProtocolTokenAmount: failed!💥
  Call sequence:
    fuzzParams(12363724300,488908949313535191735025544936183155531.510918229770825230,1157998202302582545322303197744827203045317.72204312158718461,1504229331527011360703020412954109405186050922765518291569)
    getRawProtocolTokenAmount()
```

Prot price of 12363724300, bid target value of 1157998202302582545322303197744827203045317.72204312158718461. Here the fuzzer also made it's best to reduce prot price, ended up with a large bitTarget, if we balance the two (up to 1mm prot price):

prot price 1,236,372.430000000000000000
bid target value 11579982023025825453223031977.4482720304531772204312158718461

```
assertion in getNewDebtBid: failed!💥
  Call sequence:
    fuzzParams(17,657,843,745,536,337.527512516605525074, 1,589,585.014227748301395367 ,115,804,424,984,310.826176615835225343,0)
    getNewDebtBid()
````

A Bid target price of 115,804,424,984,310.826176615835225343 alone makes the function revert due to an overflow.

```
assertion in setDebtAuctionInitialParameters: failed!💥
  Call sequence:
    fuzzParams(36,143,935,985.15173946989974365, 20,657,823,283493783720108499, 115,803,057,612,405.542733808860688740,0)
    setDebtAuctionInitialParameters(0x0)
```
Will overflow only for Prot price in the trillion range, coin price over 20mm, and bidTargetVlue in the Trillion Range. (tokenPremium set to 1).

#### Conclusion: Bounds are plentyful and should not affect the system in normal conditions.


### Fuzz Properties (Fuzz)

In this case we setup the setter, and check properties.

Here we are not looking for bounds, but instead checking the properties that either should remain constant:

- initial debt auction minted tokens bounds and value
- bid size bounds and value

These properties are verified in between all calls.

```
Analyzing contract: /Users/fabio/Documents/reflexer/geb-debt-auction-param-setter/src/test/fuzz/DebtAuctionInitialParameterSetterFuzz.sol:Fuzz
echidna_debt_auction_bid_size_bound: passed! 🎉
echidna_initial_debt_auction_minted_tokens: passed! 🎉
echidna_initial_debt_auction_minted_tokens_bound: passed! 🎉
echidna_debt_auction_bid_size: passed! 🎉

Seed: 4523568715541225461
```

The formula used to calulate ```initialDebtAuctionMintedTokens``` sightly differs between ```getPremiumAdjustedProtocolTokenAmount()``` and ```setDebtAuctionInitialParameters()```. This results in minor loss of precision (only two last digits affected using sane but generous ranges for the parameters) due to division rounding.

Another side effect is that the bound of ```setDebtAuctionInitialParameters()``` is larger than the one in ```getPremiumAdjustedProtocolTokenAmount()``` (which is a positive thing since it's the one that changes state, and overflowing any of the calculations results in DoS).

#### Conclusion: No exceptions found
