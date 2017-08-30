const Nutz = artifacts.require('./satelites/Nutz.sol');
const Power = artifacts.require('./satelites/Power.sol');
const Storage = artifacts.require('./satelites/Storage.sol');
const PullPayment = artifacts.require('./satelites/PullPayment.sol');
const Controller = artifacts.require('./controller/Controller.sol');
const PowerEvent = artifacts.require('./policies/PowerEvent.sol');
const assertJump = require('./helpers/assertJump');
const BigNumber = require('bignumber.js');
require('./helpers/transactionMined.js');
const INFINITY = '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';
const NTZ_DECIMALS = new BigNumber(10).pow(12);
const babz = (ntz) => new BigNumber(NTZ_DECIMALS).mul(ntz);
const WEI_AMOUNT = web3.toWei(0.001, 'ether');
const CEILING_PRICE = 20000;

contract('PowerEvent', (accounts) => {
  let controller;

  it('should allow to execute event through policy', async () => {
    const nutz = await Nutz.new();
    const power = await Power.new();
    const storage = await Storage.new();
    const pull = await PullPayment.new();
    controller = await Controller.new(power.address, pull.address, nutz.address, storage.address);
    nutz.transferOwnership(controller.address);
    power.transferOwnership(controller.address);
    storage.transferOwnership(controller.address);
    pull.transferOwnership(controller.address);
    await controller.unpause();
    await controller.moveFloor(INFINITY);
    await controller.moveCeiling(CEILING_PRICE);
    await controller.setOnlyContractHolders(false);


    // prepare event #1
    const FOUNDERS = accounts[1];
    const startTime = (Date.now() / 1000 | 0) - 60;
    const minDuration = 0;
    const maxDuration = 3600;
    const softCap = WEI_AMOUNT;
    const hardCap = WEI_AMOUNT;
    const discountRate = 60000000000; // make ceiling 1,200,000,000
    const milestoneRecipients = [];
    const milestoneShares = [];
    const event1 = await PowerEvent.new(controller.address, startTime, minDuration, maxDuration, softCap, hardCap, discountRate, milestoneRecipients, milestoneShares);
    await controller.addAdmin(event1.address);
    await event1.tick();
    // event #1 - buyin
    await nutz.purchase(1200000000, {from: FOUNDERS, value: WEI_AMOUNT });
    // event #1 - burn
    await event1.tick();
    await event1.tick();
    // event #1 power up
    await nutz.powerUp(babz(1200000), { from: FOUNDERS });
    const totalPow1 = await power.totalSupply.call();
    const founderPow1 = await power.balanceOf.call(FOUNDERS);
    assert.equal(founderPow1.toNumber(), totalPow1.toNumber());


    // prepare event #2
    const INVESTORS = accounts[2];
    const EXEC_BOARD = accounts[3];
    const GOVERNING_COUNCIL = accounts[4];
    const softCap2 = WEI_AMOUNT * 5000;
    const hardCap2 = WEI_AMOUNT * 30000;
    const discountRate2 = 1500000; // 150% -> make ceiling 30,000
    const milestoneRecipients2 = [EXEC_BOARD, GOVERNING_COUNCIL];
    const milestoneShares2 = [200000, 5000]; // 20% and 0.5%
    const event2 = await PowerEvent.new(controller.address, startTime, minDuration, maxDuration, softCap2, hardCap2, discountRate2, milestoneRecipients2, milestoneShares2);
    // event #2 - buy in
    await controller.addAdmin(event2.address);
    await event2.startCollection();
    await nutz.purchase(30000, {from: INVESTORS, value: hardCap2 });
    // event #2 - burn
    await event2.stopCollection();
    await event2.completeClosed();
    // event #2 - power up
    const investorsBal = await nutz.balanceOf.call(INVESTORS);
    await nutz.powerUp(investorsBal, { from: INVESTORS });
    // event #2 - milestone payment
    await controller.moveFloor(CEILING_PRICE * 2);
    let amountAllocated = await pull.balanceOf.call(EXEC_BOARD);
    assert.equal(amountAllocated.toNumber(), WEI_AMOUNT * 6000, 'ether wasn\'t allocated to beneficiary');

    // check power allocation
    const totalPow = await power.totalSupply.call();
    const founderPow = await power.balanceOf.call(FOUNDERS);
    const investorsPow = await power.balanceOf.call(INVESTORS);
    assert.equal(founderPow.toNumber(), totalPow.mul(0.7).toNumber());
    assert.equal(investorsPow.toNumber(), totalPow.mul(0.3).toNumber());
  });

  it('should not allow to initilialize power event because of milestone length mismatch', async () => {
    const nutz = await Nutz.new();
    const power = await Power.new();
    const storage = await Storage.new();
    const pull = await PullPayment.new();
    controller = await Controller.new(power.address, pull.address, nutz.address, storage.address);
    nutz.transferOwnership(controller.address);
    power.transferOwnership(controller.address);
    storage.transferOwnership(controller.address);
    pull.transferOwnership(controller.address);
    await controller.unpause();
    await controller.moveFloor(INFINITY);
    await controller.moveCeiling(CEILING_PRICE);
    await controller.setOnlyContractHolders(false);


    // prepare event #1
    const FOUNDERS = accounts[1];
    const startTime = (Date.now() / 1000 | 0) - 60;
    const minDuration = 0;
    const maxDuration = 3600;
    const softCap = WEI_AMOUNT;
    const hardCap = WEI_AMOUNT;
    const discountRate = 60000000000; // make ceiling 1,200,000,000
    const milestoneRecipients = [web3.eth.accounts[0], web3.eth.accounts[1]];
    const milestoneShares = [200000];
    try {
      const event1 = await PowerEvent.new(controller.address, startTime, minDuration, maxDuration, softCap, hardCap, discountRate, milestoneRecipients, milestoneShares);
      assert.fail('should have thrown before');
    } catch(error) {
      assertJump(error);
    }
  });

  it('should not allow to initilialize power event because min duration greater than max duration', async () => {
    const nutz = await Nutz.new();
    const power = await Power.new();
    const storage = await Storage.new();
    const pull = await PullPayment.new();
    controller = await Controller.new(power.address, pull.address, nutz.address, storage.address);
    nutz.transferOwnership(controller.address);
    power.transferOwnership(controller.address);
    storage.transferOwnership(controller.address);
    pull.transferOwnership(controller.address);
    await controller.unpause();
    await controller.moveFloor(INFINITY);
    await controller.moveCeiling(CEILING_PRICE);
    await controller.setOnlyContractHolders(false);


    // prepare event #1
    const FOUNDERS = accounts[1];
    const startTime = (Date.now() / 1000 | 0) - 60;
    const minDuration = 3601;
    const maxDuration = 3600;
    const softCap = WEI_AMOUNT;
    const hardCap = WEI_AMOUNT;
    const discountRate = 60000000000; // make ceiling 1,200,000,000
    const milestoneRecipients = [web3.eth.accounts[0], web3.eth.accounts[1]];
    const milestoneShares = [200000, 5000];
    try {
      const event1 = await PowerEvent.new(controller.address, startTime, minDuration, maxDuration, softCap, hardCap, discountRate, milestoneRecipients, milestoneShares);
      assert.fail('should have thrown before');
    } catch(error) {
      assertJump(error);
    }
  });

  it('should not allow to initilialize power event because soft cap greater than hard cap', async () => {
    const nutz = await Nutz.new();
    const power = await Power.new();
    const storage = await Storage.new();
    const pull = await PullPayment.new();
    controller = await Controller.new(power.address, pull.address, nutz.address, storage.address);
    nutz.transferOwnership(controller.address);
    power.transferOwnership(controller.address);
    storage.transferOwnership(controller.address);
    pull.transferOwnership(controller.address);
    await controller.unpause();
    await controller.moveFloor(INFINITY);
    await controller.moveCeiling(CEILING_PRICE);
    await controller.setOnlyContractHolders(false);


    // prepare event #1
    const FOUNDERS = accounts[1];
    const startTime = (Date.now() / 1000 | 0) - 60;
    const minDuration = 0;
    const maxDuration = 3600;
    const softCap = WEI_AMOUNT + 1;
    const hardCap = WEI_AMOUNT;
    const discountRate = 60000000000; // make ceiling 1,200,000,000
    const milestoneRecipients = [web3.eth.accounts[0], web3.eth.accounts[1]];
    const milestoneShares = [200000, 5000];
    try {
      const event1 = await PowerEvent.new(controller.address, startTime, minDuration, maxDuration, softCap, hardCap, discountRate, milestoneRecipients, milestoneShares);
      assert.fail('should have thrown before');
    } catch(error) {
      assertJump(error);
    }
  });

  it('should not allow to initilialize power event because milestoneShare[0] greater than 100%', async () => {
    const nutz = await Nutz.new();
    const power = await Power.new();
    const storage = await Storage.new();
    const pull = await PullPayment.new();
    controller = await Controller.new(power.address, pull.address, nutz.address, storage.address);
    nutz.transferOwnership(controller.address);
    power.transferOwnership(controller.address);
    storage.transferOwnership(controller.address);
    pull.transferOwnership(controller.address);
    await controller.unpause();
    await controller.moveFloor(INFINITY);
    await controller.moveCeiling(CEILING_PRICE);
    await controller.setOnlyContractHolders(false);


    // prepare event #1
    const FOUNDERS = accounts[1];
    const startTime = (Date.now() / 1000 | 0) - 60;
    const minDuration = 0;
    const maxDuration = 3600;
    const softCap = WEI_AMOUNT + 1;
    const hardCap = WEI_AMOUNT;
    const discountRate = 60000000000; // make ceiling 1,200,000,000
    const milestoneRecipients = [web3.eth.accounts[0], web3.eth.accounts[1]];
    const milestoneShares = [1000001, 5000];
    try {
      const event1 = await PowerEvent.new(controller.address, startTime, minDuration, maxDuration, softCap, hardCap, discountRate, milestoneRecipients, milestoneShares);
      assert.fail('should have thrown before');
    } catch(error) {
      assertJump(error);
    }
  });

  it('should not allow to initilialize power event because total share percentage greater than 100%', async () => {
    const nutz = await Nutz.new();
    const power = await Power.new();
    const storage = await Storage.new();
    const pull = await PullPayment.new();
    controller = await Controller.new(power.address, pull.address, nutz.address, storage.address);
    nutz.transferOwnership(controller.address);
    power.transferOwnership(controller.address);
    storage.transferOwnership(controller.address);
    pull.transferOwnership(controller.address);
    await controller.unpause();
    await controller.moveFloor(INFINITY);
    await controller.moveCeiling(CEILING_PRICE);
    await controller.setOnlyContractHolders(false);


    // prepare event #1
    const FOUNDERS = accounts[1];
    const startTime = (Date.now() / 1000 | 0) - 60;
    const minDuration = 0;
    const maxDuration = 3600;
    const softCap = WEI_AMOUNT + 1;
    const hardCap = WEI_AMOUNT;
    const discountRate = 60000000000; // make ceiling 1,200,000,000
    const milestoneRecipients = [web3.eth.accounts[0], web3.eth.accounts[1]];
    const milestoneShares = [600000, 40001];
    try {
      const event1 = await PowerEvent.new(controller.address, startTime, minDuration, maxDuration, softCap, hardCap, discountRate, milestoneRecipients, milestoneShares);
      assert.fail('should have thrown before');
    } catch(error) {
      assertJump(error);
    }
  });

  it('should allow to execute event that fails');

});
