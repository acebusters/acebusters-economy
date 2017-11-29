pragma solidity ^0.4.11;

import "../../contracts/controller/Controller.sol";


contract MockController is Controller {

    function MockController(address _powerAddr, address _pullAddr, address _nutzAddr, address _storageAddr)
        Controller(_powerAddr, _pullAddr, _nutzAddr, _storageAddr) {
    }

    function inflateActiveSupply(uint256 _extraSupply) public {
        _setActiveSupply(activeSupply().add(_extraSupply));
    }

    function ethBalance() public returns (uint256) {
        return this.balance;
    }

    function sell(address _from, uint256 _price, uint256 _amountBabz) public onlyNutz whenNotPaused {
        uint256 effectiveFloor = floor();
        require(_amountBabz != 0);
        require(effectiveFloor != INFINITY);
        require(_price == effectiveFloor);

        uint256 amountWei = _amountBabz.mul(1000000).div(effectiveFloor);  // 1,000,000 WEI, used as price factor
        require(amountWei > 0);
        // make sure power pool shrinks proportional to economy
        uint256 powPool = powerPool();
        uint256 activeSup = activeSupply();
        if (powPool > 0) {
            uint256 powerShare = powPool.mul(_amountBabz).div(activeSup);
            _setPowerPool(powPool.sub(powerShare));
        }
        _setActiveSupply(activeSup.sub(_amountBabz));
        _setBabzBalanceOf(_from, babzBalanceOf(_from).sub(_amountBabz));
        Nutz(nutzAddr).asyncSend(pullAddr, _from, amountWei);
    }

}
