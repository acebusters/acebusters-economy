pragma solidity ^0.4.11;
import "../../contracts/MultisigWallet.sol";

contract MultisigWalletMock is MultisigWallet {
  uint public totalSpending;

  function MultisigWalletMock(address[] _owners, uint _required)
    MultisigWallet(_owners, _required) payable { }

  function changeOwner(address _from, address _to) external { }

}