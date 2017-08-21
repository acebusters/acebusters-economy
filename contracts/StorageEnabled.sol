pragma solidity 0.4.11;

import "./Storage.sol";

contract StorageEnabled {

  // satelite contract addresses
  address public storageAddr;

  function StorageEnabled(address _storageAddr) {
    storageAddr = _storageAddr;
  }


  // ############################################
  // ########### NUTZ FUNCTIONS  ################
  // ############################################


  // all Nutz balances
  function babzBalanceOf(address _owner) constant returns (uint256) {
    return Storage(storageAddr).getBal('Nutz', _owner);
  }
  function _setBabzBalanceOf(address _owner, uint256 _newValue) internal {
    Storage(storageAddr).setBal('Nutz', _owner, _newValue);
  }
  // active supply - sum of balances above
  function activeSupply() constant returns (uint256) {
    return Storage(storageAddr).getUInt('Nutz', 'activeSupply');
  }
  function _setActiveSupply(uint256 _newActiveSupply) internal {
    Storage(storageAddr).setUInt('Nutz', 'activeSupply', _newActiveSupply);
  }
  // burn pool - inactive supply
  function burnPool() constant returns (uint256) {
    return Storage(storageAddr).getUInt('Nutz', 'burnPool');
  }
  function _setBurnPool(uint256 _newBurnPool) internal {
    Storage(storageAddr).setUInt('Nutz', 'burnPool', _newBurnPool);
  }
  // power pool - inactive supply
  function powerPool() constant returns (uint256) {
    return Storage(storageAddr).getUInt('Nutz', 'powerPool');
  }
  function _setPowerPool(uint256 _newPowerPool) internal {
    Storage(storageAddr).setUInt('Nutz', 'powerPool', _newPowerPool);
  }





  // ############################################
  // ########### POWER   FUNCTIONS  #############
  // ############################################

  // all power balances
  function powerBalanceOf(address _owner) constant returns (uint256) {
    return Storage(storageAddr).getBal('Power', _owner);
  }

  function _setPowerBalanceOf(address _owner, uint256 _newValue) internal {
    Storage(storageAddr).setBal('Power', _owner, _newValue);
  }

  function outstandingPower() constant returns (uint256) {
    return Storage(storageAddr).getUInt('Power', 'outstandingPower');
  }

  function _setOutstandingPower(uint256 _newOutstandingPower) internal {
    Storage(storageAddr).setUInt('Power', 'outstandingPower', _newOutstandingPower);
  }

  function authorizedPower() constant returns (uint256) {
    return Storage(storageAddr).getUInt('Power', 'authorizedPower');
  }

  function _setAuthorizedPower(uint256 _newAuthorizedPower) internal {
    Storage(storageAddr).setUInt('Power', 'authorizedPower', _newAuthorizedPower);
  }

}
