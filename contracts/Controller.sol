pragma solidity 0.4.11;

import "./PowerEnabled.sol";

contract Controller is PowerEnabled {

  function Controller(address _powerAddr, address _pullAddr, address _nutzAddr, address _storageAddr) 
    PowerEnabled(_powerAddr, _pullAddr, _nutzAddr, _storageAddr) {
  }

  function setContracts(address _storageAddr, address _nutzAddr, address _powerAddr, address _pullAddr) public onlyAdmins whenPaused {
    storageAddr = _storageAddr;
    nutzAddr = _nutzAddr;
    powerAddr = _powerAddr;
    pullAddr = _pullAddr;
  }

  function kill() public onlyAdmins whenPaused {
    Ownable(powerAddr).transferOwnership(msg.sender);
    Ownable(pullAddr).transferOwnership(msg.sender);
    Ownable(nutzAddr).transferOwnership(msg.sender);
    Ownable(storageAddr).transferOwnership(msg.sender);
    selfdestruct(msg.sender);
  }

}
