pragma solidity ^0.4.11;

import "../satelites/PullPayment.sol";
import "./NutzEnabled.sol";
import "../satelites/Nutz.sol";

contract MarketEnabled is NutzEnabled {

  uint256 constant INFINITY = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

  // address of the pull payemnt satelite
  address public pullAddr;

  // not written to storage satellite because easily transferrable to new controller
  uint256 public dailyLimit = 1000000000000000000000;  // 1 ETH
  uint256 public lastDay;
  uint256 public spentToday;

  // the Token sale mechanism parameters:
  // purchasePrice is the number of NTZ received for purchase with 1 ETH
  uint256 internal purchasePrice;

  // floor is the number of NTZ needed, to receive 1 ETH in sell
  uint256 internal salePrice;

  modifier onlyPull() {
    require(msg.sender == pullAddr);
    _;
  }

  function MarketEnabled(address _pullAddr, address _storageAddr, address _nutzAddr)
    NutzEnabled(_nutzAddr, _storageAddr) {
    pullAddr = _pullAddr;
  }


  function ceiling() constant returns (uint256) {
    return purchasePrice;
  }

  // returns either the salePrice, or if reserve does not suffice
  // for active supply, returns maxFloor
  function floor() constant returns (uint256) {
    if (nutzAddr.balance == 0) {
      return INFINITY;
    }
    uint256 maxFloor = activeSupply().mul(1000000).div(nutzAddr.balance); // 1,000,000 WEI, used as price factor
    // return max of maxFloor or salePrice
    return maxFloor >= salePrice ? maxFloor : salePrice;
  }

  // ############################################
  // ########### PULLPAY FUNCTIONS  #############
  // ############################################

  function ethBalanceOf(address _owner) constant returns (uint256 value) {
    return getPayBalance(_owner);
  }

  function paymentOf(address _owner) constant returns (uint256 value, uint256 date) {
    return getPayments(_owner);
  }


  // ############################################
  // ########### ADMIN FUNCTIONS  ###############
  // ############################################

  /// @dev Allows to change the daily limit. Transaction has to be sent by wallet.
  /// @param _dailyLimit Amount in wei.
  function changeDailyLimit(uint256 _dailyLimit) public onlyAdmins {
      dailyLimit = _dailyLimit;
  }

  function changeWithdrawalDate(address _owner, uint256 _newDate)  public onlyAdmins {
    // allow to withdraw immediately
    // move witdrawal date more days into future
    var (value, ) = getPayments(_owner);
    _setPayments(_owner, value, _newDate);
  }

  /// @dev Allows to set the lastDay. Mainly for the UpgradeEvent.
  function setLastDay(uint256 _lastDay) public onlyAdmins {
      lastDay = _lastDay;
  }
  /// @dev Allows to set the spentToday. Mainly for the UpgradeEvent.
  function setSpentToday(uint256 _spentToday) public onlyAdmins {
      spentToday = _spentToday;
  }

  function moveCeiling(uint256 _newPurchasePrice) public onlyAdmins {
    require(_newPurchasePrice <= salePrice);
    purchasePrice = _newPurchasePrice;
  }

  function moveFloor(uint256 _newSalePrice) public onlyAdmins {
    require(_newSalePrice >= purchasePrice);
    // moveFloor fails if the administrator tries to push the floor so low
    // that the sale mechanism is no longer able to buy back all tokens at
    // the floor price if those funds were to be withdrawn.
    if (_newSalePrice < INFINITY) {
      require(nutzAddr.balance >= activeSupply().mul(1000000).div(_newSalePrice)); // 1,000,000 WEI, used as price factor
    }
    salePrice = _newSalePrice;
  }

  // withdraw excessive reserve - i.e. milestones
  function allocateEther(uint256 _amountWei, address _beneficiary) public onlyAdmins {
    require(_amountWei > 0);
    // allocateEther fails if allocating those funds would mean that the
    // sale mechanism is no longer able to buy back all tokens at the floor
    // price if those funds were to be withdrawn.
    require(nutzAddr.balance.sub(_amountWei) >= activeSupply().mul(1000000).div(salePrice)); // 1,000,000 WEI, used as price factor
    _asyncSend(_beneficiary, _amountWei);
  }

  // ############################################
  // ########### MARKET FUNCTIONS  ##############
  // ############################################

  function purchase(address _sender, uint256 _value, uint256 _price) public onlyNutz whenNotPaused returns (uint256) {
    // disable purchases if purchasePrice set to 0
    require(purchasePrice > 0);
    require(_price == purchasePrice);

    uint256 amountBabz = purchasePrice.mul(_value).div(1000000); // 1,000,000 WEI, used as price factor
    // avoid deposits that issue nothing
    // might happen with very high purchase price
    require(amountBabz > 0);

    // make sure power pool grows proportional to economy
    uint256 activeSup = activeSupply();
    uint256 powPool = powerPool();
    if (powPool > 0) {
      uint256 powerShare = powPool.mul(amountBabz).div(activeSup.add(burnPool()));
      _setPowerPool(powPool.add(powerShare));
    }
    _setActiveSupply(activeSup.add(amountBabz));
    _setBabzBalanceOf(_sender, babzBalanceOf(_sender).add(amountBabz));
    return amountBabz;
  }

  function sell(address _from, uint256 _price, uint256 _amountBabz) public onlyNutz whenNotPaused {
    uint256 effectiveFloor = floor();
    require(_amountBabz != 0);
    require(effectiveFloor != INFINITY);
    require(_price == effectiveFloor);

    uint256 amountWei = _amountBabz.mul(1000000).div(effectiveFloor);  // 1,000,000 WEI, used as price factor
    require(amountWei > 0);
    // make sure power pool shrinks proportional to economy
    uint256 powPool = powerPool();
    uint256 activeSup = activeSupply();
    if (powPool > 0) {
      uint256 powerShare = powPool.mul(_amountBabz).div(activeSup.add(burnPool()));
      _setPowerPool(powPool.sub(powerShare));
    }
    _setActiveSupply(activeSup.sub(_amountBabz));
    _setBabzBalanceOf(_from, babzBalanceOf(_from).sub(_amountBabz));
    _asyncSend(_from, amountWei);
  }

  function withdraw(address _untrustedReceipient) public onlyPull whenNotPaused returns (uint256) {
    var(amountWei, date) = getPayments(_untrustedReceipient);

    require(amountWei != 0);
    require(now >= date);
    require(pullAddr.balance >= amountWei);

    _setPayments(_untrustedReceipient, 0, 0);
    return amountWei;
  }

  // ############################################
  // ########### INTERNAL FUNCTIONS  ############
  // ############################################

  function _asyncSend(address _dest, uint256 amountWei) internal {
    require(amountWei > 0);
    var (oldValue, ) = getPayments(_dest);
    uint256 newValue = amountWei.add(oldValue);
    uint256 newDate;
    if (isUnderLimit(amountWei)) {
      var (, date) = getPayments(_dest);
      newDate = (date > now) ? date : now;
    } else {
      newDate = now.add(3 days);
    }
    spentToday = spentToday.add(amountWei);
    _setPayments(_dest, newValue, newDate);
    Nutz(nutzAddr).asyncSend(pullAddr, _dest, amountWei);
   }

  /// @dev Returns if amount is within daily limit and resets spentToday after one day.
  /// @param amount Amount to withdraw.
  /// @return Returns if amount is under daily limit.
  function isUnderLimit(uint256 amount) internal returns (bool) {
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
