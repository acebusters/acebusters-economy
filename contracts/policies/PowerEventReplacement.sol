pragma solidity ^0.4.11;

// #ONLY CHANGED startCollection FUNCTION TO ACT AS A REPLACEMENT FOR OLD POWER EVENT

import "../policies/PowerEvent.sol";


contract PowerEventReplacement is PowerEvent {

    // #KEEP ALL THE OTHER PARAMS SAME AS oldPowerEvent
    // except for where *_controllerAddr = _nextControllerAddress, *_discount = 1000000
    function PowerEventReplacement(address _controllerAddr, uint256 _startTime, uint256 _minDuration, uint256 _maxDuration, uint256 _softCap, uint256 _hardCap, uint256 _discount, uint256 _amountPower, address[] _milestoneRecipients, uint256[] _milestoneShares) public
        PowerEvent(_controllerAddr, _startTime, _minDuration, _maxDuration, _softCap, _hardCap, _discount, _amountPower, _milestoneRecipients, _milestoneShares)
        {
            // empty block
        }

    // #CHANGED THIS FUNCTION TO REFLECT OLD PowerEvent VARIABLES
    function startCollection() public isState(EventState.Waiting) {
        // check time
        require(now > startTime);
        // assert(now < startTime.add(minDuration));
        // read initial values
        var contr = Controller(controllerAddr);
        powerAddr = contr.powerAddr();
        nutzAddr = contr.nutzAddr();
        initialSupply = 2399896170149257466012; //initialSupply as per old Power Event
        initialReserve = 22469750000000000000;  // initialReserve as per old Power Event
        // set state
        state = EventState.Collecting;
    }

    function completeClosed() public isState(EventState.Closed) {
        var contr = Controller(controllerAddr);
        // move ceiling
        uint256 newCeiling = 20000;
        contr.moveCeiling(newCeiling);
        // dilute power
        uint256 totalSupply = contr.completeSupply();
        uint256 newSupply = totalSupply.sub(initialSupply);
        contr.dilutePower(newSupply, amountPower);
        // set max power
        var PowerContract = ERC20(powerAddr);
        uint256 authorizedPower = PowerContract.totalSupply();
        contr.setMaxPower(authorizedPower);
        // pay out milestone
        uint256 collected = nutzAddr.balance.sub(initialReserve);
        for (uint256 i = 0; i < milestoneRecipients.length; i++) {
            uint256 payoutAmount = collected.mul(milestoneShares[i]).div(rateFactor);
            contr.allocateEther(payoutAmount, milestoneRecipients[i]);
        }
        // remove access
        contr.removeAdmin(address(this));
        // set state
        state = EventState.Complete;
    }

}
