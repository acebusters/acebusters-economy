pragma solidity 0.4.11;

contract ControllerInterface {
  // Nutz functions
  function activeSupply() constant returns (uint256);
  function burnPool() constant returns (uint256);
  function floor() constant returns (uint256);
  function ceiling() constant returns (uint256);
  function powerPool() constant returns (uint256);
  function powerAddr() constant returns (address);
  function getBabzBal(address _owner) constant returns (uint256);
  function allowance(address _owner, address _spender) constant returns (uint256);

  function purchase() public payable returns (uint256);
  function approve(address _owner, address _spender, uint256 _amountBabz) public;
  function powerUp(address _from, uint256 _amountBabz) public;
  function sell(address _from, uint256 _amountBabz) public;
  function transfer(address _from, address _to, uint256 _amountBabz, bytes _data) public returns (bool);
  function transferFrom(address _sender, address _from, address _to, uint256 _amountBabz, bytes _data) public returns (bool);
  // Power functions
  
  function outstandingPower() constant returns (uint256);
  function authorizedPower() constant returns (uint256);
  function maxPower() constant returns (uint256);
  function getPowerBal(address owner) constant returns (uint256);

  function setPowBalance(address owner, uint256 amount);
  function downTick(uint256 _pos, uint256 _now);
  function createDownRequest(address _owner, uint256 _amountPower, uint256 _time);
}
