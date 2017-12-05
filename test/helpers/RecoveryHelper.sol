pragma solidity ^0.4.11;

contract RecoveryHelper {

  address public nutzAddr;

  function RecoveryHelper(address _nutzAddr) payable {
    nutzAddr = _nutzAddr;
  }

  function kill() public {
    selfdestruct(nutzAddr);
  }
}
