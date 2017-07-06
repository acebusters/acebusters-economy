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
  uint outstandingAbp;

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
    return outstandingAbp;
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

  // init power
  function _init(uint _size) internal {
    // during the first capital increase, set some big number as authorized shares
    balances[nutzAddr] = _size;
  }

  // executes a powerdown request
  function _downTick(uint _pos, uint _now) internal returns (bool success) {
    uint amountAbp = vestedDown(_pos, _now);
    if (amountAbp == 0) {
      throw;
    }
    DownRequest req = downs[_pos];

    // calculate token amount representing amount of power
    var nutzContract = ERC20(nutzAddr);
    uint totalBabz = nutzContract.activeSupply().add(nutzContract.balanceOf(address(this))).add(nutzContract.balanceOf(nutzAddr));
    uint amountBabz = amountAbp.mul(totalBabz).div(totalSupply());
    // transfer power and tokens
    balances[req.owner] = balances[req.owner].sub(amountAbp);
    downs[_pos].left = downs[_pos].left.sub(amountAbp);
    if (!nutzContract.transfer(req.owner, amountBabz)) {
      throw;
    }
    return true;
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
      _init(_totalBabzBefore.add(_amountBabz));
    } else {
      // in later increases, expand authorized shares at same rate like economy
      totalSupply().mul(_totalBabzBefore.add(_amountBabz)).div(_totalBabzBefore);
    }
    return true;
  }

  // this is called when NTZ are deposited into the power pool
  function up(address _sender, uint _amountNtz, uint _totalBabz) onlyNutzContract returns (bool) {
    if (_amountNtz == 0) {
      return false;
    }
    if (totalSupply() == 0) {
      _init(_amountNtz.add(_totalBabz));
    }
    uint amountAbp = _amountNtz.mul(totalSupply()).div(_totalBabz);
    if (outstandingAbp + amountAbp > totalSupply().div(2)) {
      // this powerup would assign more power to power holders than 50% of total NTZ.
      throw;
    }
    outstandingAbp = outstandingAbp.add(amountAbp);
    balances[_sender] = balances[_sender].add(amountAbp);
    return true;
  }




  // ############################################
  // ########### PUBLIC FUNCTIONS ###############
  // ############################################

  // registers a powerdown request
  // TODO: limit amount of powerdown per user
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
    // check overflow
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
