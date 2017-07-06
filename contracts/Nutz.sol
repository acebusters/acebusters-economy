pragma solidity ^0.4.11;

import "./SafeMath.sol";
import "./ERC20.sol";
import "./Power.sol";

/**
 * Nutz implements a price floor and a price ceiling on the token being
 * sold. It is based of the zeppelin token contract. Nutz implements the
 * https://github.com/ethereum/EIPs/issues/20 interface.
 */
contract Nutz is ERC20 {
  using SafeMath for uint;

  event Purchase(address indexed purchaser, uint value);
  event Sell(address indexed seller, uint value);
  
  string public name = "Acebusters Nutz";
  // acebusters units:
  // 10^12 - Nutz   (NTZ)
  // 10^9 - Jonyz
  // 10^6 - Helcz
  // 10^3 - Pascalz
  // 10^0 - Babz
  string public symbol = "NTZ";
  uint public decimals = 12;
  uint INFINITY = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
  uint BABBAGE = 1000000;   // 1 BABBAGE equals 1,000,000 WEI, used as price factor

  // contract's ether balance, except all ether parked to be withdrawn
  uint public reserve;
  // balanceOf[powerAddr] returns power pool
  // balanceOf[address(this)] returns burn pool
  mapping(address => uint) balances;
  // "allowed[address(this)][x]" ether parked to be withdraw
  mapping (address => mapping (address => uint)) allowed;
  
  // the Token sale mechanism parameters:
  // ceiling is the number of NTZ returned for 1 ETH
  uint public ceiling;
  // floor is the number of NTZ needed, no receive 1 ETH back
  // we say that floor is lower than ceiling, if the number of NTZ needed to sell
  // to receive the same amount of ETH as used in purchase, is higher.
  uint public floor;
  address public admin;
  address public powerAddr;

  // returns balance
  function balanceOf(address _owner) constant returns (uint) {
    return balances[_owner];
  }

  function totalSupply() constant returns (uint256) {
    // active supply + power pool + burn pool
    return activeSupply.add(balances[powerAddr]).add(balances[address(this)]);
  }

  // return remaining allowance
  // if calling return allowed[address(this)][_spender];
  // returns balance of ether parked to be withdrawn
  function allowance(address _owner, address _spender) constant returns (uint) {
    return allowed[_owner][_spender];
  }
  
  function Nutz(uint _downTime) {
      admin = msg.sender;
      // initial purchase price
      ceiling = 0;
      // initial sale price
      floor = INFINITY;
      powerAddr = new Power(address(this), _downTime);
  }





  // ############################################
  // ########### INTERNAL FUNCTIONS #############
  // ############################################
  
  function sellTokens(uint _amountToken) internal returns (bool) {
    if (floor == INFINITY) {
      throw;
    }

    uint amountEther = _amountToken.mul(BABBAGE).div(floor);
    // make sure power pool shrinks proportional to economy
    if (powerAddr != 0x0 && balances[powerAddr] > 0) {
      uint powerShare = balances[powerAddr].mul(_amountToken).div(activeSupply);
      balances[powerAddr] = balances[powerAddr].sub(powerShare);
    }
    activeSupply = activeSupply.sub(_amountToken);
    balances[msg.sender] = balances[msg.sender].sub(_amountToken);
    reserve = reserve.sub(amountEther);
    allowed[address(this)][msg.sender] = allowed[address(this)][msg.sender].add(amountEther);
    Sell(msg.sender,  _amountToken);
    return true;
  }

  // withdraw accumulated balance, called by seller or beneficiary
  function claimEther(address _sender, address _to) internal returns (bool) {
    uint amountEth = allowed[address(this)][_sender];
    if (amountEth == 0 || this.balance < amountEth) {
      throw;
    }
    allowed[address(this)][_sender] = 0;
    if (!_to.send(amountEth)) {
      throw;
    }
    return true;
  }

  function _transfer(address _from, address _to, uint _amountNtz) internal returns (bool) {
    // power up
    if (_to == powerAddr) {
      _powerUp(_from, _amountNtz);
      activeSupply = activeSupply.sub(_amountNtz);
    }
    if (_from == powerAddr) {
      activeSupply = activeSupply.add(_amountNtz);
    }
    balances[_from] = balances[_from].sub(_amountNtz);
    balances[_to] = balances[_to].add(_amountNtz);
    Transfer(_from, _to, _amountNtz);
    return true;
  }

  function _powerUp(address _from, uint _amountNtz) internal {
    var power = Power(powerAddr);
    uint totalSupply = activeSupply.add(balances[powerAddr]).add(balances[address(this)]);
    if (!power.up(_from, _amountNtz, totalSupply)) {
      throw;
    }
  }


  // ############################################
  // ########### ADMIN FUNCTIONS ################
  // ############################################

  modifier onlyAdmin() {
    if (msg.sender == admin) {
      _;
    }
  }
  
  function moveCeiling(uint _newCeiling) onlyAdmin {
    if (_newCeiling > floor) {
        throw;
    }
    ceiling = _newCeiling;
  }
  
  function moveFloor(uint _newFloor) onlyAdmin {
    if (_newFloor < ceiling) {
        throw;
    }
    // moveFloor fails if the administrator tries to push the floor so low
    // that the sale mechanism is no longer able to buy back all tokens at
    // the floor price if those funds were to be withdrawn.
    if (_newFloor > 0) {
      uint newReserveNeeded = activeSupply.mul(BABBAGE).div(_newFloor);
      if (reserve < newReserveNeeded) {
          throw;
      }
    }
    floor = _newFloor;
  }

  function allocateEther(uint _amountEther, address _beneficiary) onlyAdmin {
    if (_amountEther == 0) {
        return;
    }
    // allocateEther fails if allocating those funds would mean that the
    // sale mechanism is no longer able to buy back all tokens at the floor
    // price if those funds were to be withdrawn.
    uint leftReserve = reserve.sub(_amountEther);
    if (leftReserve < activeSupply.mul(BABBAGE).div(floor)) {
        throw;
    }
    reserve = reserve.sub(_amountEther);
    allowed[address(this)][_beneficiary] = allowed[address(this)][_beneficiary].add(_amountEther);
  }

  function dilutePower(uint _amountNtz) onlyAdmin {
    var power = Power(powerAddr);
    uint totalSupply = activeSupply.add(balances[powerAddr]).add(balances[address(this)]);
    if (!power.burn(totalSupply, _amountNtz)) {
      throw;
    }
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
    uint amountToken = msg.value.mul(ceiling).div(BABBAGE);
    // avoid deposits that issue nothing
    // might happen with very large ceiling
    if (amountToken == 0) {
      throw;
    }
    reserve = reserve.add(msg.value);
    // make sure power pool grows proportional to economy
    if (powerAddr != 0x0 && balances[powerAddr] > 0) {
      uint powerShare = balances[powerAddr].mul(amountToken).div(activeSupply);
      balances[powerAddr] = balances[powerAddr].add(powerShare);
    }
    activeSupply = activeSupply.add(amountToken);
    balances[msg.sender] = balances[msg.sender].add(amountToken);
    Purchase(msg.sender, amountToken);
  }




  // ############################################
  // ########### PUBLIC FUNCTIONS ###############
  // ############################################
  
  function approve(address _spender, uint _amountNtz) {
    if (_spender == address(this) || msg.sender == _spender || _amountNtz == 0) {
      throw;
    }
    allowed[msg.sender][_spender] = _amountNtz;
    Approval(msg.sender, _spender, _amountNtz);
  }

  function transfer(address _to, uint _amountNtz) returns (bool) {
    if (_amountNtz == 0) {
      return false;
    }
    // sell tokens
    if (_to == address(this)) {
      return sellTokens(_amountNtz);
    }
    return _transfer(msg.sender, _to, _amountNtz);
  }

  function transferFrom(address _from, address _to, uint _amountNtz) returns (bool) {
    if (_from == _to || _to == address(this) || _to == powerAddr) {
      throw;
    }
    // claim ether
    if (_from == address(this) && _amountNtz == 0) {
      return claimEther(msg.sender, _to);
    }
    if (_amountNtz == 0) {
      return false;
    }
    allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_amountNtz);
    return _transfer(_from, _to, _amountNtz);
  }

}
