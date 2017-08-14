pragma solidity 0.4.11;

import "./SafeMath.sol";
import "./ERC20.sol";
import "./ERC20Basic.sol";
import "./ERC223ReceivingContract.sol";

contract Power is ERC20Basic, ERC223ReceivingContract {
  using SafeMath for uint;

  event Slashing(address indexed holder, uint value, bytes32 data);

  string public name = "Acebusters Power";
  string public symbol = "ABP";
  uint256 public decimals = 12;
  

  // time it should take to power down
  uint256 public downtime;
  // token contract address
  address internal nutzAddr;
  // sum of all outstanding power
  uint256 outstandingPower = 0;
  // authorized power
  uint256 internal authorizedPower = 0;
  // when powering down, at least totalSupply/minShare Power should be claimed
  uint256 internal minShare = 10000;

  // maxPower is a limit of total power that can be outstanding
  // maxPower has a valid value between outstandingPower and authorizedPow/2
  uint256 internal maxPower = 0;

  // all holder balances
  mapping (address => uint256) internal balances;

  // data structure for withdrawals
  struct DownRequest {
    address owner;
    uint256 total;
    uint256 left;
    uint256 start;
  }
  DownRequest[] public downs;

  function Power(address _nutzAddr, uint256 _downtime) {
    nutzAddr = _nutzAddr;
    downtime = _downtime;
  }

  /// @param _holder The address from which the balance will be retrieved
  /// @return The balance
  function balanceOf(address _holder) constant returns (uint256 balance) {
    return balances[_holder];
  }

  function activeSupply() constant returns (uint256) {
    return outstandingPower;
  }

  function totalSupply() constant returns (uint256) {
    uint256 issuedPower = authorizedPower.div(2);
    // return max of maxPower or issuedPower
    return maxPower >= issuedPower ? maxPower : issuedPower;
  }

  function vestedDown(uint256 _pos, uint256 _now) constant returns (uint256) {
    if (downs.length <= _pos) {
      return 0;
    }
    if (_now <= downs[_pos].start) {
      return 0;
    }
    // calculate amountVested
    // amountVested is amount that can be withdrawn according to time passed
    DownRequest storage req = downs[_pos];
    uint256 timePassed = _now.sub(req.start);
    if (timePassed > downtime) {
     timePassed = downtime;
    }
    uint256 amountVested = req.total.mul(timePassed).div(downtime);
    uint256 amountFrozen = req.total.sub(amountVested);
    if (req.left <= amountFrozen) {
      return 0;
    }
    return req.left.sub(amountFrozen);
  }





  // ############################################
  // ########### INTERNAL FUNCTIONS #############
  // ############################################

  // executes a powerdown request
  function _downTick(uint256 _pos, uint256 _now) internal returns (bool success) {
    uint256 amountPow = vestedDown(_pos, _now);
    DownRequest storage req = downs[_pos];

    // prevent power down in tiny steps
    uint256 minStep = req.total.div(10);
    require(req.left <= minStep || minStep <= amountPow);

    // calculate token amount representing share of power
    var nutzContract = ERC20(nutzAddr);
    uint256 totalBabz = nutzContract.totalSupply();
    uint256 amountBabz = amountPow.mul(totalBabz).div(authorizedPower);
    // transfer power and tokens
    outstandingPower = outstandingPower.sub(amountPow);
    req.left = req.left.sub(amountPow);
    bytes memory empty;
    assert(nutzContract.transfer(req.owner, amountBabz, empty));
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




  // ############################################
  // ########### ADMIN FUNCTIONS ################
  // ############################################

  modifier onlyNutzContract() {
    require(msg.sender == nutzAddr);
    _;
  }

  function setMaxPower(uint256 _maxPower) onlyNutzContract {
    require(outstandingPower <= _maxPower && _maxPower < authorizedPower);
    maxPower = _maxPower;
  }

  // this is called when NTZ are deposited into the burn pool
  function dilutePower(uint256 _totalBabzBefore, uint256 _amountBabz) onlyNutzContract returns (bool) {
    if (authorizedPower == 0) {
      // during the first capital increase, set some big number as authorized shares
      authorizedPower = _totalBabzBefore.add(_amountBabz);
    } else {
      // in later increases, expand authorized shares at same rate like economy
      authorizedPower = authorizedPower.mul(_totalBabzBefore.add(_amountBabz)).div(_totalBabzBefore);
    }
    return true;
  }

  function slashPower(address _holder, uint256 _value, bytes32 _data) onlyNutzContract returns (uint256) {
    balances[_holder] = balances[_holder].sub(_value);
    uint256 previouslyOutstanding = outstandingPower;
    outstandingPower = previouslyOutstanding.sub(_value);
    Slashing(_holder, _value, _data);
    return previouslyOutstanding;
  }

  function slashDownRequest(uint256 _pos, address _holder, uint256 _value, bytes32 _data) onlyNutzContract returns (uint256) {
    DownRequest storage req = downs[_pos];
    require(req.owner == _holder);
    req.left = req.left.sub(_value);
    uint256 previouslyOutstanding = outstandingPower;
    outstandingPower = previouslyOutstanding.sub(_value);
    Slashing(_holder, _value, _data);
    return previouslyOutstanding;
  }





  // ############################################
  // ########### PUBLIC FUNCTIONS ###############
  // ############################################

  // this is called when NTZ are deposited into the power pool
  function tokenFallback(address _from, uint256 _amountBabz, bytes _data) public {
    require(msg.sender == nutzAddr);
    uint256 totalBabz;
    assembly {
      totalBabz := mload(add(_data, 32))
    }
    require(authorizedPower != 0);
    require(_amountBabz != 0);
    require(totalBabz != 0);
    uint256 amountPow = _amountBabz.mul(authorizedPower).div(totalBabz);
    // check pow limits
    require(outstandingPower.add(amountPow) <= maxPower);
    outstandingPower = outstandingPower.add(amountPow);
    balances[_from] = balances[_from].add(amountPow);
    require(balances[_from] >= authorizedPower.div(minShare));
  }

  // registers a powerdown request
  function transfer(address _to, uint256 _amountPower) public returns (bool success) {
    // make Power not transferable
    require(_to == nutzAddr);
    // prevent powering down tiny amounts
    require(_amountPower >= authorizedPower.div(minShare));

    balances[msg.sender] = balances[msg.sender].sub(_amountPower);
    uint256 pos = downs.length++;
    downs[pos] = DownRequest(msg.sender, _amountPower, _amountPower, now);
    Transfer(msg.sender, nutzAddr, _amountPower);
    return true;
  }

  function downTick(uint256 _pos) public returns (bool success) {
      return _downTick(_pos, now);
  }

  // !!!!!!!!!!!!!!!!!!!!!!!! IMPORTANT !!!!!!!!!!!!!!!!!!!!!
  // REMOVE THIS BEFORE DEPLOYMENT!!!!
  // needed for accelerated time testing
  function downTickTest(uint256 _pos, uint256 _now) public returns (bool success) {
    return _downTick(_pos, _now);
  }
  // !!!!!!!!!!!!!!!!!!!!!!!! IMPORTANT !!!!!!!!!!!!!!!!!!!!!

}
