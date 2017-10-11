pragma solidity ^0.4.11;

import '../controller/Controller.sol';
import '../ownership/Ownable.sol';

contract UpgradeEventCompact {

  // states
  //  - verifying, initial state
  //  - controlling, after verifying, before complete
  //  - complete, after controlling
  enum EventState { Verifying, Complete }
  EventState public state;

  // Terms
  address public nextController;
  address public oldController;
  address public council;

  // Params
  address nextPullPayment;
  address storageAddr;
  address nutzAddr;
  address powerAddr;
  uint256 maxPower;
  uint256 downtime;
  uint256 purchasePrice;
  uint256 salePrice;

  function UpgradeEventCompact(address _oldController, address _nextController, address _nextPullPayment) {
    state = EventState.Verifying;
    nextController = _nextController;
    oldController = _oldController;
    nextPullPayment = _nextPullPayment; //the ownership of this satellite should be with oldController
    council = msg.sender;
  }

  modifier isState(EventState _state) {
    require(state == _state);
    _;
  }

  function upgrade() isState(EventState.Verifying) {
    // check old controller
    var old = Controller(oldController);
    old.pause();
    require(old.admins(1) == address(this));
    require(old.paused() == true);
    // check next controller
    var next = Controller(nextController);
    require(next.admins(1) == address(this));
    require(next.paused() == true);
    // kill old one, and transfer ownership
    // transfer ownership of payments and storage to here
    storageAddr = old.storageAddr();
    nutzAddr = old.nutzAddr();
    powerAddr = old.powerAddr();
    maxPower = old.maxPower();
    downtime = old.downtime();
    purchasePrice = old.ceiling();
    salePrice = old.floor();
    //set pull payment contract in old controller
    old.setContracts(powerAddr, nextPullPayment, nutzAddr, storageAddr);
    // kill old controller, sending all ETH to new controller
    old.kill(nextController);
    // transfer ownership of Nutz/Power contracts to next controller
    Ownable(nutzAddr).transferOwnership(nextController);
    Ownable(powerAddr).transferOwnership(nextController);
    // transfer ownership of storage to next controller
    Ownable(storageAddr).transferOwnership(nextController);
    // if intended, transfer ownership of pull payment account
    Ownable(nextPullPayment).transferOwnership(nextController);
    // resume next controller
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
