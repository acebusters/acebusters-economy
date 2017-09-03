const Nutz = artifacts.require('./satelites/Nutz.sol');
const Power = artifacts.require('./satelites/Power.sol');
const Storage = artifacts.require('./satelites/Storage.sol');
const PullPayment = artifacts.require('./satelites/PullPayment.sol');
const MockController = artifacts.require('./helpers/MockController.sol');
const UpgradeEvent = artifacts.require('./policies/UpgradeEvent.sol');
const BigNumber = require('bignumber.js');
const INFINITY = '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';
const NTZ_DECIMALS = new BigNumber(10).pow(12);
const babz = (ntz) => new BigNumber(NTZ_DECIMALS).mul(ntz);
const ONE_ETH = web3.toWei(1, 'ether');

contract('UpgradeEvent', (accounts) => {
  let controller;
  let nutz;
  let storage;
  let pull;
  let power;

  beforeEach(async () => {
    nutz = await Nutz.new();
    power = await Power.new();
    storage = await Storage.new();
    pull = await PullPayment.new();
    controller = await MockController.new(power.address, pull.address, nutz.address, storage.address);
    nutz.transferOwnership(controller.address);
    power.transferOwnership(controller.address);
    storage.transferOwnership(controller.address);
    pull.transferOwnership(controller.address);
    await controller.unpause();
  });

  it('should allow upgrade controller', async () => {
    // create token contract
    const ceiling = new BigNumber(30000);
    await controller.moveFloor(INFINITY);
    await controller.moveCeiling(ceiling);
    // purchase some tokens with ether
    await nutz.purchase(ceiling, {from: accounts[0], value: ONE_ETH });
    // check balance, supply and reserve
    const babzBalBefore = await nutz.balanceOf.call(accounts[0]);
    assert.equal(babzBalBefore.toNumber(), ceiling.mul(NTZ_DECIMALS).toNumber(), 'token wasn\'t issued to account');

    // upgrade controller contract
    const nextController = await MockController.new(power.address, pull.address, nutz.address, storage.address);
    const event1 = await UpgradeEvent.new(controller.address, nextController.address);
    await nextController.addAdmin(event1.address);
    await controller.addAdmin(event1.address);
    await controller.pause();
    await event1.tick();
    await event1.tick();
    // check balance with next controller
    const babzBalAfter = await nutz.balanceOf.call(accounts[0]);
    assert.equal(babzBalAfter.toNumber(), ceiling.mul(NTZ_DECIMALS).toNumber(), 'token wasn\'t issued to account');
    // check eth migrated
    const reserveWei = web3.eth.getBalance(nextController.address);
    assert.equal(reserveWei.toNumber(), ONE_ETH, 'ether wasn\'t sent to contract');
    // check transfers with next controller
    await nutz.transfer(accounts[1], babzBalAfter);
    const babzBalEnd = await nutz.balanceOf.call(accounts[0]);
    assert.equal(babzBalEnd.toNumber(), 0, 'transfer failed after upgrade');
  });

  it('should allow to recover from emergency');

});
