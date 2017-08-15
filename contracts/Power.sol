pragma solidity 0.4.11;

import "./SafeMath.sol";
import "./ERC20.sol";
import "./ERC20Basic.sol";
import "./Ownable.sol";
import "./ControllerInterface.sol";

contract Power is ERC20Basic, Ownable {
  using SafeMath for uint;

  event Slashing(address indexed holder, uint value, bytes32 data);

  string public name = "Acebusters Power";
  string public symbol = "ABP";
  uint256 public decimals = 12;

  /// @param _holder The address from which the balance will be retrieved
  /// @return The balance
  function balanceOf(address _holder) constant returns (uint256 balance) {
    return ControllerInterface(owner).getPowerBal(_holder);
  }

  function activeSupply() constant returns (uint256) {
    return ControllerInterface(owner).outstandingPower();
  }

  function totalSupply() constant returns (uint256) {
    var contr = ControllerInterface(owner);
    uint256 issuedPower = contr.authorizedPower().div(2);
    uint maxPower = contr.maxPower();
    // return max of maxPower or issuedPower
    return maxPower >= issuedPower ? maxPower : issuedPower;
  }


  // ############################################
  // ########### ADMIN FUNCTIONS ################
  // ############################################

  function slashPower(address _holder, uint256 _value, bytes32 _data) onlyOwner {
    Slashing(_holder, _value, _data);
  }


  // ############################################
  // ########### PUBLIC FUNCTIONS ###############
  // ############################################

  // registers a powerdown request
  function transfer(address _to, uint256 _amountPower) public returns (bool success) {
    // make Power not transferable
    require(_to == owner);
    // prevent powering down tiny amounts
    var contr = ControllerInterface(owner);
    // when powering down, at least totalSupply/minShare Power should be claimed
    require(_amountPower >= contr.authorizedPower().div(10000)); // minShare = 10000;

    uint256 powBal = contr.getPowerBal(msg.sender);
    contr.setPowBalance(msg.sender, powBal.sub(_amountPower));
    contr.createDownRequest(msg.sender, _amountPower, now);
    Transfer(msg.sender, owner, _amountPower);
    return true;
  }

  function downTick(uint256 _pos) public returns (bool success) {
    ControllerInterface(owner).downTick(_pos, now);
  }

  // !!!!!!!!!!!!!!!!!!!!!!!! IMPORTANT !!!!!!!!!!!!!!!!!!!!!
  // REMOVE THIS BEFORE DEPLOYMENT!!!!
  // needed for accelerated time testing
  function downTickTest(uint256 _pos, uint256 _now) public returns (bool success) {
    ControllerInterface(owner).downTick(_pos, _now);
  }
  // !!!!!!!!!!!!!!!!!!!!!!!! IMPORTANT !!!!!!!!!!!!!!!!!!!!!

}
