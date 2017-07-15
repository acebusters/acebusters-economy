pragma solidity ^0.4.11;

import "./SafeMath.sol";
import "./ERC20.sol";
import "./Power.sol";
import "./ERC223ReceivingContract.sol";

/**
 * Nutz implements a price floor and a price ceiling on the token being
 * sold. It is based of the zeppelin token contract. Nutz implements the
 * https://github.com/ethereum/EIPs/issues/20 interface.
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
  uint256 INFINITY = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
  uint256 MEGA_WEI = 1000000;   // 1 MEGA_WEI equals 1,000,000 WEI, used as price factor

  uint256 actSupply;
  // contract's ether balance, except all ether parked to be withdrawn
  uint256 public reserve;
  // balanceOf[powerAddr] returns power pool
  // balanceOf[address(this)] returns burn pool
  mapping(address => uint) balances;
  // "allowed[address(this)][x]" ether parked to be withdraw
  mapping (address => mapping (address => uint)) allowed;
  
  // the Token sale mechanism parameters:
  // ceiling is the number of NTZ returned for 1 ETH
  uint256 public ceiling;
  // floor is the number of NTZ needed, no receive 1 ETH back
  // we say that floor is lower than ceiling, if the number of NTZ needed to sell
  // to receive the same amount of ETH as used in purchase, is higher.
  uint256 public setFloor;
  address[] public admins;
  address public powerAddr;

  // returns balance
  function balanceOf(address _owner) constant returns (uint) {
    return balances[_owner];
  }

  function totalSupply() constant returns (uint256) {
    // active supply + power pool + burn pool
    return actSupply.add(balances[powerAddr]).add(balances[address(this)]);
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

  // returns either the setFloor, or if reserve does not suffice
  // for active supply, returns maxFloor
  function floor() constant returns (uint256) {
    if (reserve == 0) {
      return INFINITY;
    }
    uint256 maxFloor = actSupply.mul(MEGA_WEI).div(reserve);
    // return max of maxFloor or setFloor
    return maxFloor >= setFloor ? maxFloor : setFloor;
  }

  function Nutz(uint256 _downTime) {
    admins.length = 1;
    admins[0] = msg.sender;
    // initial purchase price
    ceiling = 0;
    // initial sale price
    setFloor = INFINITY;
    powerAddr = new Power(address(this), _downTime);
  }






  // ############################################
  // ########### INTERNAL FUNCTIONS #############
  // ############################################
  
  function _sellTokens(address _from, uint256 _amountBabz) internal returns (bool) {
    uint256 effectiveFloor = floor();
    assert(effectiveFloor != INFINITY);

    uint256 amountWei = _amountBabz.mul(MEGA_WEI).div(effectiveFloor);
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
    uint256 amountWei = allowed[address(this)][_sender];
    assert(0 < amountWei && amountWei <= this.balance);
    allowed[address(this)][_sender] = 0;
    assert(_to.send(amountWei));
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

    // erc223: Retrieve the size of the code on target address, this needs assembly .
    uint256 codeLength;
    assembly {
      codeLength := extcodesize(_to)
    }
    if(codeLength>0) {
      ERC223ReceivingContract receiver = ERC223ReceivingContract(_to);
      receiver.tokenFallback(_from, _amountBabz, data);
    }

    Transfer(_from, _to, _amountBabz);
    return true;
  }





  // ############################################
  // ########### ADMIN FUNCTIONS ################
  // ############################################

  modifier onlyAdmins() {
    for (uint256 i = 0; i < admins.length; i++) {
      if (msg.sender == admins[i]) {
        _;
      }
    }
  }

  function addAdmin(address _admin) onlyAdmins {
    for (uint256 i = 0; i < admins.length; i++) {
      assert(_admin != admins[i]);
    }
    assert(admins.length <= 10);
    admins[admins.length++] = _admin;
  }

  function removeAdmin(address _admin) onlyAdmins {
    uint256 pos = 1337;
    for (uint256 i = 0; i < admins.length; i++) {
      if (_admin == admins[i]) {
        pos = i;
      }
    }
    // if not last element, switch with last
    if (pos < admins.length - 1) {
      admins[pos] = admins[admins.length - 1];
    }
    // then cut off the tail
    admins.length--;
  }
  
  function moveCeiling(uint256 _newCeiling) onlyAdmins {
    assert(_newCeiling <= setFloor);
    ceiling = _newCeiling;
  }
  
  function moveFloor(uint256 _newFloor) onlyAdmins {
    assert(_newFloor >= ceiling);
    // moveFloor fails if the administrator tries to push the floor so low
    // that the sale mechanism is no longer able to buy back all tokens at
    // the floor price if those funds were to be withdrawn.
    if (_newFloor > 0) {
      uint256 newReserveNeeded = actSupply.mul(MEGA_WEI).div(_newFloor);
      assert(reserve >= newReserveNeeded);
    }
    setFloor = _newFloor;
  }

  function allocateEther(uint256 _amountWei, address _beneficiary) onlyAdmins {
    assert(_amountWei > 0);
    // allocateEther fails if allocating those funds would mean that the
    // sale mechanism is no longer able to buy back all tokens at the floor
    // price if those funds were to be withdrawn.
    uint256 leftReserve = reserve.sub(_amountWei);
    assert(leftReserve >= actSupply.mul(MEGA_WEI).div(setFloor));
    reserve = reserve.sub(_amountWei);
    allowed[address(this)][_beneficiary] = allowed[address(this)][_beneficiary].add(_amountWei);
  }

  function dilutePower(uint256 _amountBabz) onlyAdmins {
    uint256 burn = balances[address(this)];
    uint256 totalSupply = actSupply.add(balances[powerAddr]).add(burn);
    assert(Power(powerAddr).dilutePower(totalSupply, _amountBabz));
    balances[address(this)] = burn.add(_amountBabz);
  }

  function setMaxPower(uint256 _maxPower) onlyAdmins {
    Power(powerAddr).setMaxPower(_maxPower);
  }





  // ############################################
  // ########### PAYABLE FUNCTIONS ##############
  // ############################################

  function () payable {
    purchaseTokens();
  }
  
  function purchaseTokens() payable {
    assert(msg.value > 0);
    // disable purchases if ceiling set to 0
    assert(ceiling > 0);

    uint256 amountBabz = msg.value.mul(ceiling).div(MEGA_WEI);
    // avoid deposits that issue nothing
    // might happen with very large ceiling
    assert(amountBabz > 0);

    reserve = reserve.add(msg.value);
    // make sure power pool grows proportional to economy
    if (powerAddr != 0x0 && balances[powerAddr] > 0) {
      uint256 powerShare = balances[powerAddr].mul(amountBabz).div(actSupply.add(balances[address (this)]));
      balances[powerAddr] = balances[powerAddr].add(powerShare);
    }
    actSupply = actSupply.add(amountBabz);
    balances[msg.sender] = balances[msg.sender].add(amountBabz);
    // erc223: Retrieve the size of the code on target address, this needs assembly .
    uint256 codeLength;
    address to = msg.sender;
    assembly {
      codeLength := extcodesize(to)
    }
    if(codeLength > 0) {
      ERC223ReceivingContract receiver = ERC223ReceivingContract(to);
      bytes memory empty;
      receiver.tokenFallback(address(this), amountBabz, empty);
    }
    Purchase(msg.sender, amountBabz);
  }




  // ############################################
  // ########### PUBLIC FUNCTIONS ###############
  // ############################################
  
  function approve(address _spender, uint256 _amountBabz) {
    assert(_spender != address(this));
    assert(msg.sender != _spender);
    assert(_amountBabz != 0);
    allowed[msg.sender][_spender] = _amountBabz;
    Approval(msg.sender, _spender, _amountBabz);
  }

  function transfer(address _to, uint256 _amountBabz) returns (bool) {
    bytes memory empty;
    return transfer(_to, _amountBabz, empty);
  }

  function transData(address _to, uint256 _amountBabz, bytes _data) returns (bool) {
    return transfer(_to, _amountBabz, _data);
  }

  function transfer(address _to, uint256 _amountBabz, bytes _data) returns (bool) {
    assert(_amountBabz != 0);
    // sell tokens
    if (_to == address(this)) {
      return _sellTokens(msg.sender, _amountBabz);
    }
    return _transfer(msg.sender, _to, _amountBabz, _data);
  }

  function transferFrom(address _from, address _to, uint256 _amountBabz) returns (bool) {
    assert(_from != _to);
    // claim ether
    if (_from == address(this) && _amountBabz == 0) {
      _claimEther(msg.sender, _to);
      return true;
    }
    assert(_amountBabz > 0);
    // sell tokens
    if (_to == address(this)) {
      return _sellTokens(_from, _amountBabz);
    }
    allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_amountBabz);
    bytes memory empty;
    return _transfer(_from, _to, _amountBabz, empty);
  }

}