pragma solidity 0.4.11;

import '../../contracts/Nutz.sol';
import '../../contracts/Power.sol';
import '../../contracts/Controller.sol';
import '../../contracts/PullPayment.sol';

contract NutzMock is Controller {
  
  function NutzMock(uint _downtime, uint256 _value, uint256 _ceiling, uint256 _floor) {
    nutzAddr = new Nutz();
    powerAddr = new Power();
    pullAddr = new PullPayment();
    // initial purchase price
    ceiling = _ceiling;
    // initial sale price
    salePrice = _floor;
    onlyContractHolders = false;

    // initial balance (not backed by reserve)
    activeSupply = activeSupply.add(_value);
    balances[msg.sender] = balances[msg.sender].add(_value);
  }

}
