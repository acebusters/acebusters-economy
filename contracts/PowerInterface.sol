pragma solidity ^0.4.8;

contract PowerInterface {

  function accredit(address _investor);
  function up(address _sender, uint _value, uint _totalSupply) returns (bool);
}