pragma solidity ^0.4.11;


contract ControllerInterface {


    // State Variables
    bool public paused;
    address public nutzAddr;

    // Nutz functions
    function babzBalanceOf(address _owner) public constant returns (uint256);
    function activeSupply() public constant returns (uint256);
    function burnPool() public constant returns (uint256);
    function powerPool() public constant returns (uint256);
    function totalSupply() public constant returns (uint256);
    function completeSupply() public constant returns (uint256);
    function allowance(address _owner, address _spender) public constant returns (uint256);

    function approve(address _owner, address _spender, uint256 _amountBabz) public;
    function transfer(address _from, address _to, uint256 _amountBabz, bytes _data) public;
    function transferFrom(address _sender, address _from, address _to, uint256 _amountBabz, bytes _data) public;

    // Market functions
    function floor() public constant returns (uint256);
    function ceiling() public constant returns (uint256);

    function purchase(address _sender, uint256 _value, uint256 _price) public returns (uint256);
    function sell(address _from, uint256 _price, uint256 _amountBabz) public;

    // Power functions
    function powerBalanceOf(address _owner) public constant returns (uint256);
    function outstandingPower() public constant returns (uint256);
    function authorizedPower() public constant returns (uint256);
    function powerTotalSupply() public constant returns (uint256);

    function powerUp(address _sender, address _from, uint256 _amountBabz) public;
    function downTick(address _owner, uint256 _now) public;
    function createDownRequest(address _owner, uint256 _amountPower) public;
    function downs(address _owner) public constant returns(uint256, uint256, uint256);
    function downtime() public constant returns (uint256);
}
