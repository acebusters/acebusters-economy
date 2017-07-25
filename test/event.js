const NutzMock = artifacts.require('./helpers/NutzMock.sol');
const Power = artifacts.require('./Power.sol');
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

contract('PowerEvent', (accounts) => {

  it('should allow to execute event through policy', async () => {
    const token = await NutzMock.new(DOWNTIME, 0, CEILING_PRICE * 20, INFINITY);
    const powerAddr = await token.powerAddr.call();
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
    await token.setMaxPower(totalPow.div(2));
    // Founder power up, 1 ETH to 50 percent
    await token.transfer(powerAddr, expectedBal, "0x00", { from: FOUNDERS });
    const founderPow = await power.balanceOf.call(FOUNDERS);
    assert.equal(founderPow.toNumber(), totalPow.div(2).toNumber());
    // prepare event
    await token.moveCeiling(CEILING_PRICE / 2);
    const startTime = (Date.now() / 1000 | 0) - 60;
    const minDuration = 0;
    const maxDuration = 3600;
    const softCap = WEI_AMOUNT;
    const hardCap = WEI_AMOUNT * 6;
    const discountRate = 1000000; // 100% => receive double
    const milestoneRecipients = [FOUNDERS];
    const milestoneShares = [500000];
    const event = await PowerEvent.new(token.address, startTime, minDuration, maxDuration, softCap, hardCap, discountRate, milestoneRecipients, milestoneShares);
    // Investor buy in, 7 ETH
    await token.addAdmin(event.address);
    await event.startCollection();
    const txHash2 = web3.eth.sendTransaction({ gas: 300000, from: INVESTORS, to: token.address, value: WEI_AMOUNT * 7 });
    await web3.eth.transactionMined(txHash1);
    // Invetors Burn  
    const totalPow2 = await power.totalSupply.call();
    const totalBabz2 = await token.totalSupply.call();
    const investorsBal = await token.balanceOf.call(INVESTORS);
    await event.stopCollection();
    await event.completeClosed();
    const totalBabz3 = await token.totalSupply.call();
    const totalPow3 = await power.totalSupply.call();
    // Investor Power Up, ETH to 10 percent
    await token.transfer(powerAddr, totalBabz3.div(10), "0x00", { from: INVESTORS });
    const investorPow = await power.balanceOf.call(INVESTORS);
    // investor power should be 10%
    assert.equal(totalPow3.div(10).toNumber(), investorPow.toNumber());
    // check milestone payment
    const payoutAmount = WEI_AMOUNT * 3.5;
    let amountAllocated = await token.allowance.call(token.address, FOUNDERS);
    assert.equal(payoutAmount, amountAllocated.toNumber(), 'ether wasn\'t allocated to beneficiary');
    await token.moveFloor(CEILING_PRICE * 2);
    await token.transferFrom(token.address, FOUNDERS, 0, { from: FOUNDERS });
    let amountAllocated2 = await token.allowance.call(token.address, FOUNDERS);
    assert.equal(amountAllocated2, 0, 'ether wasn\'t received');
  });

});
