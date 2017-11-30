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
  address internal nextPullPayment;
  address internal nextNutz;
  address internal storageAddr;
  address internal powerAddr;
  uint256 internal maxPower;
  uint256 internal downtime;
  uint256 internal purchasePrice;
  uint256 internal salePrice;

  function UpgradeEventCompact(address _oldController, address _nextController, address _nextPullPayment, address _nextNutz) {
    state = EventState.Verifying;
    nextController = _nextController;
    oldController = _oldController;
    nextPullPayment = _nextPullPayment; //the ownership of this satellite should be with oldController
    nextNutz = _nextNutz;
    council = msg.sender;
  }

  modifier isState(EventState _state) {
    require(state == _state);
    _;
  }

  function upgrade() isState(EventState.Verifying) {
    // check old controller
    var old = Controller(oldController);
    require(old.admins(1) == address(this));
    // check next controller
    var next = Controller(nextController);
    require(next.admins(1) == address(this));
    require(next.paused() == true);
    // transfer ownership of payments and storage to here
    address nutzAddr = old.nutzAddr();
    address pullAddr = old.pullAddr();
    storageAddr = old.storageAddr();
    powerAddr = old.powerAddr();
    maxPower = old.maxPower();
    downtime = old.downtime();
    purchasePrice = old.ceiling();
    salePrice = old.floor();
    // check the balance in old nutz contract
    uint256 reserve = nutzAddr.balance;
    old.moveFloor(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
    old.allocateEther(reserve, address(this));
    PullPayment(pullAddr).withdraw();
    old.pause();
    require(old.paused() == true);
    // move floor and allocate ether
    //set pull payment contract in old controller
    old.setContracts(powerAddr, nextPullPayment, nextNutz, storageAddr);
    // kill old controller, sending all ETH to new controller
    old.kill(nextController);
    // transfer reserve to the Nutz contract
    Nutz(nextNutz).upgrade.value(reserve)();
    // transfer ownership of Nutz/Power contracts to next controller
    Ownable(nextNutz).transferOwnership(nextController);
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

  function() payable {

  }
}
