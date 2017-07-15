pragma solidity ^0.4.11;

import '../../contracts/Nutz.sol';

contract NutzMock is Nutz {
  
  function NutzMock(uint256 _value) Nutz(0) {
    admins.length = 1;
    admins[0] = msg.sender;
    // initial purchase price
    ceiling = 12000;
    // initial sale price
    setFloor = 15000;
    powerAddr = new Power(address(this), 0);

    actSupply = actSupply.add(_value);
    balances[msg.sender] = balances[msg.sender].add(_value);
  }

}
