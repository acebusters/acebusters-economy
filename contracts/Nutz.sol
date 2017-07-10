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
  uint256 BABBAGE = 1000000;   // 1 BABBAGE equals 1,000,000 WEI, used as price factor

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
  uint256 public floor;
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
  
  function Nutz(uint256 _downTime) {
    admins.length = 1;
    admins[0] = msg.sender;
    // initial purchase price
    ceiling = 0;
    // initial sale price
    floor = INFINITY;
    powerAddr = new Power(address(this), _downTime);
  }






  // ############################################
  // ########### INTERNAL FUNCTIONS #############
  // ############################################
  
  function _sellTokens(address _from, uint256 _amountBabz) internal returns (bool) {
    if (floor == INFINITY) {
      throw;
    }

    uint256 amountWei = _amountBabz.mul(BABBAGE).div(floor);
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
  function _claimEther(address _sender, address _to) internal returns (bool) {
    uint256 amountEth = allowed[address(this)][_sender];
    if (amountEth == 0 || this.balance < amountEth) {
      throw;
    }
    allowed[address(this)][_sender] = 0;
    if (!_to.send(amountEth)) {
      throw;
    }
    return true;
  }

  function _transfer(address _from, address _to, uint256 _amountNtz, bytes _data) internal returns (bool) {
    bytes memory data;
    // todo: copy data
    // power up
    if (_to == powerAddr) {
      data = new bytes(32);
      uint ts = totalSupply();
      assembly { mstore(add(data, 32), ts) }
      actSupply = actSupply.sub(_amountNtz);
    }
    // power down
    if (_from == powerAddr) {
      actSupply = actSupply.add(_amountNtz);
    }

    balances[_from] = balances[_from].sub(_amountNtz);
    balances[_to] = balances[_to].add(_amountNtz);

    // erc223: Retrieve the size of the code on target address, this needs assembly .
    uint256 codeLength;
    assembly {
      codeLength := extcodesize(_to)
    }
    if(codeLength>0) {
      ERC223ReceivingContract receiver = ERC223ReceivingContract(_to);
      receiver.tokenFallback(_from, _amountNtz, data);
    }

    Transfer(_from, _to, _amountNtz);
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
      if (_admin == admins[i]) {
        throw;
      }
    }
    if (admins.length > 10) {
      throw;
    }
    uint256 pos = admins.length++;
    admins[pos] = _admin;
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
    if (_newCeiling > floor) {
        throw;
    }
    ceiling = _newCeiling;
  }
  
  function moveFloor(uint256 _newFloor) onlyAdmins {
    if (_newFloor < ceiling) {
        throw;
    }
    // moveFloor fails if the administrator tries to push the floor so low
    // that the sale mechanism is no longer able to buy back all tokens at
    // the floor price if those funds were to be withdrawn.
    if (_newFloor > 0) {
      uint256 newReserveNeeded = actSupply.mul(BABBAGE).div(_newFloor);
      if (reserve < newReserveNeeded) {
          throw;
      }
    }
    floor = _newFloor;
  }

  function allocateEther(uint256 _amountWei, address _beneficiary) onlyAdmins {
    if (_amountWei == 0) {
        return;
    }
    // allocateEther fails if allocating those funds would mean that the
    // sale mechanism is no longer able to buy back all tokens at the floor
    // price if those funds were to be withdrawn.
    uint256 leftReserve = reserve.sub(_amountWei);
    if (leftReserve < actSupply.mul(BABBAGE).div(floor)) {
        throw;
    }
    reserve = reserve.sub(_amountWei);
    allowed[address(this)][_beneficiary] = allowed[address(this)][_beneficiary].add(_amountWei);
  }

  function dilutePower(uint256 _amountNtz) onlyAdmins {
    uint256 burn = balances[address(this)];
    uint256 totalSupply = actSupply.add(balances[powerAddr]).add(burn);
    if (!Power(powerAddr).dilutePower(totalSupply, _amountNtz)) {
      throw;
    }
    balances[address(this)] = burn.add(_amountNtz);
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
    if (msg.value == 0) {
      return;
    }
    // disable purchases if ceiling set to 0
    if (ceiling == 0) {
      throw;
    }
    uint256 amountToken = msg.value.mul(ceiling).div(BABBAGE);
    // avoid deposits that issue nothing
    // might happen with very large ceiling
    if (amountToken == 0) {
      throw;
    }
    reserve = reserve.add(msg.value);
    // make sure power pool grows proportional to economy
    if (powerAddr != 0x0 && balances[powerAddr] > 0) {
      uint256 powerShare = balances[powerAddr].mul(amountToken).div(actSupply);
      balances[powerAddr] = balances[powerAddr].add(powerShare);
    }
    actSupply = actSupply.add(amountToken);
    balances[msg.sender] = balances[msg.sender].add(amountToken);
    Purchase(msg.sender, amountToken);
  }




  // ############################################
  // ########### PUBLIC FUNCTIONS ###############
  // ############################################
  
  function approve(address _spender, uint256 _amountNtz) {
    if (_spender == address(this) || msg.sender == _spender || _amountNtz == 0) {
      throw;
    }
    allowed[msg.sender][_spender] = _amountNtz;
    Approval(msg.sender, _spender, _amountNtz);
  }

  function transfer(address _to, uint256 _amountNtz) returns (bool) {
    bytes memory empty;
    return transfer(_to, _amountNtz, empty);
  }

  function transData(address _to, uint256 _amountNtz, bytes _data) returns (bool) {
    return transfer(_to, _amountNtz, _data);
  }

  function transfer(address _to, uint256 _amountNtz, bytes _data) returns (bool) {
    if (_amountNtz == 0) {
      throw;
    }
    // sell tokens
    if (_to == address(this)) {
      return _sellTokens(msg.sender, _amountNtz);
    }
    return _transfer(msg.sender, _to, _amountNtz, _data);
  }

  function transferFrom(address _from, address _to, uint256 _amountNtz) returns (bool) {
    if (_from == _to) {
      throw;
    }
    // claim ether
    if (_from == address(this) && _amountNtz == 0) {
      return _claimEther(msg.sender, _to);
    }
    if (_amountNtz == 0) {
      throw;
    }
    // sell tokens
    if (_to == address(this)) {
      return _sellTokens(_from, _amountNtz);
    }
    allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_amountNtz);
    bytes memory empty;
    return _transfer(_from, _to, _amountNtz, empty);
  }

}
