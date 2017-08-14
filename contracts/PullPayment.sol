pragma solidity 0.4.11;


import './SafeMath.sol';
import './Ownable.sol';


/**
 * @title PullPayment
 * @dev Base contract supporting async send for pull payments. 
 */
contract PullPayment is Ownable {
  using SafeMath for uint256;

  mapping(address => uint256) internal payments;

  uint256 internal totalPayments;

  function totalSupply() constant returns (uint256) {
    return totalPayments;
  }

  function balanceOf(address _owner) constant returns (uint256) {
    return payments[_owner];
  }

  function asyncSend(address _dest) payable onlyOwner {
    require(msg.value > 0);
    payments[_dest] = payments[_dest].add(msg.value);
    totalPayments = totalPayments.add(msg.value);
  }


  function withdraw() public {
    address untrustedRecipient = msg.sender;
    uint256 amountWei = payments[untrustedRecipient];

    require(amountWei != 0);
    require(this.balance >= amountWei);

    totalPayments = totalPayments.sub(amountWei);
    payments[untrustedRecipient] = 0;

    assert(untrustedRecipient.send(amountWei));
  }
}