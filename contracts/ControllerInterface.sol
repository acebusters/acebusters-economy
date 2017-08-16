pragma solidity 0.4.11;

contract ControllerInterface {

  // Nutz functions
  function babzBalanceOf(address _owner) constant returns (uint256);
  function activeSupply() constant returns (uint256);
  function burnPool() constant returns (uint256);
  function powerPool() constant returns (uint256);
  function totalSupply() constant returns (uint256);
  function allowance(address _owner, address _spender) constant returns (uint256);

  function approve(address _owner, address _spender, uint256 _amountBabz) public;
  function transfer(address _from, address _to, uint256 _amountBabz, bytes _data) public;
  function transferFrom(address _sender, address _from, address _to, uint256 _amountBabz, bytes _data) public returns (bool);
  
  // Market functions
  function floor() constant returns (uint256);
  function ceiling() constant returns (uint256);
  
  function purchase(address _sender) public payable returns (uint256);
  function sell(address _from, uint256 _amountBabz) public;

  // Power functions
  function powerBalanceOf(address _owner) constant returns (uint256);
  function outstandingPower() constant returns (uint256);
  function authorizedPower() constant returns (uint256);
  function powerTotalSupply() constant returns (uint256);
  
  function powerUp(address _from, uint256 _amountBabz) public;
  function downTick(uint256 _pos, uint256 _now) public;
  function createDownRequest(address _owner, uint256 _amountPower) public;
}
