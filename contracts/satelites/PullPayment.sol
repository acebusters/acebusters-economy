pragma solidity ^0.4.11;


import '../SafeMath.sol';
import "../ownership/Ownable.sol";
import "../controller/ControllerInterface.sol";

/**
 * @title PullPayment
 * @dev Base contract supporting async send for pull payments.
 */
contract PullPayment is Ownable {
  using SafeMath for uint256;

  modifier onlyNutz() {
    require(msg.sender == ControllerInterface(owner).nutzAddr());
    _;
  }

  function dailyLimit() constant returns (uint256) {
    return ControllerInterface(owner).dailyLimit();
  }

  function lastDay() constant returns (uint256) {
    return ControllerInterface(owner).lastDay();
  }

  function spentToday() constant returns (uint256) {
    return ControllerInterface(owner).spentToday();
  }

  function balanceOf(address _owner) constant returns (uint256) {
    return ControllerInterface(owner).ethBalanceOf(_owner);
  }

  function paymentOf(address _owner) constant returns (uint256, uint256) {
    return ControllerInterface(owner).paymentOf(_owner);
  }

  function withdraw() public {
    address untrustedRecipient = msg.sender;
    uint256 amountWei = ControllerInterface(owner).withdraw(untrustedRecipient);
    assert(untrustedRecipient.call.gas(1000).value(amountWei)());
  }

  function asyncSend(address _dest) public payable onlyNutz {

  }

}
