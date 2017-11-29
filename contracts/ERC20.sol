pragma solidity ^0.4.11;


import "./ERC223Basic.sol";


/*
 * ERC20 interface
 * see https://github.com/ethereum/EIPs/issues/20
 */
contract ERC20 is ERC223Basic {
    // active supply of tokens
    function activeSupply() public constant returns (uint256);
    function allowance(address _owner, address _spender) public constant returns (uint256);
    function transferFrom(address _from, address _to, uint _value) public returns (bool);
    function approve(address _spender, uint256 _value) public;
    event Approval(address indexed owner, address indexed spender, uint256 value);
}
