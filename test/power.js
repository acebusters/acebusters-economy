const Nutz = artifacts.require('./Nutz.sol');
const Power = artifacts.require('./Power.sol');
const BigNumber = require('bignumber.js');
require('./helpers/transactionMined.js');
const NTZ_DECIMALS = new BigNumber(10).pow(12);
const PRICE_FACTOR = new BigNumber(10).pow(6);
const DOWNTIME = 12*7*24*3600; // 3 month
const WEI_AMOUNT = web3.toWei(1, 'ether');
const CEILING_PRICE = 30000;

contract('Power', (accounts) => {

  it('should init contract', async () => {
    const token = await Nutz.new(DOWNTIME);
    const powerAddr = await token.powerAddr.call();
    const power = Power.at(powerAddr);
    await token.dilutePower(0, 10000);
    const authorizedShares = await power.totalSupply.call();
    assert.equal(authorizedShares.toNumber(), 10000, 'shares not authorized');
  });

  it("should allow to power up and power down with no burn.", async () => {
    const ALICE = accounts[0];
    const BOB = accounts[1];

    const token = await Nutz.new(DOWNTIME);
    await token.moveCeiling(CEILING_PRICE);
    const powerAddr = await token.powerAddr.call();
    const power = Power.at(powerAddr);
    
    // get some NTZ for 1 ETH
    const txHash1 = web3.eth.sendTransaction({ gas: 200000, from: ALICE, to: token.address, value: WEI_AMOUNT });
    await web3.eth.transactionMined(txHash1);
    const totalNtz = await token.totalSupply.call();
    await token.dilutePower(0, totalNtz);
    const authorizedPower = await power.totalSupply.call();
    await token.setMaxPower(authorizedPower.div(2));
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
    assert.equal(powBalAlice.toNumber(), powTotal.div(5).toNumber(), 'first power up failed');

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
    assert.equal(powBalBob.toNumber(), powTotal.div(5).toNumber(), 'second power up failed');
    

    // pow10pc is 10% of total Power
    const pow10pc = powBalAlice.div(2);
    assert.equal(pow10pc.toNumber(), powTotal.div(10).toNumber());
    // power down and check
    const babzBalAliceBefore = await token.balanceOf.call(ALICE);
    const babzActiveBefore = await token.activeSupply.call();
    await power.transfer(token.address, pow10pc, "0x00");
    await power.downTickTest(0, (Date.now() / 1000 | 0) + DOWNTIME);
    const powBalAliceAfter = await power.balanceOf.call(ALICE);
    assert.equal(powBalAliceAfter.toNumber(), pow10pc.toNumber(), 'power down failed in Power contract');
    // check balances in token contract
    const babzBalAliceAfter = await token.balanceOf.call(ALICE);
    const expectedBalAfter = babzBalAliceBefore.add(babzTotal2.div(10));
    assert.equal(babzBalAliceAfter.toNumber(), expectedBalAfter.toNumber(), 'power down failed in Nutz contract');
    const activeSupply = await token.activeSupply.call();
    const expectedActiveAfter = babzActiveBefore.add(babzTotal2.div(10));
    assert.equal(activeSupply.toNumber(), expectedActiveAfter.toNumber(), 'active supply wrong after power down.');
  });

  it('should allow to do secondary round', async () => {
    const token = await Nutz.new(DOWNTIME);
    const powerAddr = await token.powerAddr.call();
    const power = Power.at(powerAddr);
    await token.moveCeiling(CEILING_PRICE);
    // Founder Buy in 
    const FOUNDERS = accounts[1];
    const INVESTORS = accounts[2];
    
    const txHash1 = web3.eth.sendTransaction({ gas: 200000, from: FOUNDERS, to: token.address, value: WEI_AMOUNT });
    await web3.eth.transactionMined(txHash1);
    const expectedBal = (WEI_AMOUNT * CEILING_PRICE) / PRICE_FACTOR.toNumber();
    assert.equal(await token.balanceOf.call(FOUNDERS), expectedBal);
    // Founder Burn
    const totalNtz = await token.totalSupply.call();
    await token.dilutePower(totalNtz, totalNtz.mul(2));
    const totalPow = await power.totalSupply.call();
    await token.setMaxPower(totalPow.div(2));
    // Founder power up, 1 ETH to 50 percent
    await token.transfer(powerAddr, expectedBal, "0x00", { from: FOUNDERS });
    const founderPow = await power.balanceOf.call(FOUNDERS);
    assert.equal(founderPow.toNumber(), totalPow.div(2).toNumber());
    // Investor buy in, 10 ETH
    const txHash2 = web3.eth.sendTransaction({ gas: 300000, from: INVESTORS, to: token.address, value: WEI_AMOUNT * 10 });
    await web3.eth.transactionMined(txHash1);
    // Invetors Burn  
    const totalPow2 = await power.totalSupply.call();
    const totalNtz2 = await token.totalSupply.call();
    const investorsBal = await token.balanceOf.call(INVESTORS);
    await token.dilutePower(investorsBal.mul(10).sub(totalNtz2), totalPow2.div(4));
    const totalPow3 = await power.totalSupply.call();
    // Investor Power Up, ETH to 10 percent
    await token.setMaxPower(totalPow3.div(2));
    await token.transfer(powerAddr, investorsBal, "0x00", { from: INVESTORS });
    const investorPow = await power.balanceOf.call(INVESTORS);
    // investor power should be 10%
    assert.equal(totalPow3.div(10).toNumber(), investorPow.toNumber());
    // founder power should be 40%
    assert.equal(totalPow3.div(10).mul(4).toNumber(), founderPow.toNumber());
  });
});
