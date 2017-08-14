pragma solidity 0.4.11;

import './Nutz.sol';
import "./SafeMath.sol";

contract PowerEvent {
  using SafeMath for uint;

  // states
  //   - waiting, initial state
  //   - collecting, after waiting, before collection stopped
  //   - failed, after collecting, if softcap missed
  //   - closed, after collecting, if softcap reached
  //   - complete, after closed or failed, when job done
  enum EventState { Waiting, Collecting, Closed, Failed, Complete }
  EventState public state;
  uint256 public RATE_FACTOR = 1000000;

  // Terms
  uint256 public startTime;
  uint256 public minDuration;
  uint256 public maxDuration;
  uint256 public softCap;
  uint256 public hardCap;
  uint256 public discountRate; // if rate 30%, this will be 300,000
  address[] public milestoneRecipients;
  uint256[] public milestoneShares;
  
  // Params
  address public ntzAddr;
  address public powerAddr;
  uint256 public initialReserve;
  uint256 public initialSupply;
  
  function PowerEvent(address _ntzAddr, uint256 _startTime, uint256 _minDuration, uint256 _maxDuration, uint256 _softCap, uint256 _hardCap, uint256 _discount, address[] _milestoneRecipients, uint256[] _milestoneShares) {
    ntzAddr = _ntzAddr;
    startTime = _startTime;
    minDuration = _minDuration;
    maxDuration = _maxDuration;
    softCap = _softCap;
    hardCap = _hardCap;
    discountRate = _discount;
    state = EventState.Waiting;
    milestoneRecipients = _milestoneRecipients;
    milestoneShares = _milestoneShares;
  }
  
  modifier isState(EventState _state) {
    require(state == _state);
    _;
  }

  function startCollection() isState(EventState.Waiting) {
    // check time
    require(now > startTime);
    // assert(now < startTime.add(minDuration));
    // read initial values
    var NutzContract = Nutz(ntzAddr);
    powerAddr = NutzContract.powerAddr();
    initialSupply = NutzContract.totalSupply();
    initialReserve = ntzAddr.balance;
    uint256 ceiling = NutzContract.ceiling();
    // move ceiling
    uint256 newCeiling = ceiling.mul(discountRate).div(RATE_FACTOR);
    NutzContract.moveCeiling(newCeiling);
    // set state
    state = EventState.Collecting;
  }
  
  function stopCollection() isState(EventState.Collecting) {
    var NutzContract = Nutz(ntzAddr);
    uint256 collected = ntzAddr.balance.sub(initialReserve);
    if (now > startTime.add(maxDuration)) {
      if (collected >= softCap) {
        // softCap reached, close
        state = EventState.Closed;
        return;
      } else {
        // softCap missed, fail
        state = EventState.Failed;
        return;
      }
    } else if (now > startTime.add(minDuration)) {
      if (collected >= hardCap) {
        // hardCap reached, close
        state = EventState.Closed;
        return;
      } else {
        // keep going
        revert();
      }
    }
    // keep going
    revert();
  }
  
  function completeFailed() isState(EventState.Failed) {
    var NutzContract = Nutz(ntzAddr);
    // move floor (set ceiling or max floor)
    uint256 ceiling = NutzContract.ceiling();
    NutzContract.moveFloor(ceiling);
    // remove access
    NutzContract.removeAdmin(address(this));
    // set state
    state = EventState.Complete;
  }
  
  function completeClosed() isState(EventState.Closed) {
    var NutzContract = Nutz(ntzAddr);
    // move ceiling
    uint256 ceiling = NutzContract.ceiling();
    uint256 newCeiling = ceiling.mul(RATE_FACTOR).div(discountRate);
    NutzContract.moveCeiling(newCeiling);
    // dilute power
    uint256 newSupply = NutzContract.totalSupply().sub(initialSupply);
    NutzContract.dilutePower(newSupply);
    // set max power
    var PowerContract = ERC20(powerAddr);
    uint256 authorizedPower = PowerContract.totalSupply();
    NutzContract.setMaxPower(authorizedPower);
    // pay out milestone
    uint256 collected = ntzAddr.balance.sub(initialReserve);
    for (uint256 i = 0; i < milestoneRecipients.length; i++) {
      uint256 payoutAmount = collected.mul(milestoneShares[i]).div(RATE_FACTOR);
      NutzContract.allocateEther(payoutAmount, milestoneRecipients[i]);
    }
    // remove access
    NutzContract.removeAdmin(address(this));
    // set state
    state = EventState.Complete;
  }
  
}
