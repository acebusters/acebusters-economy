const Nutz = artifacts.require('./satelites/Nutz.sol');
const Power = artifacts.require('./satelites/Power.sol');
const Storage = artifacts.require('./satelites/Storage.sol');
const PullPayment = artifacts.require('./satelites/PullPayment.sol');
const Controller = artifacts.require('./controller/Controller.sol');
const BigNumber = require('bignumber.js');
require('./helpers/transactionMined.js');
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
    await controller.dilutePower(10000);
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
    await controller.dilutePower(0);
    const authorizedPower = await power.totalSupply.call();
    await controller.setMaxPower(authorizedPower);
    const babzBalAlice = await nutz.balanceOf.call(ALICE);
    const expectedBal = (WEI_AMOUNT * CEILING_PRICE) / PRICE_FACTOR.toNumber();
    assert.equal(babzBalAlice.toNumber(), expectedBal, 'purchase failed');
    const babzTotal1 = await nutz.totalSupply.call();

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
    const babzTotal2 = await nutz.totalSupply.call();

    // ntz13k is 1/5 of total Nutz supply
    const ntz13k = NTZ_DECIMALS.mul(13500);
    assert.equal(ntz13k.toNumber(), babzTotal2.div(5).toNumber());
    // powerup these tokens and check shares
    await nutz.approve(accounts[2], ntz13k, {from: BOB});
    await nutz.transferFrom(BOB, 0, ntz13k, '0x00', {from: accounts[2]});
    const powBalBob = await power.balanceOf.call(BOB);
    assert.equal(powBalBob.toNumber(), powTotal.div(2.5).toNumber(), 'second power up failed');


    // pow20pc is 20% of total Power
    const pow20pc = powBalAlice.div(2);
    assert.equal(pow20pc.toNumber(), powTotal.div(5).toNumber());
    // power down and check
    const babzBalAliceBefore = await nutz.balanceOf.call(ALICE);
    const babzActiveBefore = await nutz.activeSupply.call();
    await power.transfer(0x0, pow20pc);
    await power.downTickTest(ALICE, 0, (Date.now() / 1000 | 0) + DOWNTIME);
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
    const totalBabz = await nutz.totalSupply.call();
    await controller.dilutePower(totalBabz);
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
    const totalBabz2 = await nutz.totalSupply.call();
    const investorsBal = await nutz.balanceOf.call(INVESTORS);
    await controller.dilutePower(totalBabz2.div(4));
    const totalBabz3 = await nutz.totalSupply.call();
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
    const weiReserve = web3.eth.getBalance(controller.address);
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

  it('should allow to slash down request');

  it("should allow to slash power balance", async () => {
    await controller.moveFloor(INFINITY);
    await controller.moveCeiling(CEILING_PRICE);
    const power = Power.at(await controller.powerAddr.call());

    // get some NTZ for 1 ETH
    await nutz.purchase(CEILING_PRICE, {from: accounts[0], value: WEI_AMOUNT });
    await controller.dilutePower(0);
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
    await controller.dilutePower(0);
    const authorizedPower = await power.totalSupply.call();
    await controller.setMaxPower(authorizedPower);
    await nutz.powerUp(babz(15000));
    const balancePow = await power.balanceOf.call(accounts[0]);

    await power.transfer(0, balancePow, "0x00");
    let downs = await controller.downs.call(accounts[0]);

    // check number of power downs
    assert.equal(downs[1], 1, "Just one power down expected");
    // check "total" of the "second" power down. It should not exist, hence we expect 0
    assert.equal(downs[0][1][0], 0, "Only one power down expected")
    let powerDown = downs[0][0];
    assert.equal(powerDown[0].toNumber(), babz(15000).toNumber(), "Total amount");
    assert.equal(powerDown[1].toNumber(), babz(15000).toNumber(), "Left amount");
    assert(powerDown[2].toNumber() > 0, "Power down start timestamp");
  });

});
