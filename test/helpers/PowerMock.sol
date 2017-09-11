pragma solidity 0.4.11;

import '../../contracts/satelites/Power.sol';

contract PowerMock is Power {

  function downTickTest(address _owner, uint256 _pos, uint256 _now) public {
    ControllerInterface(owner).downTick(_owner, _pos, _now);
  }

}
