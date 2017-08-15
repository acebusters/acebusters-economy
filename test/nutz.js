const Nutz = artifacts.require('./Nutz.sol');
const Power = artifacts.require('./Power.sol');
const Storage = artifacts.require('./Storage.sol');
const PullPayment = artifacts.require('./PullPayment.sol');
const Controller = artifacts.require('./Controller.sol');
const ERC223ReceiverMock = artifacts.require('./helpers/ERC223ReceiverMock.sol');
const assertJump = require('./helpers/assertJump');
const BigNumber = require('bignumber.js');
require('./helpers/transactionMined.js');
const INFINITY = '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';
const NTZ_DECIMALS = new BigNumber(10).pow(12);
const babz = (ntz) => new BigNumber(NTZ_DECIMALS).mul(ntz);
const PRICE_FACTOR = new BigNumber(10).pow(6);
const ONE_ETH = web3.toWei(1, 'ether');

contract('Nutz', (accounts) => {
  let controller;
  let nutz;
  let storage;
  let pull;

  beforeEach(async () => {
    nutz = await Nutz.new();
    storage = await Storage.new();
    pull = await PullPayment.new();
    controller = await Controller.new(storage.address, nutz.address, '0x00', pull.address, 0);
    nutz.transferOwnership(controller.address);
    storage.transferOwnership(controller.address);
    pull.transferOwnership(controller.address);
  });

  it('should allow to purchase', async () => {
    // create token contract
    const ceiling = new BigNumber(30000);
    await controller.moveCeiling(ceiling);
    // purchase some tokens with ether
    await nutz.purchase({from: accounts[0], value: ONE_ETH });
    // check balance, supply and reserve
    const babzBalance = await nutz.balanceOf.call(accounts[0]);
    assert.equal(babzBalance.toNumber(), ceiling.mul(NTZ_DECIMALS).toNumber(), 'token wasn\'t issued to account');
    const supplyBabz = await nutz.activeSupply.call();
    assert.equal(supplyBabz.toNumber(), ceiling.mul(NTZ_DECIMALS).toNumber(), 'token wasn\'t issued');
    const reserveWei = web3.eth.getBalance(controller.address);
    assert.equal(reserveWei.toNumber(), ONE_ETH, 'ether wasn\'t sent to contract');
  });

  it('should prevent purchase if value 0', async () => {
    // create token contract
    const ceiling = new BigNumber(30000);
    await controller.moveCeiling(ceiling);
    // purchase some tokens with ether
    try {
      await nutz.purchase({from: accounts[0], value: 0 });
      assert.fail('should have thrown before');
    } catch(error) {
      assertJump(error);
    }
  });

  it('should allow to sell', async () => {
    // create contract and purchase tokens for 1 ether
    const ceiling = new BigNumber(1000);
    await controller.moveCeiling(ceiling);
    await controller.moveFloor(ceiling);
    await nutz.purchase({from: accounts[0], value: ONE_ETH });
    let babzBalance = await nutz.balanceOf.call(accounts[0]);
    assert.equal(babzBalance.toNumber(), ceiling.mul(ONE_ETH).div(PRICE_FACTOR).toNumber(), 'token wasn\'t issued to account');
    // sell half of the tokens
    await nutz.sell(babzBalance.div(2));
    // check balance, supply
    let newBabzBal = await nutz.balanceOf.call(accounts[0]);
    assert.equal(newBabzBal.toNumber(), babzBalance.div(2).toNumber(), 'token wasn\'t deducted by sell');
    const supplyBabz = await nutz.activeSupply.call();
    assert.equal(supplyBabz.toNumber(), babzBalance.div(2).toNumber(), 'token wasn\'t destroyed');
    // check allocation and reserve
    let allocationWei = await pull.balanceOf.call(accounts[0]);
    const HALF_ETH = web3.toWei(0.5, 'ether');
    assert.equal(allocationWei.toString(), HALF_ETH, 'ether wasn\'t allocated for withdrawal');
    const reserveWei = web3.eth.getBalance(controller.address);
    assert.equal(reserveWei.toString(), HALF_ETH, 'ether allocation wasn\'t deducted from reserve');
    // pull the ether from the account
    const before = web3.eth.getBalance(accounts[0]);
    await pull.withdraw({ gasPrice: 0 });
    const after = web3.eth.getBalance(accounts[0]);
    assert.equal(after - before, allocationWei.toNumber(), 'allocation wasn\'t payed out.');
  });

  it('should allow to sell with active power pool', async () => {
    const power = await Power.new();
    power.transferOwnership(controller.address);
    await controller.setContracts(storage.address, nutz.address, power.address, pull.address);
    // create contract and purchase tokens for 1 ether
    const ceiling = new BigNumber(1000);
    await controller.moveCeiling(ceiling);
    await controller.moveFloor(ceiling);
    
    await nutz.purchase({from: accounts[0], value: ONE_ETH });

    // initiate power pool
    await controller.dilutePower(0);
    const authorizedPower = await power.totalSupply.call();
    await controller.setMaxPower(authorizedPower);

    // power up some tokens
    let babzBalance = await nutz.balanceOf.call(accounts[0]);
    await nutz.powerUp(babzBalance.div(2));

    const powerPoolBefore = await controller.powerPool.call();
    // sell half of active supply
    await nutz.sell(babzBalance.div(4));

    // check size of power pool after sell
    const powerPoolAfter = await controller.powerPool.call();
    assert.equal(powerPoolBefore.div(2).toNumber(), powerPoolAfter.toNumber(), 'power pool not adjusted on sell');
  });

  describe('#balanceOf()', () => {

    it('should return 0 for power contract address', async () => {
      const power = await Power.new();
      power.transferOwnership(controller.address);
      await controller.setContracts(storage.address, nutz.address, power.address, pull.address);
      // create contract and purchase tokens for 1 ether
      const ceiling = new BigNumber(1000);
      await controller.moveCeiling(ceiling);
      
      await nutz.purchase({from: accounts[0], value: ONE_ETH });

      // initiate power pool
      await controller.dilutePower(0);
      const authorizedPower = await power.totalSupply.call();
      await controller.setMaxPower(authorizedPower);

      // power up some tokens
      const babzBalance = await nutz.balanceOf.call(accounts[0]);
      await nutz.powerUp(babzBalance.div(2));

      // assert balanceOf() should return 0 for power contract address
      const powerBalance = await nutz.balanceOf.call(power.address);
      assert.equal(powerBalance.toNumber(), 0, 'do not expose balance of power pool through ERC20');
    });

  });

  it('setting floor to infinity should disable sell', async () => {
    // create contract and purchase tokens for 1 ether
    const ceiling = new BigNumber(1000);
    await controller.moveCeiling(ceiling);
    await controller.moveFloor(ceiling);

    await nutz.purchase({from: accounts[0], value: ONE_ETH });
    let babzBalance = await nutz.balanceOf.call(accounts[0]);
    assert.equal(babzBalance, babz(1000).toNumber(), 'token wasn\'t issued to account');
    // set floor to infinity
    await controller.moveFloor(INFINITY);
    // try sell half of the tokens
    try {
      await nutz.sell(babzBalance.div(2));
    } catch(error) {
      return assertJump(error);
    }
    assert.fail('should have thrown before');
  });

  it('setting floor to infinity should disable claim', async () => {
    // create contract and purchase tokens for 1 ether
    const ceiling = new BigNumber(1000);
    await controller.moveCeiling(ceiling);
    await controller.moveFloor(ceiling);

    await nutz.purchase({from: accounts[0], value: ONE_ETH });
    let babzBalance = await nutz.balanceOf.call(accounts[0]);
    assert.equal(babzBalance, babz(1000).toNumber(), 'token wasn\'t issued to account');
    // try sell half of the tokens
    await nutz.sell(babzBalance.div(2));
    // set floor to infinity
    await controller.moveFloor(INFINITY);
    try {
      await pull.withdraw({ gasPrice: 0 });
      assert.fail('should have thrown before');
    } catch(error) {
      return assertJump(error);
    }
  });

  it('should call erc223 when purchase', async () => {
    let receiver = await ERC223ReceiverMock.new();
    await controller.moveCeiling(1500);
    await nutz.purchase({from: accounts[0], value: ONE_ETH });
    await receiver.forward(nutz.address, ONE_ETH);
    const isCalled = await receiver.called.call();
    assert(isCalled, 'erc223 interface has not been invoked on purchase');
  });

  it('should allow to disable transfer to non-contract accounts.', async () => {
    await controller.moveCeiling(1500);
    await nutz.purchase({from: accounts[0], value: ONE_ETH });
    const bal = await nutz.balanceOf.call(accounts[0]);
    await controller.setOnlyContractHolders(true);
    try {
      await nutz.transfer(accounts[1], bal.div(2), "0x00");
    } catch(error) {
      return assertJump(error);
    }
    assert.fail('should have thrown before');
  });

  it('should adjust getFloor automatically when active supply inflated', async () => {
    // create token contract, and issue some tokens that are not backed by ETH
    //const token = await NutzMock.new(0, babz(12000), 12000, 15000);
    // purchase some tokens with ether
    await nutz.purchase({from: accounts[0], value: ONE_ETH });
    
    const bal = await nutz.balanceOf.call(accounts[0]);
    // sell more tokens than issued by eth
    await nutz.sell(bal);
    const reserve = web3.eth.getBalance(controller.address);
    assert.equal(reserve.toNumber(), 0, 'reserve has not been emptied');
  });

  it('allocate_funds_to_beneficiary and claim_revenue', async () => {
    // create token contract, default ceiling == floor
    const ceiling = new BigNumber(1500);
    await controller.moveCeiling(ceiling);
    await controller.moveFloor(ceiling.mul(2));
    // purchase NTZ for 1 ETH
    await nutz.purchase({from: accounts[0], value: ONE_ETH });
    const floor = await controller.floor.call();
    const reserveWei = web3.eth.getBalance(controller.address);
    assert.equal(reserveWei.toNumber(), ONE_ETH, 'reserve incorrect');
    const babzBalance = await nutz.balanceOf.call(accounts[0]);
    assert.equal(babzBalance.toNumber(), ceiling.mul(ONE_ETH).div(PRICE_FACTOR).toNumber(), 'token wasn\'t issued to account');

    const revenueWei = new BigNumber(ONE_ETH).minus(babzBalance.div(floor).mul(PRICE_FACTOR));
    await controller.allocateEther(revenueWei, accounts[1]);
    let allocatedWei = await pull.balanceOf(accounts[1]);
    assert.equal(allocatedWei.toNumber(), revenueWei.toNumber(), 'ether wasn\'t allocated to beneficiary');
    // pull the ether from the account
    const before = web3.eth.getBalance(accounts[1]);
    await pull.withdraw({ from: accounts[1], gasPrice: 0 });
    const after = web3.eth.getBalance(accounts[1]);
    assert.equal(after - before, allocatedWei.toNumber(), 'allocation wasn\'t payed out.');
  });

  it('should handle The sale administrator sets floor = infinity, ceiling = 0', async () => {
    // create token contract, default ceiling == floor
    let ceiling = new BigNumber(100);
    await controller.moveCeiling(ceiling);
    await nutz.purchase({from: accounts[0], value: ONE_ETH });
    const babzBalanceBefore = await nutz.balanceOf.call(accounts[0]);
    assert.equal(babzBalanceBefore.toNumber(), ceiling.mul(ONE_ETH).div(PRICE_FACTOR).toNumber(), 'token wasn\'t issued to account');
    await controller.moveFloor(INFINITY);
    const floor = await controller.floor.call();
    await controller.moveCeiling(0);
    ceiling = await controller.ceiling.call();
    assert.equal(floor.toNumber(), INFINITY, 'setting floor failed');
    assert.equal(ceiling.toNumber(), 0, 'setting ceiling failed');
    // try purchasing some tokens with ether
    try {
      await nutz.purchase({from: accounts[0], value: ONE_ETH });
      assert.fail('should have thrown before');
    } catch(error) {
      assertJump(error);
      // check balance, supply and reserve
      const babzBalanceAfter = await nutz.balanceOf.call(accounts[0]);
      assert.equal(babzBalanceAfter.toNumber(), babzBalanceBefore, 'balance should stay same after failed purchase');
      const supplyBabz = await nutz.activeSupply.call();
      assert.equal(supplyBabz.toNumber(), babzBalanceBefore, 'activeSupply should stay same after failed purchase');
      const reserveWei = web3.eth.getBalance(controller.address);
      assert.equal(reserveWei.toNumber(), ONE_ETH, 'ether should not have been deposited');
    }
  });

  it('the sale administrator can’t raise the floor price if doing so would make it unable to purchase all of the tokens at the floor price', async () => {
    // create contract and buy some tokens
    let ceiling = new BigNumber(4000);
    await controller.moveCeiling(ceiling);
    await nutz.purchase({from: accounts[0], value: ONE_ETH });
    let supplyBabz = await nutz.activeSupply.call(accounts[0]);
    const reserveWei = web3.eth.getBalance(controller.address);
    assert.equal(supplyBabz.toNumber(), ceiling.mul(ONE_ETH).div(PRICE_FACTOR).toNumber(), 'amount wasn\'t issued to account');
    // move ceiling so we can move floor
    await controller.moveCeiling(2000);
    ceiling = await controller.ceiling.call();
    assert.equal(ceiling.toNumber(), 2000, 'setting ceiling failed');

    // move floor should fail, because reserve exceeded
    try {
      await controller.moveFloor(2000);
      assert.fail('should have thrown before');
    } catch(error) {
      assertJump(error);
    }
    
  });

  it('allocate_funds_to_beneficiary fails if allocating those funds would mean that the sale mechanism is no longer able to buy back all outstanding tokens',  async () => {
    // create token contract, default ceiling == floor
    const ceiling = new BigNumber(1500);
    await controller.moveCeiling(ceiling);
    await controller.moveCeiling(2000);

    await nutz.purchase({from: accounts[0], value: ONE_ETH });
    const floor = await controller.floor.call();
    const reserveWei = web3.eth.getBalance(controller.address);
    assert.equal(reserveWei.toNumber(), ONE_ETH, 'reserve incorrect');
    const babzBalance = await nutz.balanceOf.call(accounts[0]);
    assert.equal(babzBalance.toNumber(), ceiling.mul(ONE_ETH).div(PRICE_FACTOR).toNumber(), 'token wasn\'t issued to account');

    const revenueWei = new BigNumber(ONE_ETH).minus(babzBalance.times(floor));
    const doublerevenueWei = revenueWei.times(2);
    try {
      await controller.allocateEther(doublerevenueWei, accounts[1]);
      assert.fail('should have thrown before');
    } catch(error) {
      assertJump(error);
    }
  });

  it('should return correct balances after transfer', async () => {
    // create contract and buy some tokens
    const ceiling = new BigNumber(100);
    await controller.moveCeiling(ceiling);
    await nutz.purchase({from: accounts[0], value: ONE_ETH });
    let babzBalance = await nutz.balanceOf.call(accounts[0]);
    assert.equal(babzBalance.toNumber(), ceiling.mul(ONE_ETH).div(PRICE_FACTOR).toNumber(), 'amount wasn\'t issued to account');
    // transfer token to other account
    const halfbabzBalance = babzBalance.dividedBy(2);
    let transfer = await nutz.transfer(accounts[1], halfbabzBalance, "0x00");

    // check balances of sender and recepient
    const newbabzBalance = await nutz.balanceOf(accounts[0]);
    assert.equal(newbabzBalance.toNumber(), halfbabzBalance.toNumber(), 'amount hasn\'t been transfered');
    babzBalance = await nutz.balanceOf(accounts[1]);
    assert.equal(babzBalance.toNumber(), halfbabzBalance.toNumber(), 'amount hasn\'t been received');
  });

  it('should throw an error when trying to transfer more than balance', async function() {
    try {
      await nutz.transfer(accounts[1], 101, "0x00");
      assert.fail('should have thrown before');
    } catch(error) {
      assertJump(error);
    }
  });

});
