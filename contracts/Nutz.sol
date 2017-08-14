pragma solidity 0.4.11;

import "./SafeMath.sol";
import "./ERC20.sol";
import "./Power.sol";
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
  // contract's ether balance, except all ether parked to be withdrawn
  uint256 public reserve;
  // burn pool - inactive supply
  uint256 public burnPool;
  // balanceOf[powerAddr] size of power pool
  // balance of active holders
  mapping(address => uint) internal balances;
  // "allowed[address(this)][x]" ether parked to be withdraw
  // allowances according to ERC20
  mapping (address => mapping (address => uint)) internal allowed;
  
  // the Token sale mechanism parameters:
  // ceiling is the number of NTZ received for purchase with 1 ETH
  uint256 public ceiling;
  // floor is the number of NTZ needed, to receive 1 ETH in sell
  uint256 salePrice;
  address[] public admins;
  address public powerAddr;

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
    if (reserve == 0) {
      return INFINITY;
    }
    uint256 maxFloor = actSupply.mul(1000000).div(reserve); // 1,000,000 WEI, used as price factor
    // return max of maxFloor or salePrice
    return maxFloor >= salePrice ? maxFloor : salePrice;
  }

  function powerPool() constant returns (uint256) {
    return balances[powerAddr];
  }

  function Nutz(uint256 _downTime) {
    admins.length = 1;
    admins[0] = msg.sender;
    // initial purchase price
    ceiling = 0;
    // initial sale price
    salePrice = INFINITY;
    onlyContractHolders = true;
    powerAddr = new Power(address(this), _downTime);
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

    reserve = reserve.add(msg.value);
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
    reserve = reserve.sub(amountWei);
    allowed[address(this)][_from] = allowed[address(this)][_from].add(amountWei);
    Sell(_from,  _amountBabz);
    return true;
  }

  // withdraw accumulated balance, called by seller or beneficiary
  function _claimEther(address _sender, address _to) internal {
    require(salePrice < INFINITY);
    uint256 amountWei = allowed[address(this)][_sender];
    require(amountWei > 0);
    assert(amountWei <= this.balance);
    allowed[address(this)][_sender] = 0;
    assert(_to.send(amountWei));
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

  function _transfer(address _from, address _to, uint256 _amountBabz, bytes _data) internal returns (bool) {
    bytes memory data;
    // power up
    if (_to == powerAddr) {
      data = new bytes(32);
      uint ts = totalSupply();
      assembly { mstore(add(data, 32), ts) }
      actSupply = actSupply.sub(_amountBabz);
    } else {
      data = _data;
    }
    // power down
    if (_from == powerAddr) {
      actSupply = actSupply.add(_amountBabz);
    }

    balances[_from] = balances[_from].sub(_amountBabz);
    balances[_to] = balances[_to].add(_amountBabz);

    _checkDestination(_from, _to, _amountBabz, data);

    Transfer(_from, _to, _amountBabz);
    return true;
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
      require(reserve >= actSupply.mul(1000000).div(_newSalePrice)); // 1,000,000 WEI, used as price factor
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
    uint256 leftReserve = reserve.sub(_amountWei);
    require(leftReserve >= actSupply.mul(1000000).div(salePrice)); // 1,000,000 WEI, used as price factor
    reserve = leftReserve;
    allowed[address(this)][_beneficiary] = allowed[address(this)][_beneficiary].add(_amountWei);
  }

  function dilutePower(uint256 _amountBabz) onlyAdmins {
    assert(Power(powerAddr).dilutePower(totalSupply(), _amountBabz));
    burnPool = burnPool.add(_amountBabz);
  }

  function slashPower(address _holder, uint256 _value, bytes32 _data) onlyAdmins {
    // get the previously outstanding power of which _value was slashed
    uint256 outstandingPower = Power(powerAddr).slashPower(_holder, _value, _data);
    uint256 powerPool = balances[powerAddr];
    uint256 slashingBabz = _value.mul(powerPool).div(outstandingPower);
    balances[powerAddr] = powerPool.sub(slashingBabz);
  }

  function slashDownRequest(uint256 _pos, address _holder, uint256 _value, bytes32 _data) onlyAdmins {
    // get the previously outstanding power of which _value was slashed
    uint256 outstandingPower = Power(powerAddr).slashDownRequest(_pos, _holder, _value, _data);
    uint256 powerPool = balances[powerAddr];
    uint256 slashingBabz = _value.mul(powerPool).div(outstandingPower);
    balances[powerAddr] = powerPool.sub(slashingBabz);
  }

  function setMaxPower(uint256 _maxPower) onlyAdmins {
    Power(powerAddr).setMaxPower(_maxPower);
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
    // claim ether
    if (_from == address(this) && _amountBabz == 0) {
      _claimEther(msg.sender, _to);
      return true;
    }
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
