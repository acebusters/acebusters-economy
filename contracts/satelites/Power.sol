pragma solidity 0.4.11;

import "../ERC20Basic.sol";
import "../ownership/Ownable.sol";
import "../controller/ControllerInterface.sol";

contract Power is Ownable, ERC20Basic {

  event Slashing(address indexed holder, uint value, bytes32 data);

  string public name = "Acebusters Power";
  string public symbol = "ABP";
  uint256 public decimals = 12;


  function balanceOf(address _holder) constant returns (uint256 balance) {
    return ControllerInterface(owner).powerBalanceOf(_holder);
  }

  function totalSupply() constant returns (uint256) {
    return ControllerInterface(owner).powerTotalSupply();
  }

  function activeSupply() constant returns (uint256) {
    return ControllerInterface(owner).outstandingPower();
  }


  // ############################################
  // ########### ADMIN FUNCTIONS ################
  // ############################################

  function slashPower(address _holder, uint256 _value, bytes32 _data) public onlyOwner {
    Slashing(_holder, _value, _data);
  }

  function powerUp(address _holder, uint256 _value) public onlyOwner {
    // NTZ transfered from user's balance to power pool
    Transfer(0x0, _holder, _value);
  }

  // ############################################
  // ########### PUBLIC FUNCTIONS ###############
  // ############################################

  // registers a powerdown request
  function transfer(address _to, uint256 _amountPower) public returns (bool success) {
    // make Power not transferable
    require(_to == 0x0);
    ControllerInterface(owner).createDownRequest(msg.sender, _amountPower);
    Transfer(msg.sender, 0x0, _amountPower);
    return true;
  }

  function downTick(address _owner, uint256 _pos) public {
    ControllerInterface(owner).downTick(_owner, _pos, now);
  }

}
