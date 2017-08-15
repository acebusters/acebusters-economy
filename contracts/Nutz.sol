pragma solidity 0.4.11;

import "./SafeMath.sol";
import "./ERC20.sol";
import "./Power.sol";
import "./PullPayment.sol";
import "./ERC223ReceivingContract.sol";

/**
 * Nutz implements a price floor and a price ceiling on the token being
 * sold. It is based of the zeppelin token contract.
 */
contract Nutz is ERC20 {
  using SafeMath for uint;

  event Purchase(address indexed purchaser, uint256 value);
  event Sell(address indexed seller, uint256 value);
  
  string public name = "Acebusters Nutz";
  // acebusters units:
  // 10^12 - Nutz   (NTZ)
  // 10^9 - Jonyz
  // 10^6 - Helcz
  // 10^3 - Pascalz
  // 10^0 - Babz
  string public symbol = "NTZ";
  uint256 public decimals = 12;
  uint256 internal INFINITY = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
  

  // active supply
  uint256 internal actSupply;
  // burn pool - inactive supply
  uint256 public burnPool;
  // balanceOf[powerAddr] size of power pool
  // balance of active holders
  mapping(address => uint) internal balances;
  // "allowed[address(this)][x]" ether parked to be withdraw
  // allowances according to ERC20
  mapping (address => mapping (address => uint)) internal allowed;

  // all power balances
  mapping (address => uint256) public powBalance;

  function setPowBalance(address _owner, uint256 _value) {
    require(msg.sender == powerAddr);
    powBalance[_owner] = _value;
  }

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


  
  // the Token sale mechanism parameters:
  // ceiling is the number of NTZ received for purchase with 1 ETH
  uint256 public ceiling;
  // floor is the number of NTZ needed, to receive 1 ETH in sell
  uint256 salePrice;
  address[] public admins;
  address public powerAddr;
  address public pullAddr;

  // this flag allows or denies deposits of NTZ into non-contract accounts
  bool public onlyContractHolders = true;

  // returns balances of active holders
  function balanceOf(address _owner) constant returns (uint) {
    if (_owner == powerAddr) {
      // do not return balance of power pool / use powerPool() istead
      return 0;
    } else {
      // only return balance of active holders
      return balances[_owner];
    }
  }

  function totalSupply() constant returns (uint256) {
    // active supply + power pool + burn pool
    return actSupply.add(balances[powerAddr]).add(burnPool);
  }

  function activeSupply() constant returns (uint256) {
    return actSupply;
  }

  // return remaining allowance
  // if calling return allowed[address(this)][_spender];
  // returns balance of ether parked to be withdrawn
  function allowance(address _owner, address _spender) constant returns (uint) {
    return allowed[_owner][_spender];
  }

  // returns either the salePrice, or if reserve does not suffice
  // for active supply, returns maxFloor
  function floor() constant returns (uint256) {
    if (this.balance == 0) {
      return INFINITY;
    }
    uint256 maxFloor = actSupply.mul(1000000).div(this.balance); // 1,000,000 WEI, used as price factor
    // return max of maxFloor or salePrice
    return maxFloor >= salePrice ? maxFloor : salePrice;
  }

  function powerPool() constant returns (uint256) {
    return balances[powerAddr];
  }

  function Nutz(uint256 _downtime) {
    admins.length = 1;
    admins[0] = msg.sender;
    // initial purchase price
    ceiling = 0;
    // initial sale price
    salePrice = INFINITY;
    onlyContractHolders = true;
    powerAddr = new Power();
    downtime = _downtime;
    pullAddr = new PullPayment();
  }


  // ############################################
  // ########### INTERNAL FUNCTIONS #############
  // ############################################

  function _purchase() internal {
    require(msg.value > 0);
    // disable purchases if ceiling set to 0
    require(ceiling > 0);

    uint256 amountBabz = msg.value.mul(ceiling).div(1000000); // 1,000,000 WEI, used as price factor
    // avoid deposits that issue nothing
    // might happen with very high purchase price
    require(amountBabz > 0);

    // make sure power pool grows proportional to economy
    if (powerAddr != 0x0 && balances[powerAddr] > 0) {
      uint256 powerShare = balances[powerAddr].mul(amountBabz).div(actSupply.add(burnPool));
      balances[powerAddr] = balances[powerAddr].add(powerShare);
    }
    actSupply = actSupply.add(amountBabz);
    balances[msg.sender] = balances[msg.sender].add(amountBabz);

    bytes memory empty;
    _checkDestination(address(this), msg.sender, amountBabz, empty);

    Purchase(msg.sender, amountBabz);
  }
  
  function _sell(address _from, uint256 _amountBabz) internal returns (bool) {
    uint256 effectiveFloor = floor();
    require(effectiveFloor != INFINITY);

    uint256 amountWei = _amountBabz.mul(1000000).div(effectiveFloor);  // 1,000,000 WEI, used as price factor
    // make sure power pool shrinks proportional to economy
    uint256 powerPool = balances[powerAddr];
    if (powerPool > 0) {
      uint256 powerShare = powerPool.mul(_amountBabz).div(actSupply);
      balances[powerAddr] = powerPool.sub(powerShare);
    }
    actSupply = actSupply.sub(_amountBabz);
    balances[_from] = balances[_from].sub(_amountBabz);
    assert(amountWei <= this.balance);
    PullPayment(pullAddr).asyncSend.value(amountWei)(_from);
    Sell(_from,  _amountBabz);
    return true;
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


  // this is called when NTZ are deposited into the power pool
  function _powerUp(address _from, uint256 _amountBabz) internal {
    require(authorizedPower != 0);
    require(_amountBabz != 0);
    require(totalSupply() != 0);
    uint256 amountPow = _amountBabz.mul(authorizedPower).div(totalSupply());
    // check pow limits
    require(outstandingPower.add(amountPow) <= maxPower);
    outstandingPower = outstandingPower.add(amountPow);
    
    uint256 powBal = powBalance[_from].add(amountPow);
    require(powBal >= authorizedPower.div(10000)); // minShare = 10000
    powBalance[_from] = powBal;
  }

  function _transfer(address _from, address _to, uint256 _amountBabz, bytes _data) internal returns (bool) {
    // power up
    if (_to == powerAddr) {
      _powerUp(_from, _amountBabz);
      actSupply = actSupply.sub(_amountBabz);
      balances[_from] = balances[_from].sub(_amountBabz);
      balances[_to] = balances[_to].add(_amountBabz);
      Transfer(_from, _to, _amountBabz);
      return true;
    }
    // power down
    if (_from == powerAddr) {
      actSupply = actSupply.add(_amountBabz);
    }

    balances[_from] = balances[_from].sub(_amountBabz);
    balances[_to] = balances[_to].add(_amountBabz);

    _checkDestination(_from, _to, _amountBabz, _data);

    Transfer(_from, _to, _amountBabz);
    return true;
  }





  // ############################################
  // ########### POWER   FUNCTIONS  #############
  // ############################################


  function setOutstandingPower(uint256 _value) {
    require(msg.sender == powerAddr);
    outstandingPower = _value;
  }

  function setAuthorizedPower(uint256 _value) {
    require(msg.sender == powerAddr);
    authorizedPower = _value;
  }

  function createDownRequest(address _owner, uint256 _amountPower, uint256 _time) {
    require(msg.sender == powerAddr);
    uint256 pos = downs.length++;
    downs[pos] = DownRequest(_owner, _amountPower, _amountPower, _time);
  }

  // executes a powerdown request
  function downTick(uint256 _pos, uint256 _now) {
    require(msg.sender == powerAddr);
    uint256 amountPow = vestedDown(_pos, _now);
    DownRequest storage req = downs[_pos];

    // prevent power down in tiny steps
    uint256 minStep = req.total.div(10);
    require(req.left <= minStep || minStep <= amountPow);

    // calculate token amount representing share of power
    uint256 amountBabz = amountPow.mul(totalSupply()).div(authorizedPower);
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
  // ########### ADMIN FUNCTIONS ################
  // ############################################

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

  function addAdmin(address _admin) onlyAdmins {
    for (uint256 i = 0; i < admins.length; i++) {
      require(_admin != admins[i]);
    }
    require(admins.length < 10);
    admins[admins.length++] = _admin;
  }

  function removeAdmin(address _admin) onlyAdmins {
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
  
  function moveCeiling(uint256 _newCeiling) onlyAdmins {
    require(_newCeiling <= salePrice);
    ceiling = _newCeiling;
  }
  
  function moveFloor(uint256 _newSalePrice) onlyAdmins {
    require(_newSalePrice >= ceiling);
    // moveFloor fails if the administrator tries to push the floor so low
    // that the sale mechanism is no longer able to buy back all tokens at
    // the floor price if those funds were to be withdrawn.
    if (_newSalePrice < INFINITY) {
      require(this.balance >= actSupply.mul(1000000).div(_newSalePrice)); // 1,000,000 WEI, used as price factor
    }
    salePrice = _newSalePrice;
  }

  function setOnlyContractHolders(bool _onlyContractHolders) onlyAdmins {
    onlyContractHolders = _onlyContractHolders;
  }

  function allocateEther(uint256 _amountWei, address _beneficiary) onlyAdmins {
    require(_amountWei > 0);
    // allocateEther fails if allocating those funds would mean that the
    // sale mechanism is no longer able to buy back all tokens at the floor
    // price if those funds were to be withdrawn.
    require(this.balance.sub(_amountWei) >= actSupply.mul(1000000).div(salePrice)); // 1,000,000 WEI, used as price factor
    PullPayment(pullAddr).asyncSend.value(_amountWei)(_beneficiary);
  }

  // this is called when NTZ are deposited into the burn pool
  function dilutePower(uint256 _amountBabz) onlyAdmins {
    if (authorizedPower == 0) {
      // during the first capital increase, set some big number as authorized shares
      authorizedPower = totalSupply().add(_amountBabz);
    } else {
      // in later increases, expand authorized shares at same rate like economy
      authorizedPower = authorizedPower.mul(totalSupply().add(_amountBabz)).div(totalSupply());
    }
    burnPool = burnPool.add(_amountBabz);
  }

  function slashPower(address _holder, uint256 _value, bytes32 _data) onlyAdmins {
    // get the previously outstanding power of which _value was slashed

    powBalance[_holder] = powBalance[_holder].sub(_value);
    uint256 previouslyOutstanding = outstandingPower;
    outstandingPower = outstandingPower.sub(_value);

    Power(powerAddr).slashPower(_holder, _value, _data);

    uint256 powerPool = balances[powerAddr];
    uint256 slashingBabz = _value.mul(powerPool).div(previouslyOutstanding);
    balances[powerAddr] = powerPool.sub(slashingBabz);
  }

  function slashDownRequest(uint256 _pos, address _holder, uint256 _value, bytes32 _data) onlyAdmins {
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


  function setMaxPower(uint256 _maxPower) onlyAdmins {
    require(outstandingPower <= _maxPower && _maxPower < authorizedPower);
    maxPower = _maxPower;
  }



  // ############################################
  // ########### PUBLIC FUNCTIONS ###############
  // ############################################


  function () payable {
    _purchase();
  }
  
  function approve(address _spender, uint256 _amountBabz) public {
    require(_spender != address(this));
    require(msg.sender != _spender);
    require(_amountBabz > 0);
    allowed[msg.sender][_spender] = _amountBabz;
    Approval(msg.sender, _spender, _amountBabz);
  }

  function transfer(address _to, uint256 _amountBabz, bytes _data) public returns (bool) {
    require(_amountBabz != 0);
    // sell tokens
    if (_to == address(this)) {
      return _sell(msg.sender, _amountBabz);
    }
    return _transfer(msg.sender, _to, _amountBabz, _data);
  }

  function transferFrom(address _from, address _to, uint256 _amountBabz, bytes _data) public returns (bool) {
    require(_from != _to);
    require(_to != address(this));
    require(_amountBabz > 0);
    if (_from == powerAddr) {
      // 3rd party power up:
      // - first transfer NTZ to account of receiver
      // - then power up that amount of NTZ in the account of receiver
      balances[msg.sender] = balances[msg.sender].sub(_amountBabz);
      balances[_to] = balances[_to].add(_amountBabz);
      return _transfer(_to, _from, _amountBabz, _data);
    } else {
      // usual transfer
      allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_amountBabz);
      return _transfer(_from, _to, _amountBabz, _data);
    }
  }





  // ############################################
  // ######## PUB. FUNCTION ALIASES #############
  // ############################################

  function purchase() public payable {
    _purchase();
  }

  function transfer(address _to, uint256 _amountBabz) public returns (bool) {
    bytes memory empty;
    return transfer(_to, _amountBabz, empty);
  }

  function transData(address _to, uint256 _amountBabz, bytes _data) public returns (bool) {
    return transfer(_to, _amountBabz, _data);
  }

  function transferFrom(address _from, address _to, uint256 _amountBabz) public returns (bool) {
    bytes memory empty;
    return transferFrom(_from, _to, _amountBabz, empty);
  }

  function sell(uint256 _value) public {
    _sell(msg.sender, _value);
  }

  function powerUp(uint256 _value) public {
    bytes memory empty;
    _transfer(msg.sender, powerAddr, _value, empty);
  }

}
