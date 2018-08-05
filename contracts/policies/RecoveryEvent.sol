pragma solidity ^0.4.11;

import '../controller/Controller.sol';
import "../SafeMath.sol";
import "../ERC20.sol";

contract RecoveryEvent {
  using SafeMath for uint;

  // states
  //  - verifying, initial state
  //  - controlling, after verifying, before complete
  //  - complete, after recovering
  enum EventState { Verifying, Recovering, Complete}
  EventState public state;

  // Terms
  address public nextController;
  address public oldController;
  address public council;

  // Params
  address internal pullAddr;
  address internal storageAddr;
  address internal nutzAddr;
  address internal powerAddr;
  address[] internal nutzHolders;
  uint256 internal maxPower;
  uint256 internal downtime;
  uint256 internal purchasePrice;
  uint256 internal salePrice;
  uint256[] internal rectifiedBalances;

  // need to make sure _rectifiedBalances are calculated after oldController is paused so that no sell occurs in between
  function RecoveryEvent(address _oldController, address _nextController, address[] _nutzHolders, uint256[] _rectifiedBalances) {
    require(_nutzHolders.length == _rectifiedBalances.length);
    state = EventState.Verifying;
    nextController = _nextController;
    oldController = _oldController;
    nutzHolders = _nutzHolders;
    rectifiedBalances = _rectifiedBalances;
    council = msg.sender;
  }

  modifier isState(EventState _state) {
    require(state == _state);
    _;
  }

  function tick() public {
    if (state == EventState.Verifying) {
      verify();
    } else if (state == EventState.Recovering) {
      recover();
    } else {
      throw;
    }
  }

  function verify() isState(EventState.Verifying) {
    // check old controller
    var old = Controller(oldController);
    require(old.admins(1) == address(this));
    require(old.paused() == true);
    // check next controller
    var next = Controller(nextController);
    require(next.admins(1) == address(this));
    require(next.paused() == true);
    // kill old one, and transfer ownership
    // transfer ownership of payments and storage to here
    pullAddr = old.pullAddr();
    storageAddr = old.storageAddr();
    nutzAddr = old.nutzAddr();
    powerAddr = old.powerAddr();
    maxPower = old.maxPower();
    downtime = old.downtime();
    purchasePrice = old.ceiling();
    salePrice = old.floor();
    // kill old controller, sending all ETH to new controller
    old.kill(nextController);
    // transfer ownership of Nutz/Power contracts to next controller
    Ownable(nutzAddr).transferOwnership(nextController);
    Ownable(powerAddr).transferOwnership(nextController);
    Ownable(pullAddr).transferOwnership(nextController);
    // ownership of storage remains with the RecoveryEvent
    state = EventState.Recovering;
  }

  function recover() isState(EventState.Recovering) {
    // rectify balances
    for(uint8 i = 0; i < nutzHolders.length; i++) {
      Storage(storageAddr).setBal('Nutz', nutzHolders[i], rectifiedBalances[i]);
    }
    // transfer ownership of storage to next controller after rectifying balances
    Ownable(storageAddr).transferOwnership(nextController);
    // resume next controller
    var next = Controller(nextController);
    if (maxPower > 0) {
      next.setMaxPower(maxPower);
    }
    next.setDowntime(downtime);
    next.moveFloor(salePrice);
    next.moveCeiling(purchasePrice);
    next.unpause();
    // remove access
    next.removeAdmin(address(this));
    // set state
    state = EventState.Complete;
  }

}
