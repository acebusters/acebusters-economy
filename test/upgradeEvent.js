const Nutz = artifacts.require('./satelites/Nutz.sol');
const Power = artifacts.require('./satelites/Power.sol');
const Storage = artifacts.require('./satelites/Storage.sol');
const PullPayment = artifacts.require('./satelites/PullPayment.sol');
const MockController = artifacts.require('./helpers/MockController.sol');
const PowerEvent = artifacts.require('./policies/PowerEvent.sol');
const PowerEventReplacement = artifacts.require('./helpers/MockPowerEventReplacement.sol');
const UpgradeEvent = artifacts.require('./policies/UpgradeEvent.sol');
const UpgradeEventCompact = artifacts.require('./policies/UpgradeEventCompact.sol');
const BigNumber = require('bignumber.js');
const NTZ_DECIMALS = new BigNumber(10).pow(12);
const POW_DECIMALS = new BigNumber(10).pow(12);
const babz = (ntz) => new BigNumber(NTZ_DECIMALS).mul(ntz);
const ONE_ETH = web3.toWei(1, 'ether');
const WEI_AMOUNT = web3.toWei(0.001, 'ether');
const INFINITY = '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';

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
    const reserveWei = web3.eth.getBalance(nutz.address);
    assert.equal(reserveWei.toNumber(), ONE_ETH, 'ether wasn\'t sent to contract');
    // check transfers with next controller
    await nutz.transfer(accounts[1], babzBalAfter);
    const babzBalEnd = await nutz.balanceOf.call(accounts[0]);
    assert.equal(babzBalEnd.toNumber(), 0, 'transfer failed after upgrade');
  });

  it('should allow upgrade controller and PullPayment satellite during Power Event', async () => {

    // set ceiling and floor before Power Event
    const CEILING_PRICE = 20000;
    await controller.moveFloor(INFINITY);
    await controller.moveCeiling(CEILING_PRICE);

    // prepare event #1
    const FOUNDERS = accounts[1];
    const startTime = (Date.now() / 1000 | 0) - 60;
    const minDuration = 0;
    const maxDuration = 3600;
    const softCap = WEI_AMOUNT;
    const hardCap = WEI_AMOUNT;
    const discountRate = 60000000000; // make ceiling 1,200,000,000
    const amountPower = POW_DECIMALS.mul(630000).mul(2);
    const milestoneRecipients = [];
    const milestoneShares = [];
    const event1 = await PowerEvent.new(controller.address, startTime, minDuration, maxDuration, softCap, hardCap, discountRate, amountPower, milestoneRecipients, milestoneShares);
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
    assert.equal(totalPow1.toNumber(), POW_DECIMALS.mul(630000).toNumber());

    // prepare event #2
    const INVESTORS = accounts[2];
    const EXEC_BOARD = accounts[3];
    const GOVERNING_COUNCIL = accounts[4];
    const ceiling = new BigNumber(30000);
    const MIN_NTZ = new BigNumber(30);
    const softCap2 = WEI_AMOUNT * 5000;
    const hardCap2 = WEI_AMOUNT * 30000;
    const etherBalance = WEI_AMOUNT * 99;
    const smallSwapEther = WEI_AMOUNT * 1;
    const discountRate2 = 1500000; // 150% -> make ceiling 30,000
    const milestoneRecipients2 = [EXEC_BOARD, GOVERNING_COUNCIL];
    const milestoneShares2 = [200000, 5000]; // 20% and 0.5%
    const ceilingBeforeEvent2 = await nutz.ceiling.call();
    const event2 = await PowerEvent.new(controller.address, startTime, minDuration, maxDuration, softCap2, hardCap2, discountRate2, 0, milestoneRecipients2, milestoneShares2);
    // event #2 - buy in
    await controller.addAdmin(event2.address);
    await event2.startCollection();
    await nutz.purchase(30000, {from: INVESTORS, value: etherBalance });

    // purchase some tokens with ether
    await nutz.purchase(30000, {from: accounts[0], value: smallSwapEther });

    const nutzBalanceBefore = await web3.eth.getBalance(nutz.address);
    // check balance, supply and reserve
    const babzBalBefore = await nutz.balanceOf.call(accounts[0]);
    assert.equal(babzBalBefore.toNumber(), MIN_NTZ.mul(NTZ_DECIMALS).toNumber(), 'token wasn\'t issued to account');

    // deploy new pull payment contract and set in controller
    const pullNew = await PullPayment.new();
    await pullNew.transferOwnership(controller.address);
    await controller.pause();
    await controller.setContracts(storage.address, nutz.address, power.address, pullNew.address);
    const pullAddrSet = await controller.pullAddr();
    assert.equal(pullAddrSet, pullNew.address, 'New Pull Payment wasn\'t set in controller');
    // remove old Power Event
    await controller.removeAdmin(event2.address);
    // upgrade controller contract
    const nextController = await MockController.new(power.address, pullNew.address, nutz.address, storage.address);
    const upgradeEvent = await UpgradeEvent.new(controller.address, nextController.address);
    await nextController.addAdmin(upgradeEvent.address);
    await controller.addAdmin(upgradeEvent.address);
    await upgradeEvent.tick();
    await upgradeEvent.tick();

    // check balance with next controller
    const babzBalAfter = await nutz.balanceOf.call(accounts[0]);
    assert.equal(babzBalAfter.toNumber(), MIN_NTZ.mul(NTZ_DECIMALS).toNumber(), 'token wasn\'t issued to account');
    // check eth migrated
    const reserveWei = web3.eth.getBalance(nutz.address);
    assert.equal(reserveWei.toNumber(), nutzBalanceBefore, 'ether wasn\'t sent to contract');
    // check transfers with next controller
    await nutz.transfer(INVESTORS, babzBalAfter);
    const babzBalEnd = await nutz.balanceOf.call(accounts[0]);
    assert.equal(babzBalEnd.toNumber(), 0, 'transfer failed after upgrade');

    // prepare replacement event
    const discountRate3 = 1000000; // 100% -> keeping ceiling at 30,000
    const remainingBalance = WEI_AMOUNT * 29900;

    // deploy replacement event
    const eventReplacement = await PowerEventReplacement.new(nextController.address, startTime, minDuration, maxDuration, softCap2, hardCap2, discountRate3, 0, milestoneRecipients2, milestoneShares2);

    // event #replacement - buy in remaining
    await nextController.addAdmin(eventReplacement.address);

    await eventReplacement.startCollection();
    await nutz.purchase(30000, {from: INVESTORS, value: remainingBalance });
    // event #replacement - burn
    await eventReplacement.stopCollection();
    await eventReplacement.completeClosed();
    // event #replacement - power up
    const investorsBal = await nutz.balanceOf.call(INVESTORS);
    await nutz.powerUp(investorsBal, { from: INVESTORS });
    // event #replacement - milestone payment
    await nextController.moveFloor(CEILING_PRICE * 2);
    let amountAllocated = await pullNew.balanceOf.call(EXEC_BOARD);
    assert.equal(amountAllocated.toNumber(), WEI_AMOUNT * 6000, 'ether wasn\'t allocated to beneficiary');

    // check power allocation proper after controller upgrade and replacement Event
    const ceilingAftereEvent2 = await nutz.ceiling.call();
    const totalPow = await power.totalSupply.call();
    const founderPow = await power.balanceOf.call(FOUNDERS);
    const investorsPow = await power.balanceOf.call(INVESTORS);
    assert.equal(ceilingBeforeEvent2.toNumber(), ceilingAftereEvent2.toNumber());
    assert.equal(founderPow.toNumber(), totalPow.mul(0.7).toNumber());
    assert.equal(investorsPow.toNumber(), totalPow.mul(0.3).toNumber());
    assert.equal(totalPow.toNumber(), POW_DECIMALS.mul(900000).toNumber());
  });

  it('should allow compact upgrade to controller in one ATOMIC tick()', async () => {

    // set ceiling and floor before Power Event
    const CEILING_PRICE = 20000;
    await controller.moveFloor(INFINITY);
    await controller.moveCeiling(CEILING_PRICE);

    // prepare event #1
    const FOUNDERS = accounts[1];
    const startTime = (Date.now() / 1000 | 0) - 60;
    const minDuration = 0;
    const maxDuration = 3600;
    const softCap = WEI_AMOUNT;
    const hardCap = WEI_AMOUNT;
    const discountRate = 60000000000; // make ceiling 1,200,000,000
    const amountPower = POW_DECIMALS.mul(630000).mul(2);
    const milestoneRecipients = [];
    const milestoneShares = [];
    const event1 = await PowerEvent.new(controller.address, startTime, minDuration, maxDuration, softCap, hardCap, discountRate, amountPower, milestoneRecipients, milestoneShares);
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
    assert.equal(totalPow1.toNumber(), POW_DECIMALS.mul(630000).toNumber());

    // prepare event #2
    const INVESTORS = accounts[2];
    const EXEC_BOARD = accounts[3];
    const GOVERNING_COUNCIL = accounts[4];
    const ceiling = new BigNumber(30000);
    const MIN_NTZ = new BigNumber(30);
    const softCap2 = WEI_AMOUNT * 5000;
    const hardCap2 = WEI_AMOUNT * 30000;
    const etherBalance = WEI_AMOUNT * 99;
    const smallSwapEther = WEI_AMOUNT * 1;
    const discountRate2 = 1500000; // 150% -> make ceiling 30,000
    const milestoneRecipients2 = [EXEC_BOARD, GOVERNING_COUNCIL];
    const milestoneShares2 = [200000, 5000]; // 20% and 0.5%
    const ceilingBeforeEvent2 = await nutz.ceiling.call();
    const event2 = await PowerEvent.new(controller.address, startTime, minDuration, maxDuration, softCap2, hardCap2, discountRate2, 0, milestoneRecipients2, milestoneShares2);
    // event #2 - buy in
    await controller.addAdmin(event2.address);
    await event2.startCollection();
    await nutz.purchase(30000, {from: INVESTORS, value: etherBalance });

    // purchase some tokens with ether
    await nutz.purchase(30000, {from: accounts[0], value: smallSwapEther });

    const nutzBalanceBefore = await web3.eth.getBalance(nutz.address);
    // check balance, supply and reserve
    const babzBalBefore = await nutz.balanceOf.call(accounts[0]);
    assert.equal(babzBalBefore.toNumber(), MIN_NTZ.mul(NTZ_DECIMALS).toNumber(), 'token wasn\'t issued to account');

    // #START OF THE UPGRADE PROCESS
    const nutzAddrOld = await controller.nutzAddr();
    const nutzSatelliteBalanceBefore = await web3.eth.getBalance(nutzAddrOld);
    // deploy new pull payment and Nutz contract
    const pullNew = await PullPayment.new();
    const nutzNew = await Nutz.new();
    await pullNew.transferOwnership(controller.address);
    await nutzNew.transferOwnership(controller.address);
    // remove old Power Event
    await controller.removeAdmin(event2.address);
    // upgrade controller contract (next controller with new pull payment and new nutz address)
    const nextController = await MockController.new(power.address, pullNew.address, nutzNew.address, storage.address);
    const upgradeEventComppact = await UpgradeEventCompact.new(controller.address, nextController.address, pullNew.address, nutzNew.address);
    await nextController.addAdmin(upgradeEventComppact.address);
    await controller.addAdmin(upgradeEventComppact.address);

    // ATOMIC upgrade
    await upgradeEventComppact.upgrade();

    const pullAddrSet = await nextController.pullAddr();
    assert.equal(pullAddrSet, pullNew.address, 'New Pull Payment wasn\'t set in nextcontroller');

    const nutzAddrSet = await nextController.nutzAddr();
    assert.equal(nutzAddrSet, nutzNew.address, 'New Nutz wasn\'t set in nextcontroller');

    const nutzSatelliteBalanceAfter = await web3.eth.getBalance(nutzAddrSet);
    assert.equal(nutzSatelliteBalanceBefore.toNumber(), nutzSatelliteBalanceAfter.toNumber(), 'Upgrade() didn\'t work properly');

    // check balance with next controller
    const babzBalAfter = await nutzNew.balanceOf.call(accounts[0]);
    assert.equal(babzBalAfter.toNumber(), MIN_NTZ.mul(NTZ_DECIMALS).toNumber(), 'token wasn\'t issued to account');
    // check eth migrated
    const reserveWei = web3.eth.getBalance(nutzNew.address);
    assert.equal(reserveWei.toNumber(), nutzBalanceBefore, 'ether wasn\'t sent to contract');
    // check transfers with next controller
    await nutzNew.transfer(INVESTORS, babzBalAfter);
    const babzBalEnd = await nutzNew.balanceOf.call(accounts[0]);
    assert.equal(babzBalEnd.toNumber(), 0, 'transfer failed after upgrade');

    // prepare replacement event
    const discountRate3 = 1000000; // 100% -> keeping ceiling at 30,000
    const remainingBalance = WEI_AMOUNT * 29900;

    // deploy replacement event
    const eventReplacement = await PowerEventReplacement.new(nextController.address, startTime, minDuration, maxDuration, softCap2, hardCap2, discountRate3, 0, milestoneRecipients2, milestoneShares2);

    // event #replacement - buy in remaining
    await nextController.addAdmin(eventReplacement.address);

    await eventReplacement.startCollection();
    await nutzNew.purchase(30000, {from: INVESTORS, value: remainingBalance });
    // event #replacement - burn
    await eventReplacement.stopCollection();
    await eventReplacement.completeClosed();
    // event #replacement - power up
    const investorsBal = await nutzNew.balanceOf.call(INVESTORS);
    await nutzNew.powerUp(investorsBal, { from: INVESTORS });
    // event #replacement - milestone payment
    await nextController.moveFloor(CEILING_PRICE * 2);
    let amountAllocated = await pullNew.balanceOf.call(EXEC_BOARD);
    assert.equal(amountAllocated.toNumber(), WEI_AMOUNT * 6000, 'ether wasn\'t allocated to beneficiary');

    // check power allocation proper after controller upgrade and replacement Event
    const ceilingAftereEvent2 = await nutzNew.ceiling.call();
    const totalPow = await power.totalSupply.call();
    const founderPow = await power.balanceOf.call(FOUNDERS);
    const investorsPow = await power.balanceOf.call(INVESTORS);
    assert.equal(ceilingBeforeEvent2.toNumber(), ceilingAftereEvent2.toNumber());
    assert.equal(founderPow.toNumber(), totalPow.mul(0.7).toNumber());
    assert.equal(investorsPow.toNumber(), totalPow.mul(0.3).toNumber());
    assert.equal(totalPow.toNumber(), POW_DECIMALS.mul(900000).toNumber());
  });

  it('should allow to recover from emergency');

});
