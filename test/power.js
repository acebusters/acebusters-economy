const Nutz = artifacts.require('./Nutz.sol');
const Power = artifacts.require('./Power.sol');
const BigNumber = require('bignumber.js');
require('./helpers/transactionMined.js');
const NTZ_DECIMALS = new BigNumber(10).pow(12);
const PRICE_FACTOR = new BigNumber(10).pow(6);

contract('Power', (accounts) => {

  it('should init contract', async () => {
    const DOWNTIME = 12*7*24*3600; // 3 month
    const token = await Nutz.new(DOWNTIME);
    const powerAddr = await token.powerAddr.call();
    const power = Power.at(powerAddr);
    await token.dilutePower(10000);
    const authorizedShares = await power.totalSupply.call();
    assert.equal(authorizedShares.toNumber(), 10000, 'shares not authorized');
  });

  it("should allow to power up and power down with no burn.", async () => {
    const DOWNTIME = 12*7*24*3600; // 3 month
    const WEI_AMOUNT = web3.toWei(1, 'ether');
    const CEILING_PRICE = 30000;
    const ALICE = accounts[0];
    const BOB = accounts[1];

    const token = await Nutz.new(DOWNTIME);
    await token.moveCeiling(CEILING_PRICE);
    const powerAddr = await token.powerAddr.call();
    const power = Power.at(powerAddr);
    
    // get some NTZ for 1 ETH
    const txHash1 = web3.eth.sendTransaction({ gas: 200000, from: accounts[0], to: token.address, value: WEI_AMOUNT });
    await web3.eth.transactionMined(txHash1);
    await token.dilutePower(0);
    const babzBalAlice = await token.balanceOf.call(ALICE);
    const expectedBal = (WEI_AMOUNT * CEILING_PRICE) / PRICE_FACTOR.toNumber();
    assert.equal(babzBalAlice.toNumber(), expectedBal, 'purchase failed');
    const babzTotal1 = await token.totalSupply.call();

    // ntz6k is 1/5 of total Nutz supply
    const ntz6k = NTZ_DECIMALS.mul(6000);
    assert.equal(ntz6k.toNumber(), babzTotal1.div(5).toNumber());
    // powerup these tokens and check shares
    await token.transfer(power.address, ntz6k);
    const powTotal = await power.totalSupply.call();
    const powBalAlice = await power.balanceOf.call(ALICE);
    assert.equal(powBalAlice.toNumber(), powTotal.div(5).toNumber(), 'first power up failed');

    // get some NTZ for 1 ETH with other account
    const txHash2 = web3.eth.sendTransaction({ gas: 200000, from: BOB, to: token.address, value: WEI_AMOUNT });
    await web3.eth.transactionMined(txHash2);
    const babzTotal2 = await token.totalSupply.call();
    
    // ntz13k is 1/5 of total Nutz supply
    const ntz13k = NTZ_DECIMALS.mul(13500);
    assert.equal(ntz13k.toNumber(), babzTotal2.div(5).toNumber());
    // powerup these tokens and check shares
    await token.transfer(power.address, ntz13k, {from: BOB});
    const powBalBob = await power.balanceOf.call(BOB);
    assert.equal(powBalBob.toNumber(), powTotal.div(5).toNumber(), 'second power up failed');
    

    // pow10pc is 10% of total Power
    const pow10pc = powBalAlice.div(2);
    assert.equal(pow10pc.toNumber(), powTotal.div(10).toNumber());
    // power down and check
    const babzBalAliceBefore = await token.balanceOf.call(ALICE);
    const babzActiveBefore = await token.activeSupply.call();
    await power.transfer(token.address, pow10pc);
    await power.downTickTest(0, (Date.now() / 1000 | 0) + DOWNTIME);
    const powBalAliceAfter = await power.balanceOf.call(ALICE);
    assert.equal(powBalAliceAfter.toNumber(), pow10pc.toNumber(), 'power down failed in Power contract');
    // check balances in token contract
    const babzBalAliceAfter = await token.balanceOf.call(ALICE);
    const expectedBalAfter = babzBalAliceBefore.add(babzTotal2.div(10));
    assert.equal(babzBalAliceAfter.toNumber(), expectedBalAfter.toNumber(), 'power down failed in Nutz contract');
    const activeSupply = await token.activeSupply.call();
    const expectedActiveAfter = babzActiveBefore.add(babzTotal2.div(10));
    assert.equal(activeSupply.toNumber(), expectedActiveAfter.toNumber(), 'config failed.');
  });

});
