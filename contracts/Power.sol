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
  address nutzAddr;
  // sum of all outstanding shares
  uint outstandingPow;
  // when powering down, at least totalSupply/minShare Power should be claimed
  uint minShare = 10000;

  // all holder balances
  mapping (address => uint256) balances;

  // data structure for withdrawals
  struct DownRequest {
    address owner;
    uint total;
    uint left;
    uint start;
  }
  DownRequest[] downs;

  function Power(address _nutzAddr, uint _downtime) {
    nutzAddr = _nutzAddr;
    downtime = _downtime;
  }

  /// @param _holder The address from which the balance will be retrieved
  /// @return The balance
  function balanceOf(address _holder) constant returns (uint256 balance) {
    return balances[_holder];
  }

  function activeSupply() constant returns (uint256) {
    return outstandingPow;
  }

  function totalSupply() constant returns (uint256) {
    return balances[nutzAddr];
  }

  function vestedDown(uint _pos, uint _now) constant returns (uint256) {
    if (downs.length <= _pos) {
      return 0;
    }
    if (_now <= downs[_pos].start) {
      return 0;
    }
    // calculate amountVested
    // amountVested is amount that can be withdrawn according to time passed
    DownRequest req = downs[_pos];
    uint timePassed = _now.sub(req.start);
    if (timePassed > downtime) {
     timePassed = downtime;
    }
    uint amountVested = req.total.mul(timePassed).div(downtime);
    uint amountFrozen = req.total.sub(amountVested);
    if (req.left <= amountFrozen) {
      return 0;
    }
    return req.left.sub(amountFrozen);
  }






  // ############################################
  // ########### INTERNAL FUNCTIONS #############
  // ############################################

  // executes a powerdown request
  function _downTick(uint _pos, uint _now) internal returns (bool success) {
    uint amountPow = vestedDown(_pos, _now);
    if (amountPow == 0) {
      throw;
    }
    DownRequest req = downs[_pos];

    // prevent power down in tiny steps
    uint minStep = req.total.div(10);
    if (amountPow < minStep && req.left > minStep) {
      throw;
    }

    // calculate token amount representing share of power
    var nutzContract = ERC20(nutzAddr);
    uint totalBabz = nutzContract.totalSupply();
    uint amountBabz = amountPow.mul(totalBabz).div(totalSupply());
    // transfer power and tokens
    balances[req.owner] = balances[req.owner].sub(amountPow);
    req.left = req.left.sub(amountPow);
    if (!nutzContract.transfer(req.owner, amountBabz)) {
      throw;
    }
    // down request completed
    if (req.left == 0) {
      // if not last element, switch with last
      if (_pos < downs.length - 1) {
        downs[_pos] = downs[downs.length - 1];
      }
      // then cut off the tail
      downs.length--;
    }
    return true;
  }

  // this is called when NTZ are deposited into the power pool
  function _up(address _sender, uint _amountBabz, uint _totalBabz) internal {
    if (totalSupply() == 0 || _amountBabz == 0 || _totalBabz == 0 || _amountBabz < _totalBabz.div(minShare)) {
      throw;
    }
    uint amountPow = _amountBabz.mul(totalSupply()).div(_totalBabz);
    if (outstandingPow + amountPow > totalSupply().div(2)) {
      // this powerup would assign more power to power holders than 50% of total NTZ.
      throw;
    }
    outstandingPow = outstandingPow.add(amountPow);
    balances[_sender] = balances[_sender].add(amountPow);
  }


  // ############################################
  // ########### ADMIN FUNCTIONS ################
  // ############################################

  modifier onlyNutzContract() {
    //checking access
    if (msg.sender != nutzAddr) {
      throw;
    }
    _;
  }

  // this is called when NTZ are deposited into the burn pool
  function burn(uint _totalBabzBefore, uint _amountBabz) onlyNutzContract returns (bool) {
    if (totalSupply() == 0) {
      // during the first capital increase, set some big number as authorized shares
      balances[nutzAddr] = _totalBabzBefore.add(_amountBabz);
    } else {
      // in later increases, expand authorized shares at same rate like economy
      balances[nutzAddr] = totalSupply().mul(_totalBabzBefore.add(_amountBabz)).div(_totalBabzBefore);
    }
    return true;
  }

  function tokenFallback(address _from, uint _value, bytes32 _data) onlyNutzContract {
    _up(_from, _value, uint256(_data));
  }


  // ############################################
  // ########### PUBLIC FUNCTIONS ###############
  // ############################################

  // registers a powerdown request
  function transfer(address _to, uint _amountPower) returns (bool success) {
    // make Power not transferable
    if (_to != nutzAddr) {
      throw;
    }
    // prevent powering down tiny amounts or spending more than there is
    if (balances[msg.sender] < _amountPower || _amountPower <= totalSupply().div(minShare)) {
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
