pragma solidity ^0.4.11;


import "./ownership/Multisig.sol";
import "./ownership/Shareable.sol";


/**
 * MultisigWallet
 * Usage:
 *     bytes32 h = Wallet(w).from(oneOwner).execute(to, value, data);
 *     Wallet(w).from(anotherOwner).confirm(h);
 */
contract MultisigWallet is Multisig, Shareable {

  struct Transaction {
    address to;
    uint value;
    bytes data;
  }

  /**
   * Constructor, sets the owners addresses, number of approvals required, and daily spending limit
   * @param _owners A list of owners.
   * @param _required The amount required for a transaction to be approved.
   */
  function MultisigWallet(address[] _owners, uint _required) Shareable(_owners, _required) {
    // nothing
  }

  /** 
   * @dev destroys the contract sending everything to `_to`. 
   */
  function destroy(address _to) onlymanyowners(keccak256(msg.data)) external {
    selfdestruct(_to);
  }

  /** 
   * @dev Fallback function, receives value and emits a deposit event. 
   */
  function() payable {
    // just being sent some cash?
    if (msg.value > 0)
      Deposit(msg.sender, msg.value);
  }

  /**
   * @dev Outside-visible transaction entry point. Executes transaction with multisig process.
   * We provide a hash on return to allow the sender to provide shortcuts for the other
   * confirmations (allowing them to avoid replicating the _to, _value, and _data arguments).
   * They still get the option of using them if they want, anyways.
   * @param _to The receiver address
   * @param _value The value to send
   * @param _data The data part of the transaction
   */
  function execute(address _to, uint _value, bytes _data) external onlyOwner returns (bytes32 _r) {
    // determine our operation hash.
    _r = keccak256(msg.data);
    if (!confirm(_r) && txs[_r].to == 0) {
      txs[_r].to = _to;
      txs[_r].value = _value;
      txs[_r].data = _data;
      ConfirmationNeeded(_r, msg.sender, _value, _to, _data);
    }
  }

  /**
   * @dev Confirm a transaction by providing just the hash. We use the previous transactions map, 
   * txs, in order to determine the body of the transaction from the hash provided.
   * @param _h The transaction hash to approve.
   */
  function confirm(bytes32 _h) onlymanyowners(_h) returns (bool) {
    if (txs[_h].to != 0) {
      if (!txs[_h].to.call.value(txs[_h].value)(txs[_h].data)) {
        throw;
      }
      MultiTransact(msg.sender, _h, txs[_h].value, txs[_h].to, txs[_h].data);
      delete txs[_h];
      return true;
    }
  }

  // INTERNAL METHODS
  /** 
   * @dev Clears the list of transactions pending approval.
   */
  function clearPending() internal {
    uint length = pendingsIndex.length;
    for (uint i = 0; i < length; ++i) {
      delete txs[pendingsIndex[i]];
    }
    super.clearPending();
  }


  // FIELDS

  // pending transactions we have at present.
  mapping (bytes32 => Transaction) txs;
}