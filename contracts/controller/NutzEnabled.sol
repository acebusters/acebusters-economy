pragma solidity 0.4.11;

import "../SafeMath.sol";
import "./StorageEnabled.sol";
import "../Pausable.sol";

contract NutzEnabled is Pausable, StorageEnabled {
  using SafeMath for uint;

  // satelite contract addresses
  address public nutzAddr;


  modifier onlyNutz() {
    require(msg.sender == nutzAddr);
    _;
  }

  function NutzEnabled(address _nutzAddr, address _storageAddr)
    StorageEnabled(_storageAddr) {
    nutzAddr = _nutzAddr;
  }

  // this flag allows or denies deposits of NTZ into non-contract accounts
  bool public onlyContractHolders;

  function setOnlyContractHolders(bool _onlyContractHolders) public onlyAdmins {
    onlyContractHolders = _onlyContractHolders;
  }

  // ############################################
  // ########### NUTZ FUNCTIONS  ################
  // ############################################

  // total supply
  function totalSupply() constant returns (uint256) {
    return activeSupply().add(powerPool()).add(burnPool());
  }

  // allowances according to ERC20
  // not written to storage, as not very critical
  mapping (address => mapping (address => uint)) internal allowed;

  function allowance(address _owner, address _spender) constant returns (uint256) {
    return allowed[_owner][_spender];
  }

  function approve(address _owner, address _spender, uint256 _amountBabz) public onlyNutz whenNotPaused {
    require(_owner != _spender);
    allowed[_owner][_spender] = _amountBabz;
  }

  // assumption that params have allready be sanity checked:
  // require(_from != _to)
  // require(_from != powerAddr)
  function _transfer(address _from, address _to, uint256 _amountBabz, bytes _data) internal {
    require(_to != address(this));
    require(_to != address(0x0));
    require(_amountBabz > 0);
    _setBabzBalanceOf(_from, babzBalanceOf(_from).sub(_amountBabz));
    _setBabzBalanceOf(_to, babzBalanceOf(_to).add(_amountBabz));
  }

  function transfer(address _from, address _to, uint256 _amountBabz, bytes _data) public onlyNutz whenNotPaused returns (bool) {
    _transfer(_from, _to, _amountBabz, _data);
    return onlyContractHolders;
  }

  function transferFrom(address _sender, address _from, address _to, uint256 _amountBabz, bytes _data) public onlyNutz whenNotPaused returns (bool) {
    require(_from != _to);
    allowed[_from][_sender] = allowed[_from][_sender].sub(_amountBabz);
    _transfer(_from, _to, _amountBabz, _data);
    return onlyContractHolders;
  }

}
