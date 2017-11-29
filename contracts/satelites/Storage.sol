pragma solidity ^0.4.11;

import "../ownership/Ownable.sol";


contract Storage is Ownable {
    struct Crate {
        mapping(bytes32 => uint256) uints;
        mapping(bytes32 => address) addresses;
        mapping(bytes32 => bool) bools;
        mapping(address => uint256) bals;
    }

    mapping(bytes32 => Crate) internal crates;

    function setUInt(bytes32 _crate, bytes32 _key, uint256 _value) external onlyOwner {
        crates[_crate].uints[_key] = _value;
    }

    function setAddress(bytes32 _crate, bytes32 _key, address _value) external onlyOwner {
        crates[_crate].addresses[_key] = _value;
    }
 
    function setBool(bytes32 _crate, bytes32 _key, bool _value) external onlyOwner {
        crates[_crate].bools[_key] = _value;
    }
  
    function setBal(bytes32 _crate, address _key, uint256 _value) external onlyOwner {
        crates[_crate].bals[_key] = _value;
    }

    function getUInt(bytes32 _crate, bytes32 _key) public constant returns(uint256) {
        return crates[_crate].uints[_key];
    }

    function getAddress(bytes32 _crate, bytes32 _key) public constant returns(address) {
        return crates[_crate].addresses[_key];
    }

    function getBool(bytes32 _crate, bytes32 _key) public constant returns(bool) {
        return crates[_crate].bools[_key];
    }

    function getBal(bytes32 _crate, address _key) public constant returns(uint256) {
        return crates[_crate].bals[_key];
    }

}
