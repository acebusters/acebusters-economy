pragma solidity ^0.4.11;

import "./SafeMath.sol";
import "./ERC20.sol";
import "./ERC20Basic.sol";

contract Power is ERC20Basic {
  using SafeMath for uint;

  string public name = "Acebusters Power";
  string public symbol = "ABP";
  uint public decimals = 12;

  // time it should take to power down
  uint public downtime;
  // token contract address
  address public nutzAddr;
  // sum of all outstanding shares
  uint public outstandingAbp;

  // all investors balances
  mapping (address => uint256) balances;
  // balances[nutzAddr]  // stores authorized shares

  // data structure for withdrawals
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

  function totalSupply() constant returns (uint256) {
    return balances[nutzAddr];
  }

  function Power(address _nutzAddr, uint _downtime) {
    nutzAddr = _nutzAddr;
    downtime = _downtime;
  }

  // executes a powerdown request
  function _downTick(uint _pos, uint _now) internal returns (bool success) {
    if (downs.length <= _pos) {
      throw;
    }
    if (_now <= downs[_pos].start) {
      throw;
    }
    // calculate amount that can be withdrawn according to time passed
    DownRequest req = downs[_pos];
    uint timePassed = _now.sub(req.start);
    if (timePassed > downtime) {
     timePassed = downtime;
    }
    uint amountVested = req.total.mul(timePassed).div(downtime);
    uint amountLeft = req.total.sub(amountVested);
    if (req.left <= amountLeft) {
      throw;
    }
    uint amountAbp = req.left.sub(amountLeft);

    // calculate token amount representing amount of power
    var nutzContract = ERC20(nutzAddr);
    uint totalNtz = nutzContract.activeSupply().add(nutzContract.balanceOf(address(this))).add(nutzContract.balanceOf(nutzAddr));
    uint amountNtz = amountAbp.mul(totalNtz).div(balances[nutzAddr]);
    // transfer power and tokens
    balances[req.owner] = balances[req.owner].sub(amountAbp);
    downs[_pos].left = amountLeft;
    if (!nutzContract.transfer(req.owner, amountNtz)) {
      throw;
    }
    return true;
  }


  modifier onlyNutzContract() {
    //checking access
    if (msg.sender != nutzAddr) {
      throw;
    }
    _;
  }

  function configure(uint _downtime) onlyNutzContract {
    downtime = _downtime;
  }

  // this is called when NTZ are deposited into the burn pool
  function burn(uint _totalSupplyBefore, uint _amount) onlyNutzContract returns (bool) {
    if (balances[nutzAddr] == 0) {
      // during the first capital increase, set some big number as authorized shares
      balances[nutzAddr] = _totalSupplyBefore.add(_amount);
    } else {
      // in later increases, expand authorized shares at same rate like economy
      balances[nutzAddr].mul(_totalSupplyBefore.add(_amount)).div(_totalSupplyBefore);
    }
    return true;
  }

  // this is called when NTZ are deposited into the power pool
  function up(address _sender, uint _amountNtz, uint _totalSupply) onlyNutzContract returns (bool) {
    if (_amountNtz <= 0) {
      return false;
    }
    uint authorizedShares = balances[nutzAddr];
    uint amountAbp = _amountNtz.mul(authorizedShares).div(_totalSupply);
    if (outstandingAbp + amountAbp > authorizedShares.div(2)) {
      // this powerup would assign more power to investors
      // than allowed by maxPower.
      throw;
    }
    outstandingAbp = outstandingAbp.add(amountAbp);
    balances[_sender] = balances[_sender].add(amountAbp);
    return true;
  }

  // registers a powerdown request
  // limit amount of powerdown per user
  function transfer(address _to, uint _amountPower) returns (bool success) {
    if (_to != nutzAddr) {
      throw;
    }
    if (_amountPower <= 0) {
      throw;
    }
    if (balances[msg.sender] < _amountPower) {
      throw;
    }
//    if (balances[this] - _amountPower > balances[this]) {
//      throw;
//    }

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
