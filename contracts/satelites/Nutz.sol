pragma solidity 0.4.11;

import "../ERC20.sol";
import "../ownership/Ownable.sol";
import "../controller/ControllerInterface.sol";

/**
 * Nutz implements a price floor and a price ceiling on the token being
 * sold. It is based of the zeppelin token contract.
 */
contract Nutz is Ownable, ERC20 {

  event Purchase(address indexed purchaser, uint256 value);
  event Sell(address indexed seller, uint256 value);
  
  string public name = "Acebusters Nutz";
  // acebusters units:
  // 10^12 - Nutz   (NTZ)
  // 10^9 - Jonyz
  // 10^6 - Helcz
  // 10^3 - Pascalz
  // 10^0 - Babz
  string public symbol = "NTZ";
  uint256 public decimals = 12;

  // returns balances of active holders
  function balanceOf(address _owner) constant returns (uint) {
    return ControllerInterface(owner).babzBalanceOf(_owner);
  }

  function totalSupply() constant returns (uint256) {
    return ControllerInterface(owner).totalSupply();
  }

  function activeSupply() constant returns (uint256) {
    return ControllerInterface(owner).activeSupply();
  }

  // return remaining allowance
  // if calling return allowed[address(this)][_spender];
  // returns balance of ether parked to be withdrawn
  function allowance(address _owner, address _spender) constant returns (uint256) {
    return ControllerInterface(owner).allowance(_owner, _spender);
  }

  // returns either the salePrice, or if reserve does not suffice
  // for active supply, returns maxFloor
  function floor() constant returns (uint256) {
    return ControllerInterface(owner).floor();
  }

  // returns either the salePrice, or if reserve does not suffice
  // for active supply, returns maxFloor
  function ceiling() constant returns (uint256) {
    return ControllerInterface(owner).ceiling();
  }

  function powerPool() constant returns (uint256) {
    return ControllerInterface(owner).powerPool();
  }



  // ############################################
  // ########### ADMIN FUNCTIONS ################
  // ############################################

  function powerDown(address _holder, uint256 _amountBabz) onlyOwner {
    // NTZ transfered from power pool to user's balance
    Transfer(0x0, _holder, _amountBabz);
  }



  // ############################################
  // ########### PUBLIC FUNCTIONS ###############
  // ############################################
  
  function approve(address _spender, uint256 _amountBabz) public {
    ControllerInterface(owner).approve(msg.sender, _spender, _amountBabz);
    Approval(msg.sender, _spender, _amountBabz);
  }

  function transfer(address _to, uint256 _amountBabz, bytes _data) public returns (bool) {
    if (_to == 0x0) {
      // powerup
      ControllerInterface(owner).powerUp(msg.sender, msg.sender, _amountBabz);
    } else {
      ControllerInterface(owner).transfer(msg.sender, _to, _amountBabz, _data);
      Transfer(msg.sender, _to, _amountBabz);
    }
    return true;
  }

  function transfer(address _to, uint256 _amountBabz) public returns (bool) {
    bytes memory empty;
    return transfer(_to, _amountBabz, empty);
  }

  function transData(address _to, uint256 _amountBabz, bytes _data) public returns (bool) {
    return transfer(_to, _amountBabz, _data);
  }

  function transferFrom(address _from, address _to, uint256 _amountBabz, bytes _data) public returns (bool) {
    if (_to == 0x0) {
      // powerup
      ControllerInterface(owner).powerUp(msg.sender, _from, _amountBabz);
    } else {
      ControllerInterface(owner).transferFrom(msg.sender, _from, _to, _amountBabz, _data);
      Transfer(_from, _to, _amountBabz);
    }
    return true;
  }

  function transferFrom(address _from, address _to, uint256 _amountBabz) public returns (bool) {
    bytes memory empty;
    return transferFrom(_from, _to, _amountBabz, empty);
  }

  function purchase(uint256 _price) public payable {
    require(msg.value > 0);
    uint256 amountBabz = ControllerInterface(owner).purchase.value(msg.value)(msg.sender, _price);
    Purchase(msg.sender, amountBabz);
  }

  function sell(uint256 _price, uint256 _amountBabz) public {
    ControllerInterface(owner).sell(msg.sender, _price, _amountBabz);
    Sell(msg.sender, _amountBabz);
  }

  function powerUp(uint256 _amountBabz) public {
    ControllerInterface(owner).powerUp(msg.sender, msg.sender, _amountBabz);
  }

}
