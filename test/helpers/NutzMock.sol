pragma solidity ^0.4.11;

import '../../contracts/Nutz.sol';

contract NutzMock is Nutz {
  
  function NutzMock(uint _downtime, uint256 _value, uint256 _ceiling, uint256 _floor) Nutz(_downtime) {
    // initial purchase price
    ceiling = _ceiling;
    // initial sale price
    salePrice = _floor;
    onlyContractHolders = false;

    // initial balance (not backed by reserve)
    actSupply = actSupply.add(_value);
    balances[msg.sender] = balances[msg.sender].add(_value);
  }

}
