pragma solidity 0.4.11;

import "./SafeMath.sol";

import "./Nutz.sol";
import "./Power.sol";
import "./PullPayment.sol";
import "./Storage.sol";
import "./ControllerInterface.sol";
import "./ERC223ReceivingContract.sol";

contract Controller {
  using SafeMath for uint;


  // ############################################
  // ########### ADMIN FUNCTIONS ################
  // ############################################

  // list of admins, council at first spot
  address[] public admins;

  function Controller() {
    admins.length = 1;
    admins[0] = msg.sender;
  }

  modifier onlyAdmins() {
    bool isAdmin = false;
    for (uint256 i = 0; i < admins.length; i++) {
      if (msg.sender == admins[i]) {
        isAdmin = true;
      }
    }
    require(isAdmin == true);
    _;
  }

  function addAdmin(address _admin) public onlyAdmins {
    for (uint256 i = 0; i < admins.length; i++) {
      require(_admin != admins[i]);
    }
    require(admins.length < 10);
    admins[admins.length++] = _admin;
  }

  function removeAdmin(address _admin) public onlyAdmins {
    uint256 pos = admins.length;
    for (uint256 i = 0; i < admins.length; i++) {
      if (_admin == admins[i]) {
        pos = i;
      }
    }
    require(pos < admins.length);
    // if not last element, switch with last
    if (pos < admins.length - 1) {
      admins[pos] = admins[admins.length - 1];
    }
    // then cut off the tail
    admins.length--;
  }

  // satelite contract addresses
  address public storageAddr;
  address public nutzAddr;
  address public powerAddr;
  address public pullAddr;

  function setContracts(address _storageAddr, address _nutzAddr, address _powerAddr, address _pullAddr) public onlyAdmins {
    storageAddr = _storageAddr;
    nutzAddr = _nutzAddr;
    powerAddr = _powerAddr;
    pullAddr = _pullAddr;
  }

  // withdraw excessive reserve - i.e. milestones
  function allocateEther(uint256 _amountWei, address _beneficiary) public onlyAdmins {
    require(_amountWei > 0);
    // allocateEther fails if allocating those funds would mean that the
    // sale mechanism is no longer able to buy back all tokens at the floor
    // price if those funds were to be withdrawn.
    require(this.balance.sub(_amountWei) >= activeSupply().mul(1000000).div(salePrice)); // 1,000,000 WEI, used as price factor
    PullPayment(pullAddr).asyncSend.value(_amountWei)(_beneficiary);
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
  // total supply
  function totalSupply() constant returns (uint256) {
    return activeSupply().add(powerPool()).add(burnPool());
  }

  modifier onlyNutz() {
    require(msg.sender == nutzAddr);
    _;
  }

  // allowances according to ERC20
  // not written to storage, as not very critical
  mapping (address => mapping (address => uint)) internal allowed;

  function allowance(address _owner, address _spender) constant returns (uint256) {
    return allowed[_owner][_spender];
  }

  function approve(address _owner, address _spender, uint256 _amountBabz) public onlyNutz {
    allowed[_owner][_spender] = _amountBabz;
  }

  // this flag allows or denies deposits of NTZ into non-contract accounts
  bool public onlyContractHolders;

  function setOnlyContractHolders(bool _onlyContractHolders) public onlyAdmins {
    onlyContractHolders = _onlyContractHolders;
  }

  function _checkDestination(address _from, address _to, uint256 _value, bytes _data) internal {
    // erc223: Retrieve the size of the code on target address, this needs assembly .
    uint256 codeLength;
    assembly {
      codeLength := extcodesize(_to)
    }
    if(codeLength>0) {
      ERC223ReceivingContract untrustedReceiver = ERC223ReceivingContract(_to);
      // untrusted contract call
      untrustedReceiver.tokenFallback(_from, _value, _data);
    } else {
      require(onlyContractHolders == false);
    }
  }

  // assumption that params have allready be sanity checked:
  // require(_from != _to)
  // require(_from != powerAddr)
  function _transfer(address _from, address _to, uint256 _amountBabz, bytes _data) internal {
    _setBabzBalanceOf(_from, babzBalanceOf(_from).sub(_amountBabz));
    _setBabzBalanceOf(_to, babzBalanceOf(_to).sub(_amountBabz));
    _checkDestination(_from, _to, _amountBabz, _data);
  }

  function transfer(address _from, address _to, uint256 _amountBabz, bytes _data) public onlyNutz {
    _transfer(_from, _to, _amountBabz, _data);
  }

  function transferFrom(address _sender, address _from, address _to, uint256 _amountBabz, bytes _data) public onlyNutz returns (bool) {
    require(_from != _to);
    require(_to != address(this));
    require(_amountBabz > 0);
    if (_to == powerAddr) {
      powerUp(_from, _amountBabz);
      return true;
    }
    if (_from == powerAddr) {
      // 3rd party power up:
      // - first transfer NTZ to account of receiver
      // - then power up that amount of NTZ in the account of receiver
      _setBabzBalanceOf(_sender, babzBalanceOf(_sender).sub(_amountBabz));
      _setBabzBalanceOf(_to, babzBalanceOf(_to).add(_amountBabz));
      powerUp(_to, _amountBabz);
      return true;
    } else {
      // usual transfer
      allowed[_from][_sender] = allowed[_from][_sender].sub(_amountBabz);
      _transfer(_from, _to, _amountBabz, _data);
      return true;
    }
  }

  // this is called when NTZ are deposited into the power pool
  function powerUp(address _from, uint256 _amountBabz) public onlyNutz {
    uint256 authorizedPow = authorizedPower();
    require(authorizedPow != 0);
    require(_amountBabz != 0);
    uint256 totalBabz = totalSupply();
    require(totalBabz != 0);
    uint256 amountPow = _amountBabz.mul(authorizedPow).div(totalBabz);
    // check pow limits
    uint256 outstandingPow = outstandingPower();
    require(outstandingPow.add(amountPow) <= maxPower);
    _setOutstandingPower(outstandingPow.add(amountPow));
    
    uint256 powBal = powerBalanceOf(_from).add(amountPow);
    require(powBal >= authorizedPow.div(10000)); // minShare = 10000
    _setPowerBalanceOf(_from, powBal);
    _setActiveSupply(activeSupply().sub(_amountBabz));
    _setBabzBalanceOf(_from, babzBalanceOf(_from).sub(_amountBabz));
    _setPowerPool(powerPool().add(_amountBabz));
  }





  // ############################################
  // ########### MARKET FUNCTIONS ###############
  // ############################################


  // the Token sale mechanism parameters:
  // purchasePrice is the number of NTZ received for purchase with 1 ETH
  uint256 internal purchasePrice;

  function ceiling() constant returns (uint256) {
    return purchasePrice;
  }
  // floor is the number of NTZ needed, to receive 1 ETH in sell
  uint256 internal salePrice;


  // returns either the salePrice, or if reserve does not suffice
  // for active supply, returns maxFloor
  function floor() constant returns (uint256) {
    if (this.balance == 0) {
      return 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff; // infinity
    }
    uint256 maxFloor = activeSupply().mul(1000000).div(this.balance); // 1,000,000 WEI, used as price factor
    // return max of maxFloor or salePrice
    return maxFloor >= salePrice ? maxFloor : salePrice;
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
    uint256 INFINITY = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    if (_newSalePrice < INFINITY) {
      require(this.balance >= activeSupply().mul(1000000).div(_newSalePrice)); // 1,000,000 WEI, used as price factor
    }
    salePrice = _newSalePrice;
  }

  function purchase(address _sender) public onlyNutz payable returns (uint256) {
    // disable purchases if purchasePrice set to 0
    require(purchasePrice > 0);

    uint256 amountBabz = purchasePrice.mul(msg.value).div(1000000); // 1,000,000 WEI, used as price factor
    // avoid deposits that issue nothing
    // might happen with very high purchase price
    require(amountBabz > 0);

    // make sure power pool grows proportional to economy
    uint256 activeSup = activeSupply();
    uint256 powPool = powerPool();
    if (powerAddr != 0x0 && powPool > 0) {
      uint256 powerShare = powPool.mul(amountBabz).div(activeSup.add(burnPool()));
      _setPowerPool(powPool.add(powerShare));
    }
    _setActiveSupply(activeSup.add(amountBabz));
    _setBabzBalanceOf(_sender, babzBalanceOf(_sender).add(amountBabz));

    bytes memory empty;
    _checkDestination(address(this), _sender, amountBabz, empty);
    return amountBabz;
  }

  function sell(address _from, uint256 _amountBabz) public onlyNutz {
    uint256 effectiveFloor = floor();
    uint256 INFINITY = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    require(effectiveFloor != INFINITY);

    uint256 amountWei = _amountBabz.mul(1000000).div(effectiveFloor);  // 1,000,000 WEI, used as price factor
    // make sure power pool shrinks proportional to economy
    uint256 powPool = powerPool();
    uint256 activeSup = activeSupply();
    if (powPool > 0) {
      uint256 powerShare = powPool.mul(_amountBabz).div(activeSup);
      _setPowerPool(powPool.sub(powerShare));
    }
    _setActiveSupply(activeSup.sub(_amountBabz));
    _setBabzBalanceOf(_from, babzBalanceOf(_from).sub(_amountBabz));
    assert(amountWei <= this.balance);
    PullPayment(pullAddr).asyncSend.value(amountWei)(_from);
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

  // sum of all outstanding power
  function outstandingPower() constant returns (uint256) {
    return Storage(storageAddr).getUInt('Power', 'outstandingPower');
  }

  function _setOutstandingPower(uint256 _newOutstandingPower) internal {
    Storage(storageAddr).setUInt('Power', 'outstandingPower', _newOutstandingPower);
  }

  // authorized power
  function authorizedPower() constant returns (uint256) {
    return Storage(storageAddr).getUInt('Power', 'authorizedPower');
  }

  function _setAuthorizedPower(uint256 _newAuthorizedPower) internal {
    Storage(storageAddr).setUInt('Power', 'authorizedPower', _newAuthorizedPower);
  }

  function powerTotalSupply() constant returns (uint256) {
    uint256 issuedPower = authorizedPower().div(2);
    // return max of maxPower or issuedPower
    return maxPower >= issuedPower ? maxPower : issuedPower;
  }

  modifier onlyPower() {
    require(msg.sender == powerAddr);
    _;
  }

  // data structure for withdrawals
  struct DownRequest {
    address owner;
    uint256 total;
    uint256 left;
    uint256 start;
  }
  DownRequest[] public downs;


  function vestedDown(uint256 _pos, uint256 _now) constant returns (uint256) {
    if (downs.length <= _pos) {
      return 0;
    }
    if (_now <= downs[_pos].start) {
      return 0;
    }
    // calculate amountVested
    // amountVested is amount that can be withdrawn according to time passed
    DownRequest storage req = downs[_pos];
    uint256 timePassed = _now.sub(req.start);
    if (timePassed > downtime) {
     timePassed = downtime;
    }
    uint256 amountVested = req.total.mul(timePassed).div(downtime);
    uint256 amountFrozen = req.total.sub(amountVested);
    if (req.left <= amountFrozen) {
      return 0;
    }
    return req.left.sub(amountFrozen);
  }

  function createDownRequest(address _owner, uint256 _amountPower) public onlyPower {
    // prevent powering down tiny amounts
    // when powering down, at least totalSupply/minShare Power should be claimed
    require(_amountPower >= authorizedPower().div(10000)); // minShare = 10000;
    _setPowerBalanceOf(_owner, powerBalanceOf(_owner).sub(_amountPower));
    uint256 pos = downs.length++;
    downs[pos] = DownRequest(_owner, _amountPower, _amountPower, now);
  }

  // executes a powerdown request
  function downTick(uint256 _pos, uint256 _now) public onlyPower {
    require(msg.sender == powerAddr);
    uint256 amountPow = vestedDown(_pos, _now);
    DownRequest storage req = downs[_pos];

    // prevent power down in tiny steps
    uint256 minStep = req.total.div(10);
    require(req.left <= minStep || minStep <= amountPow);

    // calculate token amount representing share of power
    uint256 amountBabz = amountPow.mul(totalSupply()).div(authorizedPower());
    // transfer power and tokens
    _setOutstandingPower(outstandingPower().sub(amountPow));
    req.left = req.left.sub(amountPow);
    _setPowerPool(powerPool().sub(amountBabz));
    _setActiveSupply(activeSupply().add(amountBabz));
    _setBabzBalanceOf(req.owner, babzBalanceOf(req.owner).add(amountBabz));
    bytes memory empty;
    _checkDestination(powerAddr, req.owner, amountBabz, empty);

    // down request completed
    if (req.left == 0) {
      // if not last element, switch with last
      if (_pos < downs.length - 1) {
        downs[_pos] = downs[downs.length - 1];
      }
      // then cut off the tail
      downs.length--;
    }
  }

  // this is called when NTZ are deposited into the burn pool
  function dilutePower(uint256 _amountBabz) public onlyAdmins {
    uint256 authorizedPow = authorizedPower();
    if (authorizedPow == 0) {
      // during the first capital increase, set some big number as authorized shares
      _setAuthorizedPower(totalSupply().add(_amountBabz));
    } else {
      uint256 totalBabz = totalSupply();
      // in later increases, expand authorized shares at same rate like economy
      _setAuthorizedPower(authorizedPow.mul(totalBabz.add(_amountBabz)).div(totalBabz));
    }
    _setBurnPool(burnPool().add(_amountBabz));
  }

  // maxPower is a limit of total power that can be outstanding
  // maxPower has a valid value between outstandingPower and authorizedPow/2
  uint256 public maxPower = 0;

  function setMaxPower(uint256 _maxPower) public onlyAdmins {
    require(outstandingPower() <= _maxPower && _maxPower < authorizedPower());
    maxPower = _maxPower;
  }

  function _slashPower(address _holder, uint256 _value, bytes32 _data) internal {
    uint256 previouslyOutstanding = outstandingPower();
    _setOutstandingPower(previouslyOutstanding.sub(_value));
    // adjust size of power pool
    uint256 powPool = powerPool();
    uint256 slashingBabz = _value.mul(powPool).div(previouslyOutstanding);
    _setPowerPool(powPool.sub(slashingBabz));
    // put event into satelite contract
    Power(powerAddr).slashPower(_holder, _value, _data);
  }

  function slashPower(address _holder, uint256 _value, bytes32 _data) public onlyAdmins {
    _setPowerBalanceOf(_holder, powerBalanceOf(_holder).sub(_value));
    _slashPower(_holder, _value, _data);
  }

  function slashDownRequest(uint256 _pos, address _holder, uint256 _value, bytes32 _data) public onlyAdmins {
    DownRequest storage req = downs[_pos];
    require(req.owner == _holder);
    req.left = req.left.sub(_value);
    _slashPower(_holder, _value, _data);
  }

  // time it should take to power down
  uint256 public downtime;

  function setDowntime(uint256 _downtime) public onlyAdmins {
    downtime = _downtime;
  }

}
