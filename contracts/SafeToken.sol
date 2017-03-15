pragma solidity ^0.4.7;

/**
 * Standard ERC20 token
 * https://github.com/ethereum/EIPs/issues/20
 */
contract SafeToken {

  event Transfer(address indexed from, address indexed to, uint value);
  event Approval(address indexed owner, address indexed spender, uint value);
  event Purchase(address indexed purchaser, uint value);
  event Sell(address indexed seller, uint value);
  event Error(uint errCode);
  
  string public name = "SafeToken";
  string public symbol = "VST";
  uint public decimals = 18;

  uint public totalSupply;
  uint public ceiling;
  uint public floor;
  address public admin;
  mapping(address => uint) balances;
  uint public totalReserve;
  mapping(address => uint) allocations;
  mapping (address => mapping (address => uint)) allowed;

  function balanceOf(address _owner) constant returns (uint balance) {
    return balances[_owner];
  }

  function allowance(address _owner, address _spender) constant returns (uint remaining) {
    return allowed[_owner][_spender];
  }
  
  function SafeToken() {
      admin = msg.sender;
      ceiling = 10;
      floor = 10;
  }

  modifier onlyAdmin() {
    if (msg.sender == admin) {
      _;
    } else {
      Error(3);
    }
  }
  
  function changeAdmin(address _newAdmin) onlyAdmin {
    if (_newAdmin == msg.sender) {
        Error(7);
    }
    if (_newAdmin == 0x0) {
        Error(8);
    }
    admin = _newAdmin;
  }
  
  function moveCeiling(uint _ceiling) onlyAdmin {
    if (_ceiling < floor) {
        Error(1);
    }
    ceiling = _ceiling;
  }
  
  function moveFloor(uint _newFloor) onlyAdmin {
    if (_newFloor == 0 || _newFloor > ceiling) {
        Error(2);
    }
    uint newReserveNeeded = totalSupply / _newFloor;
    if (totalSupply != newReserveNeeded * _newFloor + totalSupply % _newFloor) {
        Error(2);
    }
    if (totalReserve < newReserveNeeded) {
        Error(4);
    }
    floor = _newFloor;
  }
  
  function allocateEther(address _to, uint _value) onlyAdmin {
    // check uint overflow
    if (_value == 0 || _value > totalReserve) {
        Error(2);
    }
    if (totalReserve - _value < totalSupply / floor) {
        Error(4);
    }
    totalReserve -= _value;
    allocations[_to] += _value;
  }
  
  function () payable {
    purchaseTokens();
  }
  
  function purchaseTokens() payable {
    if (msg.value == 0) {
      throw;
    }
    // check uint overflow
    uint amount = msg.value * ceiling;
    if (amount / msg.value != ceiling) {
      throw;
    }
    // check uint overflow
    uint sum = totalSupply + amount;
    if (sum < totalSupply || sum < amount) {
      throw;
    }
    totalReserve += msg.value;
    totalSupply = sum;
    balances[msg.sender] += amount;
    Purchase(msg.sender, msg.value);
  }
  
  function sellTokens(uint _value) {
    uint amount = _value * floor;
    if (_value != 0 && amount / _value != floor) {
        Error(14);
        return;
    }
    if (amount > balances[msg.sender]) {
        Error(3);
        return;
    }
    if (_value > totalReserve) {
        Error(3);
        return;
    }
    totalSupply -= amount;
    balances[msg.sender] -= amount;
    totalReserve -= _value;
    allocations[msg.sender] += _value;
    Sell(msg.sender,  _value);
  }
  
  // withdraw accumulated balance, called by seller or beneficiary
  function claimEther() {
    uint amount = allocations[msg.sender];
    if (amount == 0) {
      Error(5);
      return;
    }
    if (this.balance < amount) {
      Error(6);
      return;
    }
    allocations[msg.sender] = 0;
    if (!msg.sender.send(amount)) {
      throw;
    }
  }
  
  function approve(address _spender, uint _value) {
    allowed[msg.sender][_spender] = _value;
    Approval(msg.sender, _spender, _value);
  }

  function transfer(address _to, uint _value) {
    if (_value > balances[msg.sender]) {
      Error(9);
      return;
    }
    
    uint newBalTo = balances[_to] + _value;
    if (newBalTo < balances[_to] || newBalTo < _value) {
      Error(11);
      return;
    }
    balances[msg.sender] -= _value;
    balances[_to] = newBalTo;
    Transfer(msg.sender, _to, _value);
  }

  function transferFrom(address _from, address _to, uint _value) {
    if (_value > balances[_from]) {
      Error(8);
      return;
    }
    if (_value > allowed[_from][msg.sender]) {
      Error(17);
      return;
    }
    uint newBalTo = balances[_to] + _value;
    if (newBalTo < balances[_to] || newBalTo < _value) {
      Error(7);
      return;
    }
    balances[_to] = newBalTo;
    balances[_from] -= _value;
    allowed[_from][msg.sender] -= _value;
    Transfer(_from, _to, _value);
  }

}