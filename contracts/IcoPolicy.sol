pragma solidity ^0.4.11;

import "./SafeMath.sol";
import "./ERC20.sol";
import "./Power.sol";
import "./Nutz.sol";
import "./ERC223ReceivingContract.sol";


contract IcoPolicy {
    uint256 minRaise;
    uint256 maxRaise;
    uint256 minDuration; 
    uint256 maxDuration;
    address milestoneAdr;
    uint256 startTime;
    bool started;
    uint256 ntzAddr;

    function IcoPolicy( uint256 _minRaise,
                        uint256 _maxRaise, 
                        uint256 _minDuration, 
                        uint256 _maxDuration, 
                        address _milestoneAdr,
                        uint256 _startTime,
                        address _ntzAddr) {
            minRaise = _minRaise;
            maxRaise = _maxRaise;
            minDuration = _minDuration;
            maxDuration = _maxDuration;
            milestoneAdr = _milestoneAdr;
            startTime = _startTime;
            started = false;
            ntzAddr = _ntzAddr;
    }

    

    function tick() {
        var nutzContract = Nutz(ntzAddr);
        uint256 raised = nutzContract.balanceOf(ntzAddr); // ??
        // check if funding goal reached
        if (!ended && icoEnded(raised)) {
            var totalSupply = nutzContract.totalSupply();
            ended = true;
            nutzContract.moveCeiling(REGULAR_PRICE);
            nutzContract.dilutePower(totalSupply);
        }

        if (!started && now >= _startTime) {
            started = true;
            nutzContract.moveCeiling(DISCOUNT_PRICE);
        }

        // check if milestone is reached an allocate funds for founders
    }

    function icoEnded(uint256 funded) returns (bool) {
        // maybe more conditions
        return (now - startTime >= maxDuration || funded >= maxRaise) 
    }

    function icoStarted(uint256 funded) returns (bool) {
        return (now >= _startTime) 
    }

    function mileStonePayout() {

    }
}