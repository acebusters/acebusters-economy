pragma solidity ^0.4.11;


import '../../contracts/ERC223ReceivingContract.sol';


// mock class using StandardToken
contract ERC223ReceiverMock is ERC223ReceivingContract {

  bool public called = false;

  function tokenFallback(address _from, uint _value, bytes _data) {
    called = true;
  }

  function () payable {
  }

  function forward(address _to, uint256 _value) {
  	assert(_to.call.value(_value)());
  }

}