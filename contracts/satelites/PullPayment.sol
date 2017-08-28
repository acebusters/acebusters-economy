pragma solidity 0.4.11;


import '../SafeMath.sol';
import "../ownership/Ownable.sol";


/**
 * @title PullPayment
 * @dev Base contract supporting async send for pull payments. 
 */
contract PullPayment is Ownable {
  using SafeMath for uint256;

  struct Payment {
    uint256 value;  // TODO: use compact storage
    uint256 date;   // 
  }

  uint public dailyLimit = 1000000000000000000000;  // 1 ETH
  uint public lastDay;
  uint public spentToday;

  mapping(address => Payment) internal payments;

  function balanceOf(address _owner) constant returns (uint256 value) {
    return payments[_owner].value;
  }

  function paymentOf(address _owner) constant returns (uint256 value, uint256 date) {
    value = payments[_owner].value;
    date = payments[_owner].date;
    return;
  }

  /// @dev Allows to change the daily limit. Transaction has to be sent by wallet.
  /// @param _dailyLimit Amount in wei.
  function changeDailyLimit(uint _dailyLimit) public onlyOwner {
      dailyLimit = _dailyLimit;
  }

  function changeWithdrawalDate(address _owner, uint256 _newDate)  public onlyOwner {
    // allow to withdraw immediately
    // move witdrawal date more days into future
    payments[_owner].date = _newDate;
  }

  function asyncSend(address _dest) public payable onlyOwner {
    require(msg.value > 0);
    uint256 newValue = payments[_dest].value.add(msg.value);
    uint256 newDate;
    if (isUnderLimit(msg.value)) {
      newDate = (payments[_dest].date > now) ? payments[_dest].date : now;
    } else {
      newDate = now.add(3 days);
    }
    spentToday = spentToday.add(msg.value);
    payments[_dest] = Payment(newValue, newDate);
  }


  function withdraw() public {
    address untrustedRecipient = msg.sender;
    uint256 amountWei = payments[untrustedRecipient].value;

    require(amountWei != 0);
    require(now >= payments[untrustedRecipient].date);
    require(this.balance >= amountWei);

    payments[untrustedRecipient].value = 0;

    assert(untrustedRecipient.send(amountWei));
  }

  /*
   * Internal functions
   */
  /// @dev Returns if amount is within daily limit and resets spentToday after one day.
  /// @param amount Amount to withdraw.
  /// @return Returns if amount is under daily limit.
  function isUnderLimit(uint amount) internal returns (bool) {
    if (now > lastDay.add(24 hours)) {
      lastDay = now;
      spentToday = 0;
    }
    // not using safe math because we don't want to throw;
    if (spentToday + amount > dailyLimit || spentToday + amount < spentToday) {
      return false;
    }
    return true;
  }

}