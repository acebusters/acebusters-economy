pragma solidity 0.4.11;

import "../satelites/Power.sol";
import "../satelites/Nutz.sol";
import "./MarketEnabled.sol";

contract PowerEnabled is MarketEnabled {

  // satelite contract addresses
  address public powerAddr;

  // maxPower is a limit of total power that can be outstanding
  // maxPower has a valid value between outstandingPower and authorizedPow/2
  uint256 public maxPower = 0;

  // time it should take to power down
  uint256 public downtime;

  // data structure for withdrawals
  struct DownRequest {
    address owner;
    uint256 total;
    uint256 left;
    uint256 start;
  }
  DownRequest[] public downs;

  modifier onlyPower() {
    require(msg.sender == powerAddr);
    _;
  }

  function PowerEnabled(address _powerAddr, address _pullAddr, address _storageAddr, address _nutzAddr)
    MarketEnabled(_pullAddr, _nutzAddr, _storageAddr) {
    powerAddr = _powerAddr;
  }

  function setMaxPower(uint256 _maxPower) public onlyAdmins {
    require(outstandingPower() <= _maxPower && _maxPower < authorizedPower());
    maxPower = _maxPower;
  }

  function setDowntime(uint256 _downtime) public onlyAdmins {
    downtime = _downtime;
  }

  // this is called when NTZ are deposited into the burn pool
  function dilutePower(uint256 _amountBabz) public onlyAdmins {
    uint256 authorizedPow = authorizedPower();
    if (authorizedPow == 0) {
      // during the first capital increase, set some big number as authorized shares
      _setAuthorizedPower(totalSupply().add(_amountBabz));
    } else {
      uint256 totalBabz = totalSupply();
      // in later increases, expand authorized shares at same rate like economy
      _setAuthorizedPower(authorizedPow.mul(totalBabz.add(_amountBabz)).div(totalBabz));
    }
    _setBurnPool(burnPool().add(_amountBabz));
  }

  function _slashPower(address _holder, uint256 _value, bytes32 _data) internal {
    uint256 previouslyOutstanding = outstandingPower();
    _setOutstandingPower(previouslyOutstanding.sub(_value));
    // adjust size of power pool
    uint256 powPool = powerPool();
    uint256 slashingBabz = _value.mul(powPool).div(previouslyOutstanding);
    _setPowerPool(powPool.sub(slashingBabz));
    // put event into satelite contract
    Power(powerAddr).slashPower(_holder, _value, _data);
  }

  function slashPower(address _holder, uint256 _value, bytes32 _data) public onlyAdmins {
    _setPowerBalanceOf(_holder, powerBalanceOf(_holder).sub(_value));
    _slashPower(_holder, _value, _data);
  }

  function slashDownRequest(uint256 _pos, address _holder, uint256 _value, bytes32 _data) public onlyAdmins {
    DownRequest storage req = downs[_pos];
    require(req.owner == _holder);
    req.left = req.left.sub(_value);
    _slashPower(_holder, _value, _data);
  }

  // this is called when NTZ are deposited into the power pool
  function powerUp(address _sender, address _from, uint256 _amountBabz) public onlyNutz whenNotPaused {
    uint256 authorizedPow = authorizedPower();
    require(authorizedPow != 0);
    require(_amountBabz != 0);
    uint256 totalBabz = totalSupply();
    require(totalBabz != 0);
    uint256 amountPow = _amountBabz.mul(authorizedPow).div(totalBabz);
    // check pow limits
    uint256 outstandingPow = outstandingPower();
    require(outstandingPow.add(amountPow) <= maxPower);

    if (_sender != _from) {
      allowed[_from][_sender] = allowed[_from][_sender].sub(_amountBabz);
    }

    _setOutstandingPower(outstandingPow.add(amountPow));

    uint256 powBal = powerBalanceOf(_from).add(amountPow);
    require(powBal >= authorizedPow.div(10000)); // minShare = 10000
    _setPowerBalanceOf(_from, powBal);
    _setActiveSupply(activeSupply().sub(_amountBabz));
    _setBabzBalanceOf(_from, babzBalanceOf(_from).sub(_amountBabz));
    _setPowerPool(powerPool().add(_amountBabz));
    Power(powerAddr).powerUp(_from, amountPow);
  }

  function powerTotalSupply() constant returns (uint256) {
    uint256 issuedPower = authorizedPower().div(2);
    // return max of maxPower or issuedPower
    return maxPower >= issuedPower ? maxPower : issuedPower;
  }

  function vestedDown(uint256 _pos, uint256 _now) constant returns (uint256) {
    if (downs.length <= _pos) {
      return 0;
    }
    if (_now <= downs[_pos].start) {
      return 0;
    }
    // calculate amountVested
    // amountVested is amount that can be withdrawn according to time passed
    DownRequest storage req = downs[_pos];
    uint256 timePassed = _now.sub(req.start);
    if (timePassed > downtime) {
     timePassed = downtime;
    }
    uint256 amountVested = req.total.mul(timePassed).div(downtime);
    uint256 amountFrozen = req.total.sub(amountVested);
    if (req.left <= amountFrozen) {
      return 0;
    }
    return req.left.sub(amountFrozen);
  }

  function createDownRequest(address _owner, uint256 _amountPower) public onlyPower whenNotPaused {
    // prevent powering down tiny amounts
    // when powering down, at least totalSupply/minShare Power should be claimed
    require(_amountPower >= authorizedPower().div(10000)); // minShare = 10000;
    _setPowerBalanceOf(_owner, powerBalanceOf(_owner).sub(_amountPower));
    uint256 pos = downs.length++;
    downs[pos] = DownRequest(_owner, _amountPower, _amountPower, now);
  }

  // executes a powerdown request
  function downTick(uint256 _pos, uint256 _now) public onlyPower whenNotPaused {
    uint256 amountPow = vestedDown(_pos, _now);
    DownRequest storage req = downs[_pos];

    // prevent power down in tiny steps
    uint256 minStep = req.total.div(10);
    require(req.left <= minStep || minStep <= amountPow);

    // calculate token amount representing share of power
    uint256 amountBabz = amountPow.mul(totalSupply()).div(authorizedPower());

    // transfer power and tokens
    _setOutstandingPower(outstandingPower().sub(amountPow));
    req.left = req.left.sub(amountPow);
    _setPowerPool(powerPool().sub(amountBabz));
    _setActiveSupply(activeSupply().add(amountBabz));
    _setBabzBalanceOf(req.owner, babzBalanceOf(req.owner).add(amountBabz));
    Nutz(nutzAddr).powerDown(req.owner, amountBabz);
    bytes memory empty;
    _checkDestination(powerAddr, req.owner, amountBabz, empty);

    // down request completed
    if (req.left == 0) {
      // if not last element, switch with last
      if (_pos < downs.length - 1) {
        downs[_pos] = downs[downs.length - 1];
      }
      // then cut off the tail
      downs.length--;
    }
  }


}
