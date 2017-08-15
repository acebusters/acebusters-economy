const Nutz = artifacts.require('./Nutz.sol');
const NutzMock = artifacts.require('./helpers/NutzMock.sol');
const Power = artifacts.require('./Power.sol');
const PullPayment = artifacts.require('./PullPayment.sol');
const PowerEvent = artifacts.require('./PowerEvent.sol');
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

  it('should init contract', async () => {
    const token = await Nutz.new(DOWNTIME);
    const power = Power.at(await token.powerAddr.call());
    await token.dilutePower(10000);
    const authorizedShares = await power.totalSupply.call();
    assert.equal(authorizedShares.toNumber(), 5000, 'shares not authorized');
  });

  it("should allow to power up and power down with no burn.", async () => {
    const ALICE = accounts[0];
    const BOB = accounts[1];

    const token = await NutzMock.new(DOWNTIME, 0, CEILING_PRICE, INFINITY);
    const power = Power.at(await token.powerAddr.call());
    
    // get some NTZ for 1 ETH
    const txHash1 = web3.eth.sendTransaction({ gas: 200000, from: ALICE, to: token.address, value: WEI_AMOUNT });
    await web3.eth.transactionMined(txHash1);
    await token.dilutePower(0);
    const authorizedPower = await power.totalSupply.call();
    await token.setMaxPower(authorizedPower);
    const babzBalAlice = await token.balanceOf.call(ALICE);
    const expectedBal = (WEI_AMOUNT * CEILING_PRICE) / PRICE_FACTOR.toNumber();
    assert.equal(babzBalAlice.toNumber(), expectedBal, 'purchase failed');
    const babzTotal1 = await token.totalSupply.call();

    // ntz6k is 1/5 of total Nutz supply
    const ntz6k = NTZ_DECIMALS.mul(6000);
    assert.equal(ntz6k.toNumber(), babzTotal1.div(5).toNumber());
    // powerup these tokens and check shares
    await token.transfer(power.address, ntz6k, "0x00");
    const powTotal = await power.totalSupply.call();
    const powBalAlice = await power.balanceOf.call(ALICE);
    assert.equal(powBalAlice.toNumber(), powTotal.div(2.5).toNumber(), 'first power up failed');

    // get some NTZ for 1 ETH with other account
    const txHash2 = web3.eth.sendTransaction({ gas: 200000, from: BOB, to: token.address, value: WEI_AMOUNT });
    await web3.eth.transactionMined(txHash2);
    const babzTotal2 = await token.totalSupply.call();
    
    // ntz13k is 1/5 of total Nutz supply
    const ntz13k = NTZ_DECIMALS.mul(13500);
    assert.equal(ntz13k.toNumber(), babzTotal2.div(5).toNumber());
    // powerup these tokens and check shares
    await token.approve(accounts[2], ntz13k, {from: BOB});
    await token.transferFrom(BOB, power.address, ntz13k, {from: accounts[2]});
    const powBalBob = await power.balanceOf.call(BOB);
    assert.equal(powBalBob.toNumber(), powTotal.div(2.5).toNumber(), 'second power up failed');
    

    // pow20pc is 20% of total Power
    const pow20pc = powBalAlice.div(2);
    assert.equal(pow20pc.toNumber(), powTotal.div(5).toNumber());
    // power down and check
    const babzBalAliceBefore = await token.balanceOf.call(ALICE);
    const babzActiveBefore = await token.activeSupply.call();
    await power.transfer(token.address, pow20pc, "0x00");
    await power.downTickTest(0, (Date.now() / 1000 | 0) + DOWNTIME);
    const powBalAliceAfter = await power.balanceOf.call(ALICE);
    assert.equal(powBalAliceAfter.toNumber(), pow20pc.toNumber(), 'power down failed in Power contract');
    // check balances in token contract
    const babzBalAliceAfter = await token.balanceOf.call(ALICE);
    const expectedBalAfter = babzBalAliceBefore.add(babzTotal2.div(10));
    assert.equal(babzBalAliceAfter.toNumber(), expectedBalAfter.toNumber(), 'power down failed in Nutz contract');
    const activeSupply = await token.activeSupply.call();
    const expectedActiveAfter = babzActiveBefore.add(babzTotal2.div(10));
    assert.equal(activeSupply.toNumber(), expectedActiveAfter.toNumber(), 'active supply wrong after power down.');
  });

  it('should allow to execute event manually', async () => {
    const token = await NutzMock.new(DOWNTIME, 0, CEILING_PRICE * 20, INFINITY);
    const powerAddr = await token.powerAddr.call();
    const pullPayment = PullPayment.at(await token.pullAddr.call());
    const power = Power.at(powerAddr);
    // Founder Buy in 
    const FOUNDERS = accounts[1];
    const INVESTORS = accounts[2];
    
    const txHash1 = web3.eth.sendTransaction({ gas: 200000, from: FOUNDERS, to: token.address, value: WEI_AMOUNT });
    await web3.eth.transactionMined(txHash1);
    const expectedBal = (WEI_AMOUNT * CEILING_PRICE * 20) / PRICE_FACTOR.toNumber();
    assert.equal(await token.balanceOf.call(FOUNDERS), expectedBal);
    // Founder Burn
    const totalBabz = await token.totalSupply.call();
    await token.dilutePower(totalBabz);
    const totalPow = await power.totalSupply.call();
    await token.setMaxPower(totalPow);
    // Founder power up, 1 ETH to 50 percent
    await token.transfer(powerAddr, expectedBal, "0x00", { from: FOUNDERS });
    const founderPow = await power.balanceOf.call(FOUNDERS);
    assert.equal(founderPow.toNumber(), totalPow.toNumber());
    // Investor buy in, 10 ETH
    // increase token price for investors
    await token.moveCeiling(CEILING_PRICE);
    await token.moveFloor(CEILING_PRICE * 2);
    const txHash2 = web3.eth.sendTransaction({ gas: 300000, from: INVESTORS, to: token.address, value: WEI_AMOUNT * 7 });
    await web3.eth.transactionMined(txHash1);
    // Invetors Burn
    const totalBabz2 = await token.totalSupply.call();
    const investorsBal = await token.balanceOf.call(INVESTORS);
    await token.dilutePower(totalBabz2.div(4));
    const totalBabz3 = await token.totalSupply.call();
    const totalPow3 = await power.totalSupply.call();
    // Investor Power Up, ETH to 20 percent
    await token.setMaxPower(totalPow3);
    await token.transfer(powerAddr, totalBabz3.div(10), "0x00", { from: INVESTORS });
    const investorPow = await power.balanceOf.call(INVESTORS);
    // investor power should be 20%
    assert.equal(totalPow3.mul(0.2).toNumber(), investorPow.toNumber());
    // founder power should be 80%
    assert.equal(totalPow3.mul(0.8).toNumber(), founderPow.toNumber());
    // payout milestone 1 -> 10%
    const floor = await token.floor.call();
    const ceiling = await token.ceiling.call();
    const totalReserve = web3.toWei(8, 'ether');
    const weiReserve = web3.eth.getBalance(token.address);
    assert.equal(weiReserve.toNumber(), totalReserve, 'reserve incorrect');
    // payout 10 percent
    const payoutAmount = totalReserve/2;
    await token.allocateEther(payoutAmount, FOUNDERS);
    let amountAllocated = await pullPayment.balanceOf.call(FOUNDERS);
    assert.equal(payoutAmount, amountAllocated.toNumber(), 'ether wasn\'t allocated to beneficiary');

    const before = web3.eth.getBalance(FOUNDERS);
    await pullPayment.withdraw({ from: FOUNDERS, gasPrice: 0 });
    const after = web3.eth.getBalance(FOUNDERS);
    assert.equal(after - before, amountAllocated.toNumber(), 'allocation wasn\'t payed out.');
  });

  it('should allow to slash down request');

  it("should allow to slash power balance", async () => {
    const token = await NutzMock.new(DOWNTIME, 0, CEILING_PRICE, INFINITY);
    const power = Power.at(await token.powerAddr.call());
    
    // get some NTZ for 1 ETH
    const txHash1 = web3.eth.sendTransaction({ gas: 200000, from: accounts[1], to: token.address, value: WEI_AMOUNT });
    await web3.eth.transactionMined(txHash1);
    await token.dilutePower(0);
    const authorizedPower = await power.totalSupply.call();
    await token.setMaxPower(authorizedPower);

    // powerup tokens ( try 3rd party powerUp )
    await token.transferFrom(power.address, accounts[0], babz(15000), '0x00', { from: accounts[1] });
    const outstandingBefore = await power.activeSupply.call();
    const bal = await power.balanceOf.call(accounts[0]);
    assert.equal(bal.toNumber(), babz(15000), '3rd party powerup failed');
    const powerPoolBefore = await token.powerPool.call();

    // slash tokens
    await token.slashPower(accounts[0], babz(5000), "0x00");
    const outstandingAfter = await power.activeSupply.call();
    const powerPoolAfter = await token.powerPool.call();
    assert.equal(outstandingBefore.div(outstandingAfter).toNumber(), powerPoolBefore.div(powerPoolAfter).toNumber());
  });

});
