pragma solidity 0.4.11;

import "./SafeMath.sol";
import "./ERC20.sol";
import "./ERC20Basic.sol";
import "./Ownable.sol";

contract Controller {
  function powBalance(address owner) constant returns (uint256);
  function outstandingPower() constant returns (uint256);
  function authorizedPower() constant returns (uint256);
  function maxPower() constant returns (uint256);
  function setPowBalance(address owner, uint256 amount);
  function setOutstandingPower(uint256 amount);
  function setAuthorizedPower(uint256 amount);
}

contract Power is ERC20Basic, Ownable {
  using SafeMath for uint;

  event Slashing(address indexed holder, uint value, bytes32 data);

  string public name = "Acebusters Power";
  string public symbol = "ABP";
  uint256 public decimals = 12;
  

  // time it should take to power down
  uint256 public downtime;

  // when powering down, at least totalSupply/minShare Power should be claimed
  uint256 internal minShare = 10000;

  // data structure for withdrawals
  struct DownRequest {
    address owner;
    uint256 total;
    uint256 left;
    uint256 start;
  }
  DownRequest[] public downs;

  function Power(uint256 _downtime) Ownable() {
    downtime = _downtime;
  }

  /// @param _holder The address from which the balance will be retrieved
  /// @return The balance
  function balanceOf(address _holder) constant returns (uint256 balance) {
    var contr = Controller(owner);
    return contr.powBalance(_holder);
  }

  function activeSupply() constant returns (uint256) {
    var contr = Controller(owner);
    return contr.outstandingPower();
  }

  function totalSupply() constant returns (uint256) {
    var contr = Controller(owner);
    uint256 issuedPower = contr.authorizedPower().div(2);
    uint maxPower = contr.maxPower();
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
    var nutzContract = ERC20(owner);
    uint256 totalBabz = nutzContract.totalSupply();
    var contr = Controller(owner);
    uint256 amountBabz = amountPow.mul(totalBabz).div(contr.authorizedPower());
    // transfer power and tokens
    uint256 outstandingPower = contr.outstandingPower();
    contr.setOutstandingPower(outstandingPower.sub(amountPow));
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

  function slashPower(address _holder, uint256 _value, bytes32 _data) onlyOwner {
    Slashing(_holder, _value, _data);
  }

  function slashDownRequest(uint256 _pos, address _holder, uint256 _value, bytes32 _data) onlyOwner returns (uint256) {
    DownRequest storage req = downs[_pos];
    require(req.owner == _holder);
    req.left = req.left.sub(_value);
    var contr = Controller(owner);
    uint256 previouslyOutstanding = contr.outstandingPower();
    contr.setOutstandingPower(previouslyOutstanding.sub(_value));
    Slashing(_holder, _value, _data);
    return previouslyOutstanding;
  }





  // ############################################
  // ########### PUBLIC FUNCTIONS ###############
  // ############################################

  // registers a powerdown request
  function transfer(address _to, uint256 _amountPower) public returns (bool success) {
    // make Power not transferable
    require(_to == owner);
    // prevent powering down tiny amounts
    var contr = Controller(owner);
    require(_amountPower >= contr.authorizedPower().div(minShare));

    uint256 powBal = contr.powBalance(msg.sender);
    contr.setPowBalance(msg.sender, powBal.sub(_amountPower));
    uint256 pos = downs.length++;
    downs[pos] = DownRequest(msg.sender, _amountPower, _amountPower, now);
    Transfer(msg.sender, owner, _amountPower);
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
