const Nutz = artifacts.require('./satelites/Nutz.sol');
const Power = artifacts.require('./helpers/PowerMock.sol');
const Storage = artifacts.require('./satelites/Storage.sol');
const PullPayment = artifacts.require('./satelites/PullPayment.sol');
const Controller = artifacts.require('./controller/Controller.sol');
const BigNumber = require('bignumber.js');
require('./helpers/transactionMined.js');
const economy = require('./helpers/economy.js');
const INFINITY = '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';
const NTZ_DECIMALS = new BigNumber(10).pow(12);
const babz = (ntz) => new BigNumber(NTZ_DECIMALS).mul(ntz);
const PRICE_FACTOR = new BigNumber(10).pow(6);
const DOWNTIME = 12*7*24*3600; // 3 month
const WEI_AMOUNT = web3.toWei(1, 'ether');
const CEILING_PRICE = 30000;

contract('Power', (accounts) => {
  let controller;
  let nutz;
  let power;
  let storage;
  let pull;

  beforeEach(async () => {
    nutz = await Nutz.new();
    power = await Power.new();
    storage = await Storage.new();
    pull = await PullPayment.new();
    controller = await Controller.new(power.address, pull.address, nutz.address, storage.address);
    nutz.transferOwnership(controller.address);
    power.transferOwnership(controller.address);
    storage.transferOwnership(controller.address);
    pull.transferOwnership(controller.address);
    await controller.unpause();
  });

  it('should init contract', async () => {
    await controller.dilutePower(10000, 0);
    const authorizedShares = await power.totalSupply.call();
    assert.equal(authorizedShares.toNumber(), 5000, 'shares not authorized');
  });

  it("should allow to power up and power down with no burn.", async () => {
    const ALICE = accounts[0];
    const BOB = accounts[1];
    await controller.moveFloor(INFINITY);
    await controller.moveCeiling(CEILING_PRICE);
    await controller.setDowntime(DOWNTIME);
    // get some NTZ for 1 ETH
    await nutz.purchase(CEILING_PRICE, {from: ALICE, value: WEI_AMOUNT });
    await controller.dilutePower(0, 0);
    const authorizedPower = await power.totalSupply.call();
    await controller.setMaxPower(authorizedPower);
    const babzBalAlice = await nutz.balanceOf.call(ALICE);
    const expectedBal = (WEI_AMOUNT * CEILING_PRICE) / PRICE_FACTOR.toNumber();
    assert.equal(babzBalAlice.toNumber(), expectedBal, 'purchase failed');
    const babzTotal1 = await controller.completeSupply.call();

    // ntz6k is 1/5 of total Nutz supply
    const ntz6k = NTZ_DECIMALS.mul(6000);
    assert.equal(ntz6k.toNumber(), babzTotal1.div(5).toNumber());
    // powerup these tokens and check shares
    await nutz.powerUp(ntz6k);
    const powTotal = await power.totalSupply.call();
    const powBalAlice = await power.balanceOf.call(ALICE);
    assert.equal(powBalAlice.toNumber(), powTotal.div(2.5).toNumber(), 'first power up failed');

    // get some NTZ for 1 ETH with other account
    await nutz.purchase(CEILING_PRICE, {from: BOB, value: WEI_AMOUNT });
    const babzTotal2 = await controller.completeSupply.call();

    // ntz13k is 1/5 of total Nutz supply
    const ntz13k = NTZ_DECIMALS.mul(13500);
    assert.equal(ntz13k.toNumber(), babzTotal2.div(5).toNumber());
    // powerup these tokens and check shares
    await nutz.powerUp(ntz13k, {from: BOB});
    const powBalBob = await power.balanceOf.call(BOB);
    assert.equal(powBalBob.toNumber(), powTotal.div(2.5).toNumber(), 'second power up failed');


    // pow20pc is 20% of total Power
    const pow20pc = powBalAlice.div(2);
    assert.equal(pow20pc.toNumber(), powTotal.div(5).toNumber());
    // power down and check
    const babzBalAliceBefore = await nutz.balanceOf.call(ALICE);
    const babzActiveBefore = await nutz.activeSupply.call();
    await power.transfer(0x0, pow20pc);
    await power.downTickTest(ALICE, (Date.now() / 1000 | 0) + DOWNTIME);
    const powBalAliceAfter = await power.balanceOf.call(ALICE);
    assert.equal(powBalAliceAfter.toNumber(), pow20pc.toNumber(), 'power down failed in Power contract');
    // check balances in token contract
    const babzBalAliceAfter = await nutz.balanceOf.call(ALICE);
    const expectedBalAfter = babzBalAliceBefore.add(babzTotal2.div(10));
    assert.equal(babzBalAliceAfter.toNumber(), expectedBalAfter.toNumber(), 'power down failed in Nutz contract');
    const activeSupply = await nutz.activeSupply.call();
    const expectedActiveAfter = babzActiveBefore.add(babzTotal2.div(10));
    assert.equal(activeSupply.toNumber(), expectedActiveAfter.toNumber(), 'active supply wrong after power down.');
  });

  it('should allow to execute event manually', async () => {
    await controller.moveFloor(INFINITY);
    await controller.moveCeiling(CEILING_PRICE * 20);
    const powerAddr = await controller.powerAddr.call();
    const pullPayment = PullPayment.at(await controller.pullAddr.call());
    const power = Power.at(powerAddr);
    // Founder Buy in
    const FOUNDERS = accounts[1];
    const INVESTORS = accounts[2];

    await nutz.purchase(CEILING_PRICE * 20, {from: FOUNDERS, value: WEI_AMOUNT });
    const expectedBal = (WEI_AMOUNT * CEILING_PRICE * 20) / PRICE_FACTOR.toNumber();
    assert.equal(await nutz.balanceOf.call(FOUNDERS), expectedBal);
    // Founder Burn
    const totalBabz = await controller.completeSupply.call();
    await controller.dilutePower(totalBabz, 0);
    const totalPow = await power.totalSupply.call();
    await controller.setMaxPower(totalPow);
    // Founder power up, 1 ETH to 50 percent
    await nutz.powerUp(expectedBal, { from: FOUNDERS });
    const founderPow = await power.balanceOf.call(FOUNDERS);
    assert.equal(founderPow.toNumber(), totalPow.toNumber());
    // Investor buy in, 10 ETH
    // increase token price for investors
    await controller.moveCeiling(CEILING_PRICE);
    await controller.moveFloor(CEILING_PRICE * 2);
    await nutz.purchase(CEILING_PRICE, {from: INVESTORS, value: WEI_AMOUNT * 7 });
    // Invetors Burn
    const totalBabz2 = await controller.completeSupply.call();
    const investorsBal = await nutz.balanceOf.call(INVESTORS);
    await controller.dilutePower(totalBabz2.div(4), 0);
    const totalBabz3 = await controller.completeSupply.call();
    const totalPow3 = await power.totalSupply.call();
    // Investor Power Up, ETH to 20 percent
    await controller.setMaxPower(totalPow3);
    await nutz.powerUp(totalBabz3.div(10), { from: INVESTORS });
    const investorPow = await power.balanceOf.call(INVESTORS);
    // investor power should be 20%
    assert.equal(totalPow3.mul(0.2).toNumber(), investorPow.toNumber());
    // founder power should be 80%
    assert.equal(totalPow3.mul(0.8).toNumber(), founderPow.toNumber());
    // payout milestone 1 -> 10%
    const floor = await controller.floor.call();
    const ceiling = await controller.ceiling.call();
    const totalReserve = web3.toWei(8, 'ether');
    const weiReserve = web3.eth.getBalance(nutz.address);
    assert.equal(weiReserve.toNumber(), totalReserve, 'reserve incorrect');
    // payout 10 percent
    const payoutAmount = totalReserve/2;
    await controller.allocateEther(payoutAmount, FOUNDERS);
    let amountAllocated = await pullPayment.balanceOf.call(FOUNDERS);
    assert.equal(payoutAmount, amountAllocated.toNumber(), 'ether wasn\'t allocated to beneficiary');

    const before = web3.eth.getBalance(FOUNDERS);
    await pullPayment.withdraw({ from: FOUNDERS, gasPrice: 0 });
    const after = web3.eth.getBalance(FOUNDERS);
    assert.equal(after - before, amountAllocated.toNumber(), 'allocation wasn\'t payed out.');
  });

  it("should not loose precision due to power pool rounding", async () => {
    await controller.moveFloor(INFINITY);
    await controller.moveCeiling(1200000000);
    await controller.setDowntime(DOWNTIME);

    await nutz.purchase(1200000000, {from: accounts[0], value: WEI_AMOUNT });

    // authorize shares
    const amountPower = new BigNumber(10).pow(12).mul(630000).mul(2);
    let totalSupplyBabz = await controller.completeSupply.call()
    await controller.dilutePower(totalSupplyBabz, amountPower);
    let totalPower = await power.totalSupply.call();
    await controller.setMaxPower(totalPower);

    // powering up. Here we initialize power pool with non-zero value
    const powerUpVal = babz(100000);
    await nutz.powerUp(powerUpVal);

    // keep power pool size to use it for later calculations
    const oldPowerPool = await controller.powerPool.call();

    // but some more NTZ. We expect power pool to increase more
    await controller.moveCeiling(20000);
    await nutz.purchase(20000, {from: accounts[0], value: WEI_AMOUNT });

    // let's check power pool increased precisely
    const newPowerPool = await controller.powerPool.call();
    const activeSupply = await controller.activeSupply.call();
    const burnPool = await controller.burnPool.call();
    // replicating power pool increase logic from purchase() method
    const expectedPool = oldPowerPool.add(oldPowerPool.mul(new BigNumber(20000).mul(WEI_AMOUNT).div(1000000)).div(activeSupply.add(burnPool)));

    assert.equal(newPowerPool.toNumber(), expectedPool.toNumber(), "Power pool");
  });

  it("rounding experiment", async () => {
    const ALICE = accounts[0];
    const BOB = accounts[1];
    await controller.moveFloor(INFINITY);
    await controller.moveCeiling(1200000000);
    await controller.setDowntime(DOWNTIME);

    console.log('Purchase..');
    await nutz.purchase(1200000000, {from: ALICE, value: WEI_AMOUNT });

    await economy.printEconomy(controller, nutz, power, ALICE);

    console.log('Dilute..');
    const POW_DECIMALS = new BigNumber(10).pow(12);
    const amountPower = POW_DECIMALS.mul(6300000).mul(2);
    let totalSupplyBabz = await controller.completeSupply.call()
    await controller.dilutePower(totalSupplyBabz, amountPower);
    let totalPower = await power.totalSupply.call();
    await controller.setMaxPower(totalPower);

    await economy.printEconomy(controller, nutz, power, ALICE);

    let powerUpVal = babz(1000000000);
    console.log(`Power up\t\t ${economy.printValue(powerUpVal, 'NTZ')} ..`);
    await nutz.powerUp(powerUpVal);
    await controller.moveCeiling(20000);
    await economy.printEconomy(controller, nutz, power, ALICE);

    console.log(`Purchase\t\t ${economy.printValue(babz(20000), 'NTZ')}`);
    await nutz.purchase(20000, {from: ALICE, value: WEI_AMOUNT });

    await economy.printEconomy(controller, nutz, power, ALICE);

    powerUpVal = babz(100);
    console.log(`Power up\t\t ${economy.printValue(powerUpVal, 'NTZ')} ..`);
    await nutz.powerUp(powerUpVal);

    await economy.printEconomy(controller, nutz, power, ALICE);

    const nutzBal = await nutz.balanceOf.call(ALICE);

    let pow = (await power.balanceOf.call(ALICE)).div(10);
    //let pow = babz(50);

    console.log(`Down\t\t\t ${economy.printValue(pow, 'ABP')} ..`);
    console.log(`Babz for power down?:\t ${economy.printValue(pow.mul(await controller.completeSupply.call()).div(await controller.authorizedPower.call()), 'NTZ')}`)
    await power.transfer(0x0, pow);
    console.log('tick..');
    await power.downTickTest(ALICE, (Date.now() / 1000 | 0) + DOWNTIME);

    const prevUserPower = (await power.balanceOf.call(ALICE)).toNumber();

    await economy.printEconomy(controller, nutz, power, ALICE);

    powerUpVal = (await nutz.balanceOf.call(ALICE)).sub(nutzBal);

    for (var i = 0; i < 5; i++) {
      await nutz.powerUp(powerUpVal);
      await power.transfer(0x0, pow);
      await power.downTickTest(ALICE, (Date.now() / 1000 | 0) + DOWNTIME);
      console.log(`\t\t\t ${economy.printValue(await power.balanceOf.call(ALICE), 'ABP')}`);
    }

    await economy.printEconomy(controller, nutz, power, ALICE);

    let curUserPower = (await power.balanceOf.call(ALICE)).toNumber();
    assert.equal(curUserPower, prevUserPower, 'power');
  });

  it('should allow to slash down request');

  it("should allow to slash power balance", async () => {
    await controller.moveFloor(INFINITY);
    await controller.moveCeiling(CEILING_PRICE);
    const power = Power.at(await controller.powerAddr.call());

    // get some NTZ for 1 ETH
    await nutz.purchase(CEILING_PRICE, {from: accounts[0], value: WEI_AMOUNT });
    await controller.dilutePower(0, 0);
    const authorizedPower = await power.totalSupply.call();
    await controller.setMaxPower(authorizedPower);

    await nutz.powerUp(babz(15000));
    const outstandingBefore = await power.activeSupply.call();
    const bal = await power.balanceOf.call(accounts[0]);
    assert.equal(bal.toNumber(), babz(15000), '3rd party powerup failed');
    const powerPoolBefore = await controller.powerPool.call();

    // slash tokens
    await controller.slashPower(accounts[0], babz(5000), "0x00");
    const outstandingAfter = await power.activeSupply.call();
    const powerPoolAfter = await controller.powerPool.call();
    assert.equal(outstandingBefore.div(outstandingAfter).toNumber(), powerPoolBefore.div(powerPoolAfter).toNumber());
  });

  it('#downs should return power down requests in array form', async() => {
    await controller.moveFloor(INFINITY);
    await controller.moveCeiling(CEILING_PRICE);
    const power = Power.at(await controller.powerAddr.call());

    // get some NTZ for 1 ETH
    await nutz.purchase(CEILING_PRICE, { from: accounts[0], value: WEI_AMOUNT });
    await controller.dilutePower(0, 0);
    const authorizedPower = await power.totalSupply.call();
    await controller.setMaxPower(authorizedPower);
    await nutz.powerUp(babz(15000));
    const balancePow = await power.balanceOf.call(accounts[0]);

    await power.transfer(0, balancePow, "0x00");
    let downs = await controller.downs.call(accounts[0]);

    assert.equal(downs[0].toNumber(), babz(15000).toNumber(), "Total amount");
    assert.equal(downs[1].toNumber(), babz(15000).toNumber(), "Left amount");
    assert(downs[2].toNumber() > 0, "Power down start timestamp");
  });

  describe('#minimumPowerUpSizeBabz', () => {

    it('should return INFINITY when there is no NTZ in supply', async() => {
      // no power possible when no ntz in supply, expect min share to be Infinity
      assert.equal((await controller.minimumPowerUpSizeBabz()).toNumber(), INFINITY, "Initial share size");
    });

    it('should return size of 1/100000 of the economy', async() => {
      // get some NTZ for 1 ETH
      await controller.moveFloor(INFINITY);
      await controller.moveCeiling(30000);
      await nutz.purchase(30000, {from: accounts[0], value: WEI_AMOUNT });

      // at this point we have 30000 ntz in supply and we expect min share ntz size to be 1/100000 of that
      let minShareSizeBabz = (await controller.minimumPowerUpSizeBabz()).toNumber();
      assert.equal(minShareSizeBabz, babz(30000).div(100000).toNumber(), "Min share size");

      // power up half of NTZ
      await controller.dilutePower(0, 0);
      const power = Power.at(await controller.powerAddr.call());
      const authorizedPower = await power.totalSupply.call();
      await controller.setMaxPower(authorizedPower);
      await nutz.powerUp(babz(15000).toNumber());

      // we expect min share ntz size to stay unchanged, cause it includes power pool
      minShareSizeBabz = (await controller.minimumPowerUpSizeBabz()).toNumber();
      assert.equal(minShareSizeBabz, babz(30000).div(100000).toNumber(), "Min share size");
    });

  });

});
