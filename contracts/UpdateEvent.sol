pragma solidity 0.4.11;

import './Controller.sol';
import "./SafeMath.sol";

contract UpdateEvent {
  using SafeMath for uint;

  // 1. deploy new controller
  // 2. verify code of controller
  // 3. if not paused, pause old controller
  // 4. transfer ownership of storage to here
  // 5. if necessary, correct storage data
  // 6. transfer ownership of storage to new controller
  // 7. transfer ownership of Nutz/Power contracts to new controller
  // 8. if intended, transfer ownership of pull payment account
  // 9. if pullPayment not transfered, kill, sending all eth to council multi-sig
  // 10. kill old controller, sending all ETH to new controller
  // 11. resume new controller
  // 12. remove this from admin access list
}
