pragma solidity ^0.4.8;

import "./Nutz.sol";
import "./SafeMath.sol";
import "./PowerInterface.sol";

contract Power is PowerInterface {
  using SafeMath for uint;

  // total amount of tokens
  uint public totalSupply;
  uint public downtime;
  address public nutzAddr;
  // maximum amount of power that can be given out;
  uint public maxPower;
  bool preemption;

  mapping (address => uint256) balances;

  struct DownRequest {
    address owner;
    uint total;
    uint left;
    uint start;
  }

  DownRequest[] downs;

  /// @param _holder The address from which the balance will be retrieved
  /// @return The balance
  function balanceOf(address _holder) constant returns (uint256 balance) {
    return balances[_holder];
  }

  function Power(address _nutzAddr, uint _downtime, uint _initialSupply) {
    nutzAddr = _nutzAddr;
    downtime = _downtime;
    totalSupply = _initialSupply;
    balances[nutzAddr] = _initialSupply;
    maxPower = _initialSupply.div(10);
    preemption = true;
  }

  function configure(uint _downtime, uint _maxPower, bool _preemption) {
    downtime = _downtime;
    maxPower = _maxPower;
    preemption = _preemption;
  }

  // executes a powerdown request
  function _downTick(uint _pos, uint _now) internal returns (bool success) {
    if (downs.length <= _pos) {
      throw;
    }
    if (_now <= downs[_pos].start) {
      throw;
    }
    uint elapsed = _now.sub(downs[_pos].start).div(downtime);
    uint expected = downs[_pos].total.sub(downs[_pos].total.mul(elapsed));
    if (downs[_pos].left <= expected) {
      throw;
    }
    uint amountPower = downs[_pos].left.sub(expected);
    if (balances[downs[_pos].owner] < amountPower) {
      throw;
    }
    if (totalSupply - amountPower > totalSupply) {
      throw;
    }
    var nutz = Nutz(nutzAddr);

    uint amountAce = amountPower.mul(nutz.totalSupply()).div(totalSupply);
    if (nutz.balanceOf(this) < amountAce) {
      throw;
    }
    balances[downs[_pos].owner] = balances[downs[_pos].owner].sub(amountPower);
    totalSupply -= totalSupply.sub(amountPower);
    downs[_pos].left = expected;
    if (!nutz.transfer(downs[_pos].owner, amountAce)) {
      throw;
    }
    return true;
  }


  modifier onlyAce() {
    //checking access
    if (msg.sender != nutzAddr) {
      throw;
    }
    _;
  }

  function accredit(address _investor) onlyAce {
    if (balances[_investor] == 0) {
      balances[nutzAddr] -= 1;
      balances[_investor] = 1;
    }
  }

  // this is called when NTZ are deposited into the power pool
  function up(address _sender, uint _value, uint _totalSupply) onlyAce returns (bool) {
    if (_value <= 0) {
      throw;
    }
    if (preemption == true && balances[_sender] == 0) {
      // only active investors are allowed to power up
      // _sender is not an active investor
      throw;
    }
    uint amount = _value.mul(totalSupply).div(_totalSupply);
    if (balances[nutzAddr].sub(amount) < totalSupply.sub(maxPower)) {
      // this powerup would assign more power to investors
      // than allowed by maxPower.
      throw;
    }
    balances[nutzAddr] = balances[nutzAddr].sub(amount);
    balances[_sender] = balances[_sender].add(amount);
    return true;
  }

  // registers a powerdown request
  function down(uint _amountPower) returns (bool success) {
    if (_amountPower <= 0) {
      throw;
    }
    if (balances[msg.sender] < _amountPower) {
      throw;
    }
    if (totalSupply - _amountPower > totalSupply) {
      throw;
    }

    uint pos = downs.length++;
    downs[pos] = DownRequest(msg.sender, _amountPower, _amountPower, now);
    return true;
  }

  function downTick(uint _pos) returns (bool success) {
      return _downTick(_pos, now);
  }

// !!!!!!!!!!!!!!!!!!!!!!!! IMPORTANT !!!!!!!!!!!!!!!!!!!!!
// REMOVE THIS BEFORE DEPLOYMENT!!!!
// needed for accelerated time testing
    function downTickTest(uint _pos, uint _now) returns (bool success) {
        return _downTick(_pos, _now);
    }
// !!!!!!!!!!!!!!!!!!!!!!!! IMPORTANT !!!!!!!!!!!!!!!!!!!!!

}