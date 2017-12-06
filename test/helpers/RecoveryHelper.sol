pragma solidity ^0.4.11;

contract RecoveryHelper {

  address public destination;

  function RecoveryHelper(address _destination) payable {
    destination = _destination;
  }

  function kill() public {
    selfdestruct(destination);
  }
}
