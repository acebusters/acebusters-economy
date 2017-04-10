pragma solidity ^0.4.8;

import "./SafeMath.sol";
/**
 * SafeToken implements a price floor and a price ceiling on the token being
 * sold. It is based of the zeppelin token contract. SafeToken implements the
 * https://github.com/ethereum/EIPs/issues/20 interface.
 */
contract SafeToken is SafeMath {

  event Transfer(address indexed from, address indexed to, uint value);
  event Approval(address indexed owner, address indexed spender, uint value);
  event Purchase(address indexed purchaser, uint value);
  event Sell(address indexed seller, uint value);
  
  string public name = "SafeToken";
  string public symbol = "VST";
  uint public decimals = 15;
  uint infinity = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

  // total supply of tokens
  uint public totalSupply;
  // contract's ether balance, except all ether which
  // has been parked to be withdrawn in "allowed[address(this)]"
  uint public totalReserve;
  mapping(address => uint) balances;
  mapping (address => mapping (address => uint)) allowed;
  
  // the Token sale mechanism parameters:
  uint public ceiling;
  uint public floor;
  address public admin;
  address public beneficiary;

  // returns balance
  function balanceOf(address _owner) constant returns (uint) {
    return balances[_owner];
  }

  // return remaining allowance
  function allowance(address _owner, address _spender) constant returns (uint) {
    return allowed[_owner][_spender];
  }

  // returns balance of ether parked to be withdrawn
  function allocatedTo(address _owner) constant returns (uint) {
    return allowed[address(this)][_owner];
  }
  
  function SafeToken(address _beneficiary) {
      admin = msg.sender;
      // initial price at 1000 Wei / token
      ceiling = 1000;
      // initial floor at 1000 Wei / token
      floor = 1000;
      beneficiary = _beneficiary;
  }

  modifier onlyAdmin() {
    if (msg.sender == admin) {
      _;
    }
  }
  
  modifier onlyBeneficiary() {
    if (msg.sender == beneficiary) {
      _;
    }
  }
  
  function changeAdmin(address _newAdmin) onlyAdmin {
    if (_newAdmin == msg.sender || _newAdmin == 0x0) {
        throw;
    }
    admin = _newAdmin;
  }
  
  function moveCeiling(uint _newCeiling) onlyAdmin {
    if (_newCeiling < floor) {
        throw;
    }
    ceiling = _newCeiling;
  }
  
  function moveFloor(uint _newFloor) onlyAdmin {
    if (_newFloor > ceiling) {
        throw;
    }
    // moveFloor fails if the administrator tries to push the floor so low
    // that the sale mechanism is no longer able to buy back all tokens at
    // the floor price if those funds were to be withdrawn.
    uint newReserveNeeded = safeMul(totalSupply, _newFloor);
    if (totalReserve < newReserveNeeded) {
        throw;
    }
    floor = _newFloor;
  }
  
  function allocateEther(uint _amountEther) onlyAdmin {
    if (_amountEther == 0) {
        return;
    }
    // allocateEther fails if allocating those funds would mean that the
    // sale mechanism is no longer able to buy back all tokens at the floor
    // price if those funds were to be withdrawn.
    uint leftReserve = safeSub(totalReserve, _amountEther);
    if (leftReserve < safeMul(totalSupply, floor)) {
        throw;
    }
    totalReserve = safeSub(totalReserve, _amountEther);
    allowed[address(this)][beneficiary] = safeAdd(allowed[address(this)][beneficiary], _amountEther);
  }
  
  function changeBeneficiary(address _newBeneficiary) onlyBeneficiary {
    if (_newBeneficiary == msg.sender || _newBeneficiary == 0x0) {
        throw;
    }
    beneficiary = _newBeneficiary;
  }
  
  function () payable {
    purchaseTokens();
  }
  
  function purchaseTokens() payable {
    if (msg.value == 0) {
      return;
    }
    // disable purchases if ceiling set to infinity
    if (ceiling == infinity) {
      throw;
    }
    uint amountToken = safeDiv(msg.value, ceiling);
    // avoid deposits that issue nothing
    // might happen with very large ceiling
    if (amountToken == 0) {
      throw;
    }
    totalReserve = safeAdd(totalReserve, msg.value);
    totalSupply = safeAdd(totalSupply, amountToken);
    balances[msg.sender] = safeAdd(balances[msg.sender], amountToken);
    Purchase(msg.sender, amountToken);
  }
  
  function sellTokens(uint _amountToken) {
    if (floor == 0) {
      throw;
    }
    uint amountEther = safeMul(_amountToken, floor);
    totalSupply = safeSub(totalSupply, _amountToken);
    balances[msg.sender] = safeSub(balances[msg.sender], _amountToken);
    totalReserve = safeSub(totalReserve, amountEther);
    allowed[address(this)][msg.sender] = safeAdd(allowed[address(this)][msg.sender], amountEther);
    Sell(msg.sender,  _amountToken);
  }
  
  // withdraw accumulated balance, called by seller or beneficiary
  function claimEther() {
    if (allowed[address(this)][msg.sender] == 0) {
      return;
    }
    if (this.balance < allowed[address(this)][msg.sender]) {
      throw;
    }
    allowed[address(this)][msg.sender] = 0;
    if (!msg.sender.send(allowed[address(this)][msg.sender])) {
      throw;
    }
  }
  
  function approve(address _spender, uint _value) {
    if (msg.sender == address(this) || msg.sender == _spender) {
      throw;
    }
    allowed[msg.sender][_spender] = _value;
    Approval(msg.sender, _spender, _value);
  }

  function transfer(address _to, uint _value) {
    if (_to == address(this) || _value == 0) {
      throw;
    }
    balances[msg.sender] = safeSub(balances[msg.sender], _value);
    balances[_to] = safeAdd(balances[_to], _value);
    Transfer(msg.sender, _to, _value);
  }

  function transferFrom(address _from, address _to, uint _value) {
    if (_from == _to || _to == address(this) || _value == 0) {
      throw;
    }
    balances[_to] = safeAdd(balances[_to], _value);
    balances[_from] = safeSub(balances[_from], _value);
    allowed[_from][msg.sender] = safeSub(allowed[_from][msg.sender], _value);
    Transfer(_from, _to, _value);
  }

}