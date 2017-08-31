pragma solidity 0.4.11;

library PowerDownRequestLib {

  // code used to denote DownRequest when packing into bytes
  // see #packToUint
  uint8 constant DOWN_REQUEST_CODE = 53;

  // data structure for withdrawals
  struct DownRequest {
    uint256 total;
    uint256 left;
    uint256 start;
  }

  // Pack DownRequest struct into 32 bytes uint
  //
  // Package structure:
  // [< 7 bytes - DownRequest#start >< 12 bytes - DownRequest#left >< 12 bytes - DownRequest#total >< 1 byte - request code >]
  //
  // Last byte denotes the type of the request and serves as a poor man's format specification
  function packToUint(DownRequest _dr) returns (uint) {
    return DOWN_REQUEST_CODE
           + (_dr.total << 8)
           + (_dr.left << (96 + 8))
           + (_dr.start << (96 + 96 + 8));
  }

  // Unpack DownRequest struct from 32 byte uint.
  // See #packToUint for packing structure.
  function unpackFromUint(uint rawBytes) returns (DownRequest) {
    require(uint8(rawBytes) == DOWN_REQUEST_CODE);
    return DownRequest(
        uint96(rawBytes >> (8)),
        uint96(rawBytes >> (8 + 96)),
        uint96(rawBytes >> (8 + 96 + 96))
    );
  }

  /*
  * For public API return only 10 down requests, cause
  * we cannot return dynamic array from public function.
  *
  * Number of requests (10) is arbitrary, feel free to adjust.
  *
  * Returns:
  * - an array of requests
  * - an index of the next free position in the array. If all the positions are filled up, returns -1.
  */
  function unpackRequestList(uint[10] _packedRequests) returns (DownRequest[10], int) {
    DownRequest[10] memory requests;
    int freePos = -1;
    for (uint i = 0; i < _packedRequests.length; i++) {
      uint packedRequest = _packedRequests[i];
      if (packedRequest == 0) {
        freePos = i;
        break;
      }
      requests[i] = unpackFromUint(packedRequest);
    }
    return (requests, freePos);
  }

  // unwraps array of uint-packed DownRequests into the array of array[3], so
  // that it could be returned to external caller.
  // It is not possible to return DownRequest from the public function
  function unpackRequestListForPublic(uint[10] _packedRequests) returns (uint[10][3], int) {
    uint[10][3] memory requests;
    int freePos = -1;
    for (uint i = 0; i < _packedRequests.length; i++) {
      uint packedRequest = _packedRequests[i];
      if (packedRequest == 0) {
        freePos = i;
        break;
      }
      DownRequest memory request = unpackFromUint(packedRequest);
      requests[i][0] = request.total;
      requests[i][1] = request.left;
      requests[i][2] = request.start;
    }
    return (requests, freePos);
  }

}
