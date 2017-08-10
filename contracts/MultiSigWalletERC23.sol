pragma solidity 0.4.11;

import "./MultiSigWallet.sol";

/// @title MultiSigWalletERC23 wallet ERC23 friendly - Allows transfers of ERC23 tokens.
/// @author Klaus Hott - <klaus@blockchainlabsnz.com>
/// @author Stefan George - <stefan.george@consensys.net>
contract MultiSigWalletERC23 is MultiSigWallet {

  event TokenReceived(
    address indexed tokenAddress,
    address indexed sender,
    uint value,
    bytes data
  );

  /*
   * Public functions
   */
  /// @dev Contract constructor sets initial owners and required number of confirmations.
  /// @param _owners List of initial owners.
  /// @param _required Number of required confirmations.
  function MultiSigWalletERC23(address[] _owners, uint _required)
      public
      MultiSigWallet(_owners, _required)
  {
  }

  /// @dev Allows verified creation of multisignature wallet.
  /// @param _from Address who initiated this token transaction (analogue of msg.sender)
  /// @param _value Number of tokens that were sent (analogue of msg.value)
  /// @param _data Data of token transaction (analogue of msg.data)
  function tokenFallback(address _from, uint _value, bytes _data) {
    TokenReceived(msg.sender, _from, _value, _data);
  }
}