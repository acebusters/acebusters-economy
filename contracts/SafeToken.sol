pragma solidity ^0.4.8;

contract SafeMath {

  function safeMul(uint a, uint b) internal returns (uint) {
    uint c = a * b;
    assert(a == 0 || c / a == b);
    return c;
  }

  function safeDiv(uint a, uint b) internal returns (uint) {
    assert(b > 0);
    uint c = a / b;
    assert(a == b * c + a % b);
    return c;
  }

  function safeSub(uint a, uint b) internal returns (uint) {
    assert(b <= a);
    return a - b;
  }

  function safeAdd(uint a, uint b) internal returns (uint) {
    uint c = a + b;
    assert(c>=a && c>=b);
    return c;
  }

  function assert(bool assertion) internal {
    if (!assertion) {
      throw;
    }
  }
}

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

  uint public totalSupply;
  mapping(address => uint) balances;
  mapping (address => mapping (address => uint)) allowed;
  
  // the Token sale mechanism parameters:

  uint public ceiling;
  uint public floor;
  address public admin;
  // this is the contract's ethereum balance except 
  // all ethereum which has been parked to be withdrawn in "allocations"
  uint public totalReserve;
  mapping(address => uint) allocations;
  

  function balanceOf(address _owner) constant returns (uint balance) {
    return balances[_owner];
  }

  function allowance(address _owner, address _spender) constant returns (uint remaining) {
    return allowed[_owner][_spender];
  }

  function allocatedTo(address _owner) constant returns (uint) {
    return allocations[_owner];
  }
  
  function SafeToken() {
      admin = msg.sender;
      ceiling = 10;
      floor = 10;
  }

  modifier onlyAdmin() {
    if (msg.sender == admin) {
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
    if (_newFloor == 0 || _newFloor > ceiling) {
        throw;
    }
    // moveFloor fails if the administrator tries to push the floor so low
    // that the sale mechanism is no longer able to buy back all tokens at
    // the floor price if those funds were to be withdrawn.
    uint newReserveNeeded = safeDiv(totalSupply, _newFloor);
    if (totalReserve < newReserveNeeded) {
        throw;
    }
    floor = _newFloor;
  }
  
  function allocateEther(address _to, uint _value) onlyAdmin {
    if (_value == 0) {
        return;
    }
    // allocateEther fails if allocating those funds would mean that the
    // sale mechanism is no longer able to buy back all tokens at the floor
    // price if those funds were to be withdrawn.
    uint leftReserve = safeSub(totalReserve, _value);
    if (leftReserve < safeDiv(totalSupply, floor)) {
        throw;
    }
    totalReserve = safeSub(totalReserve, _value);
    allocations[_to] = safeAdd(allocations[_to], _value);
  }
  
  function () payable {
    purchaseTokens();
  }
  
  function purchaseTokens() payable {
    if (msg.value == 0) {
      return;
    }
    uint amount = safeMul(msg.value, ceiling);
    totalReserve = safeAdd(totalReserve, msg.value);
    totalSupply = safeAdd(totalSupply, amount);
    balances[msg.sender] = safeAdd(balances[msg.sender], amount);
    Purchase(msg.sender, amount);
  }
  
  function sellTokens(uint _value) {
    uint amount = safeDiv(_value, floor);
    totalSupply = safeSub(totalSupply, _value);
    balances[msg.sender] = safeSub(balances[msg.sender], _value);
    totalReserve = safeSub(totalReserve, amount);
    allocations[msg.sender] = safeAdd(allocations[msg.sender], amount);
    Sell(msg.sender,  _value);
  }
  
  // withdraw accumulated balance, called by seller or beneficiary
  function claimEther() {
    if (allocations[msg.sender] == 0) {
      return;
    }
    if (this.balance < allocations[msg.sender]) {
      throw;
    }
    allocations[msg.sender] = 0;
    if (!msg.sender.send(allocations[msg.sender])) {
      throw;
    }
  }
  
  function approve(address _spender, uint _value) {
    allowed[msg.sender][_spender] = _value;
    Approval(msg.sender, _spender, _value);
  }

  function transfer(address _to, uint _value) {
    balances[msg.sender] = safeSub(balances[msg.sender], _value);
    balances[_to] = safeAdd(balances[_to], _value);
    Transfer(msg.sender, _to, _value);
  }

  function transferFrom(address _from, address _to, uint _value) {
    balances[_to] = safeAdd(balances[_to], _value);
    balances[_from] = safeSub(balances[_from], _value);
    allowed[_from][msg.sender] = safeSub(allowed[_from][msg.sender], _value);
    Transfer(_from, _to, _value);
  }

}