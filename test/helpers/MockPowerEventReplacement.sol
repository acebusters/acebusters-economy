pragma solidity ^0.4.11;

import '../../contracts/policies/PowerEventReplacement.sol';

contract MockPowerEventReplacement is PowerEventReplacement{

  function MockPowerEventReplacement(address _controllerAddr, uint256 _startTime, uint256 _minDuration, uint256 _maxDuration, uint256 _softCap, uint256 _hardCap, uint256 _discount, uint256 _amountPower, address[] _milestoneRecipients, uint256[] _milestoneShares)
    PowerEventReplacement(_controllerAddr, _startTime, _minDuration, _maxDuration, _softCap, _hardCap, _discount, _amountPower, _milestoneRecipients, _milestoneShares) {
  }

  function startCollection() isState(EventState.Waiting) {
    // check time
    require(now > startTime);
    // assert(now < startTime.add(minDuration));
    // read initial values
    var contr = Controller(controllerAddr);
    powerAddr = contr.powerAddr();
    nutzAddr = contr.nutzAddr();
    initialSupply = 2400000000000000000;
    initialReserve = 1000000000000000;
    uint256 ceiling = contr.ceiling();
    // move ceiling
    uint256 newCeiling = ceiling.mul(discountRate).div(RATE_FACTOR);
    contr.moveCeiling(newCeiling);
    // set state
    state = EventState.Collecting;
  }

}
