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


  function Controller(address _storageAddr, address _nutzAddr, address _powerAddr, address _pullAddr, uint256 _downtime) {
    admins.length = 1;
    admins[0] = msg.sender;
    // initial purchase price
    ceiling = 0;
    // initial sale price
    uint256 INFINITY = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    salePrice = INFINITY;
    onlyContractHolders = false;
    
    storageAddr = _storageAddr;
    nutzAddr = _nutzAddr;
    powerAddr = _powerAddr;
    pullAddr = _pullAddr;
    downtime = _downtime;
  }


  // ############################################
  // ########### INTERNAL FUNCTIONS #############
  // ############################################

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

  function _transfer(address _from, address _to, uint256 _amountBabz, bytes _data) internal returns (bool) {
    require(_to != powerAddr);
    // power down
    if (_from == powerAddr) {
      activeSupply = activeSupply.add(_amountBabz);
    }

    balances[_from] = balances[_from].sub(_amountBabz);
    balances[_to] = balances[_to].add(_amountBabz);

    _checkDestination(_from, _to, _amountBabz, _data);
    return true;
  }


  // ############################################
  // ########### ADMIN FUNCTIONS ################
  // ############################################

  // this flag allows or denies deposits of NTZ into non-contract accounts
  bool public onlyContractHolders = true;
  // list of admins, council at first spot
  address[] public admins;
  // satelite contract addresses
  address public storageAddr;
  address public nutzAddr;
  address public powerAddr;
  address public pullAddr;

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
  
  function moveCeiling(uint256 _newCeiling) public onlyAdmins {
    require(_newCeiling <= salePrice);
    ceiling = _newCeiling;
  }
  
  function moveFloor(uint256 _newSalePrice) public onlyAdmins {
    require(_newSalePrice >= ceiling);
    // moveFloor fails if the administrator tries to push the floor so low
    // that the sale mechanism is no longer able to buy back all tokens at
    // the floor price if those funds were to be withdrawn.
    uint256 INFINITY = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    if (_newSalePrice < INFINITY) {
      require(this.balance >= activeSupply.mul(1000000).div(_newSalePrice)); // 1,000,000 WEI, used as price factor
    }
    salePrice = _newSalePrice;
  }

  function setOnlyContractHolders(bool _onlyContractHolders) public onlyAdmins {
    onlyContractHolders = _onlyContractHolders;
  }

  function allocateEther(uint256 _amountWei, address _beneficiary) public onlyAdmins {
    require(_amountWei > 0);
    // allocateEther fails if allocating those funds would mean that the
    // sale mechanism is no longer able to buy back all tokens at the floor
    // price if those funds were to be withdrawn.
    require(this.balance.sub(_amountWei) >= activeSupply.mul(1000000).div(salePrice)); // 1,000,000 WEI, used as price factor
    PullPayment(pullAddr).asyncSend.value(_amountWei)(_beneficiary);
  }

  // this is called when NTZ are deposited into the burn pool
  function dilutePower(uint256 _amountBabz) public onlyAdmins {
    if (authorizedPower == 0) {
      // during the first capital increase, set some big number as authorized shares
      uint256 totalSupply = activeSupply.add(balances[powerAddr]).add(burnPool);
      authorizedPower = totalSupply.add(_amountBabz);
    } else {
      // in later increases, expand authorized shares at same rate like economy
      authorizedPower = authorizedPower.mul(totalSupply.add(_amountBabz)).div(totalSupply);
    }
    burnPool = burnPool.add(_amountBabz);
  }

  function setMaxPower(uint256 _maxPower) public onlyAdmins {
    require(outstandingPower <= _maxPower && _maxPower < authorizedPower);
    maxPower = _maxPower;
  }

  function slashPower(address _holder, uint256 _value, bytes32 _data) public onlyAdmins {
    // get the previously outstanding power of which _value was slashed

    powBalance[_holder] = powBalance[_holder].sub(_value);
    uint256 previouslyOutstanding = outstandingPower;
    outstandingPower = outstandingPower.sub(_value);

    Power(powerAddr).slashPower(_holder, _value, _data);

    uint256 powerPool = balances[powerAddr];
    uint256 slashingBabz = _value.mul(powerPool).div(previouslyOutstanding);
    balances[powerAddr] = powerPool.sub(slashingBabz);
  }

  function slashDownRequest(uint256 _pos, address _holder, uint256 _value, bytes32 _data) public onlyAdmins {
    // get the previously outstanding power of which _value was slashed
    DownRequest storage req = downs[_pos];
    require(req.owner == _holder);
    req.left = req.left.sub(_value);
    uint256 previouslyOutstanding = outstandingPower;
    outstandingPower = outstandingPower.sub(_value);

    Power(powerAddr).slashPower(_holder, _value, _data);

    uint256 powerPool = balances[powerAddr];
    uint256 slashingBabz = _value.mul(powerPool).div(previouslyOutstanding);
    balances[powerAddr] = powerPool.sub(slashingBabz);
  }




  // ############################################
  // ########### POWER   FUNCTIONS  #############
  // ############################################

  // all power balances
  mapping (address => uint256) public powBalance;
  // sum of all outstanding power
  uint256 public outstandingPower = 0;
  // authorized power
  uint256 public authorizedPower = 0;
  // maxPower is a limit of total power that can be outstanding
  // maxPower has a valid value between outstandingPower and authorizedPow/2
  uint256 public maxPower = 0;

  // time it should take to power down
  uint256 public downtime;
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

  function getPowerBal(address _owner) constant public returns (uint256) {
    return powBalance[_owner];
  }

  modifier onlyPower() {
    require(msg.sender == powerAddr);
    _;
  }

  function setOutstandingPower(uint256 _value) public onlyPower {
    outstandingPower = _value;
  }

  function setAuthorizedPower(uint256 _value) public onlyPower {
    require(msg.sender == powerAddr);
    authorizedPower = _value;
  }

  function setPowBalance(address _owner, uint256 _value) public onlyPower {
    powBalance[_owner] = _value;
  }

  function createDownRequest(address _owner, uint256 _amountPower) public onlyPower {
    // prevent powering down tiny amounts
    // when powering down, at least totalSupply/minShare Power should be claimed
    require(_amountPower >= authorizedPower.div(10000)); // minShare = 10000;
    powBalance[_owner] = powBalance[_owner].sub(_amountPower);
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
    uint256 totalSupply = activeSupply.add(balances[powerAddr]).add(burnPool);
    uint256 amountBabz = amountPow.mul(totalSupply).div(authorizedPower);
    // transfer power and tokens
    outstandingPower = outstandingPower.sub(amountPow);
    req.left = req.left.sub(amountPow);
    bytes memory empty;
    assert(_transfer(powerAddr, req.owner, amountBabz, empty));
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




  // ############################################
  // ########### NUTZ FUNCTIONS  ################
  // ############################################

  // active supply
  uint256 public activeSupply;
  // burn pool - inactive supply
  uint256 public burnPool;
  // balanceOf[powerAddr] size of power pool
  // balance of active holders
  mapping(address => uint) internal balances;

  // the Token sale mechanism parameters:
  // ceiling is the number of NTZ received for purchase with 1 ETH
  uint256 public ceiling;
  // floor is the number of NTZ needed, to receive 1 ETH in sell
  uint256 internal salePrice;


  // returns either the salePrice, or if reserve does not suffice
  // for active supply, returns maxFloor
  function floor() constant returns (uint256) {
    if (this.balance == 0) {
      uint256 INFINITY = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
      return INFINITY;
    }
    uint256 maxFloor = activeSupply.mul(1000000).div(this.balance); // 1,000,000 WEI, used as price factor
    // return max of maxFloor or salePrice
    return maxFloor >= salePrice ? maxFloor : salePrice;
  }

  function powerPool() constant returns (uint256) {
    return balances[powerAddr];
  }



  modifier onlyNutz() {
    require(msg.sender == nutzAddr);
    _;
  }

  // allowances according to ERC20
  // not written to storage, as not very critical
  mapping (address => mapping (address => uint)) internal allowed;

  function approve(address _owner, address _spender, uint256 _amountBabz) public onlyNutz {
    allowed[_owner][_spender] = _amountBabz;
  }

  function purchase() public onlyNutz payable returns (uint256) {
    // disable purchases if ceiling set to 0
    require(ceiling > 0);

    uint256 amountBabz = ceiling.mul(msg.value).div(1000000); // 1,000,000 WEI, used as price factor
    // avoid deposits that issue nothing
    // might happen with very high purchase price
    require(amountBabz > 0);

    // make sure power pool grows proportional to economy
    if (powerAddr != 0x0 && balances[powerAddr] > 0) {
      uint256 powerShare = balances[powerAddr].mul(amountBabz).div(activeSupply.add(burnPool));
      balances[powerAddr] = balances[powerAddr].add(powerShare);
    }
    activeSupply = activeSupply.add(amountBabz);
    balances[msg.sender] = balances[msg.sender].add(amountBabz);

    bytes memory empty;
    //_checkDestination(address(this), msg.sender, amountBabz, empty);
    return amountBabz;
  }


  function transfer(address _from, address _to, uint256 _amountBabz, bytes _data) public onlyNutz {
    _transfer(_from, _to, _amountBabz, _data);
  }

  function transferFrom(address _sender, address _from, address _to, uint256 _amountBabz, bytes _data) public onlyNutz returns (bool) {
    require(_from != _to);
    require(_to != address(this));
    require(_amountBabz > 0);
    if (_from == powerAddr) {
      // 3rd party power up:
      // - first transfer NTZ to account of receiver
      // - then power up that amount of NTZ in the account of receiver
      balances[_sender] = balances[_sender].sub(_amountBabz);
      balances[_to] = balances[_to].add(_amountBabz);
      return _transfer(_to, _from, _amountBabz, _data);
    } else {
      // usual transfer
      allowed[_from][_sender] = allowed[_from][_sender].sub(_amountBabz);
      return _transfer(_from, _to, _amountBabz, _data);
    }
  }

  function sell(address _from, uint256 _amountBabz) public onlyNutz {
    uint256 effectiveFloor = floor();
    uint256 INFINITY = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    require(effectiveFloor != INFINITY);

    uint256 amountWei = _amountBabz.mul(1000000).div(effectiveFloor);  // 1,000,000 WEI, used as price factor
    // make sure power pool shrinks proportional to economy
    uint256 powerPoolSize = balances[powerAddr];
    if (powerPoolSize > 0) {
      uint256 powerShare = powerPoolSize.mul(_amountBabz).div(activeSupply);
      balances[powerAddr] = powerPoolSize.sub(powerShare);
    }
    activeSupply = activeSupply.sub(_amountBabz);
    balances[_from] = balances[_from].sub(_amountBabz);
    assert(amountWei <= this.balance);
    PullPayment(pullAddr).asyncSend.value(amountWei)(_from);
  }

  // this is called when NTZ are deposited into the power pool
  function powerUp(address _from, uint256 _amountBabz)  public onlyNutz {
    require(authorizedPower != 0);
    require(_amountBabz != 0);
    uint256 totalSupply = activeSupply.add(balances[powerAddr]).add(burnPool);
    require(totalSupply != 0);
    uint256 amountPow = _amountBabz.mul(authorizedPower).div(totalSupply);
    // check pow limits
    require(outstandingPower.add(amountPow) <= maxPower);
    outstandingPower = outstandingPower.add(amountPow);
    
    uint256 powBal = powBalance[_from].add(amountPow);
    require(powBal >= authorizedPower.div(10000)); // minShare = 10000
    powBalance[_from] = powBal;
    activeSupply = activeSupply.sub(_amountBabz);
    balances[_from] = balances[_from].sub(_amountBabz);
    balances[powerAddr] = balances[powerAddr].add(_amountBabz);
  }

}
