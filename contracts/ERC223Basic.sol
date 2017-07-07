pragma solidity ^0.4.11;

import './ERC20Basic.sol';

contract ERC223Basic is ERC20Basic {
    function transData(address to, uint value, bytes32 data) returns (bool);
}