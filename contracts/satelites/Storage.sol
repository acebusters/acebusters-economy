pragma solidity 0.4.11;

import "../ownership/Ownable.sol";

contract Storage is Ownable {
    struct Crate {
        mapping(bytes32 => uint256) uints;
        mapping(bytes32 => address) addresses;
        mapping(bytes32 => bool) bools;
        mapping(address => uint256) bals;
        mapping(address => uint[10]) requests;
    }

    mapping(bytes32 => Crate) crates;

    function getRequests(bytes32 _crate, address _key) constant returns(uint[10]) {
        return crates[_crate].requests[_key];
    }

    function setRequestValue(bytes32 _crate, address _key, uint _index, uint value) onlyOwner {
      require(_index < 10);
      crates[_crate].requests[_key][_index] = value;
    }

    function setUInt(bytes32 _crate, bytes32 _key, uint256 _value) onlyOwner {
        crates[_crate].uints[_key] = _value;
    }

    function getUInt(bytes32 _crate, bytes32 _key) constant returns(uint256) {
        return crates[_crate].uints[_key];
    }

    function setAddress(bytes32 _crate, bytes32 _key, address _value) onlyOwner {
        crates[_crate].addresses[_key] = _value;
    }

    function getAddress(bytes32 _crate, bytes32 _key) constant returns(address) {
        return crates[_crate].addresses[_key];
    }

    function setBool(bytes32 _crate, bytes32 _key, bool _value) onlyOwner {
        crates[_crate].bools[_key] = _value;
    }

    function getBool(bytes32 _crate, bytes32 _key) constant returns(bool) {
        return crates[_crate].bools[_key];
    }

    function setBal(bytes32 _crate, address _key, uint256 _value) onlyOwner {
        crates[_crate].bals[_key] = _value;
    }

    function getBal(bytes32 _crate, address _key) constant returns(uint256) {
        return crates[_crate].bals[_key];
    }
}
