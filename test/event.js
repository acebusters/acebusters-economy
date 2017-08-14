const Nutz = artifacts.require('./Nutz.sol');
const Power = artifacts.require('./Power.sol');
const PullPayment = artifacts.require('./PullPayment.sol');
const PowerEvent = artifacts.require('./PowerEvent.sol');
const BigNumber = require('bignumber.js');
require('./helpers/transactionMined.js');
const NTZ_DECIMALS = new BigNumber(10).pow(12);
const babz = (ntz) => new BigNumber(NTZ_DECIMALS).mul(ntz);
const WEI_AMOUNT = web3.toWei(0.001, 'ether');
const CEILING_PRICE = 20000;

contract('PowerEvent', (accounts) => {

  it('should allow to execute event through policy', async () => {
    const token = await Nutz.new(0);
    const power = Power.at(await token.powerAddr.call());
    const pullPayment = PullPayment.at(await token.pullAddr.call());
    await token.moveCeiling(CEILING_PRICE);
    await token.setOnlyContractHolders(false);


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
    const event1 = await PowerEvent.new(token.address, startTime, minDuration, maxDuration, softCap, hardCap, discountRate, milestoneRecipients, milestoneShares);
    await token.addAdmin(event1.address);
    await event1.startCollection();
    // event #1 - buyin
    const txHash1 = web3.eth.sendTransaction({ gas: 200000, from: FOUNDERS, to: token.address, value: WEI_AMOUNT });
    await web3.eth.transactionMined(txHash1);
    // event #1 - burn
    await event1.stopCollection();
    await event1.completeClosed();
    // event #1 power up
    await token.transfer(power.address, babz(1200000), "0x00", { from: FOUNDERS });
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
    const event2 = await PowerEvent.new(token.address, startTime, minDuration, maxDuration, softCap2, hardCap2, discountRate2, milestoneRecipients2, milestoneShares2);
    // event #2 - buy in
    await token.addAdmin(event2.address);
    await event2.startCollection();
    const txHash2 = web3.eth.sendTransaction({ gas: 300000, from: INVESTORS, to: token.address, value: hardCap2 });
    await web3.eth.transactionMined(txHash2);
    // event #2 - burn
    await event2.stopCollection();
    await event2.completeClosed();
    // event #2 - power up
    const investorsBal = await token.balanceOf.call(INVESTORS);
    await token.transfer(power.address, investorsBal, "0x00", { from: INVESTORS });
    // event #2 - milestone payment
    await token.moveFloor(CEILING_PRICE * 2);
    let amountAllocated = await pullPayment.balanceOf.call(EXEC_BOARD);
    assert.equal(amountAllocated.toNumber(), WEI_AMOUNT * 6000, 'ether wasn\'t allocated to beneficiary');

    // check power allocation
    const totalPow = await power.totalSupply.call();
    const founderPow = await power.balanceOf.call(FOUNDERS);
    const investorsPow = await power.balanceOf.call(INVESTORS);
    assert.equal(founderPow.toNumber(), totalPow.mul(0.7).toNumber());
    assert.equal(investorsPow.toNumber(), totalPow.mul(0.3).toNumber());
  });

});
