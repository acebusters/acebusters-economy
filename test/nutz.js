const Nutz = artifacts.require('./Nutz.sol');
const ERC223ReceiverMock = artifacts.require('./helpers/ERC223ReceiverMock.sol');
const assertJump = require('./helpers/assertJump');
const BigNumber = require('bignumber.js');
require('./helpers/transactionMined.js');
const BYTES_32 = '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';
const NTZ_DECIMALS = new BigNumber(10).pow(12);
const PRICE_FACTOR = new BigNumber(10).pow(6);

contract('Nutz', function(accounts) {
  

  it('should allow to purchase', async function() {
    // create token contract
    const token = await Nutz.new(3600);
    await token.moveCeiling(30000);
    const ceiling = await token.ceiling.call();
    // purchase some tokens with ether
    const amountWei = web3.toWei(1, 'ether');
    const txHash = web3.eth.sendTransaction({ from: accounts[0], to: token.address, value: amountWei });
    await web3.eth.transactionMined(txHash);
    // check balance, supply and reserve
    const babzBalance = await token.balanceOf.call(accounts[0]);
    assert.equal(babzBalance.toNumber(), ceiling.mul(NTZ_DECIMALS).toNumber(), 'token wasn\'t issued to account');
    const supplyBabz = await token.activeSupply.call();
    assert.equal(supplyBabz.toNumber(), ceiling.mul(NTZ_DECIMALS).toNumber(), 'token wasn\'t issued');
    const reserveWei = await token.reserve.call();
    assert.equal(reserveWei.toNumber(), amountWei, 'ether wasn\'t sent to contract');
  });

  it('should allow to sell', async function() {
    // create contract and purchase tokens for 1 ether
    const token = await Nutz.new(0);
    await token.moveFloor(1000);
    await token.moveCeiling(1000);
    const floor = await token.floor.call();
    const ceiling = await token.ceiling.call();
    const amountWei = web3.toWei(1, 'ether');
    const halfamountWei = web3.toWei(0.5, 'ether');
    const txHash = web3.eth.sendTransaction({ from: accounts[0], to: token.address, value: amountWei });
    await web3.eth.transactionMined(txHash);
    let babzBalance = await token.balanceOf.call(accounts[0]);
    assert.equal(babzBalance.toNumber(), ceiling.mul(amountWei).div(PRICE_FACTOR).toNumber(), 'token wasn\'t issued to account');
    // sell half of the tokens
    await token.transfer(token.address, babzBalance.div(2), "0x00");
    // check balance, supply
    let newBabzBal = await token.balanceOf.call(accounts[0]);
    assert.equal(newBabzBal.toNumber(), babzBalance.div(2).toNumber(), 'token wasn\'t deducted by sell');
    const supplyBabz = await token.activeSupply.call();
    assert.equal(supplyBabz.toNumber(), babzBalance.div(2).toNumber(), 'token wasn\'t destroyed');
    // check allocation and reserve
    let allocationWei = await token.allowance.call(token.address, accounts[0]);
    assert.equal(allocationWei.toString(), halfamountWei, 'ether wasn\'t allocated for withdrawal');
    const reserveWei = await token.reserve.call();
    assert.equal(reserveWei.toString(), halfamountWei, 'ether allocation wasn\'t deducted from reserve');
    // pull the ether from the account
    await token.transferFrom(token.address, accounts[0], 0);
    allocationWei = await token.allowance.call(token.address, accounts[0]);
    assert.equal(allocationWei.toNumber(), 0, 'allocation wasn\'t payed out.');
    // TODO: check my ether balance increased
  });

  it('should implement emergency switch');

  it('should call erc223 when purchase', async () => {
    let receiver = await ERC223ReceiverMock.new();
    const token = await Nutz.new(0);
    await token.moveCeiling(1500);
    const amountWei = web3.toWei(1, 'ether');
    const txHash = web3.eth.sendTransaction({ from: accounts[0], to: receiver.address, value: amountWei });
    await web3.eth.transactionMined(txHash);
    await receiver.forward(token.address, amountWei);
    const isCalled = await receiver.called.call();
    assert(isCalled, 'erc223 interface has not been invoked on purchase');
  });

  it('should allow to disable transfer to non-contract accounts.');

  it('should adjust getFloor automatically when active supply inflated');

  it('should adjust floor in sell automatically when active supply inflated');

  it('should allow to slash power balance');

  it('should allow to slash down request');

  it('allocate_funds_to_beneficiary and claim_revenue', async function() {
    // create token contract, default ceiling == floor
    const token = await Nutz.new(0);
    await token.moveCeiling(1500);
    await token.moveFloor(3000);
    const floor = await token.floor.call();
    const ceiling = await token.ceiling.call();
    assert.equal(ceiling.toNumber(), 1500, 'setting ceiling failed');
    const amountWei = web3.toWei(new BigNumber(1), 'ether');
    const txHash = web3.eth.sendTransaction({ from: accounts[0], to: token.address, value: amountWei });
    await web3.eth.transactionMined(txHash);
    const reserveWei = await token.reserve.call();
    assert.equal(reserveWei.toNumber(), amountWei.toNumber(), 'reserve incorrect');
    const babzBalance = await token.balanceOf.call(accounts[0]);
    assert.equal(babzBalance.toNumber(), ceiling.mul(amountWei).div(PRICE_FACTOR).toNumber(), 'token wasn\'t issued to account');

    const revenueWei = amountWei.minus(babzBalance.div(floor).mul(PRICE_FACTOR));
    await token.allocateEther(revenueWei, accounts[1]);
    let allocatedWei = await token.allowance.call(token.address, accounts[1]);
    assert.equal(allocatedWei.toNumber(), revenueWei.toNumber(), 'ether wasn\'t allocated to beneficiary');
    // pull the ether from the account
    await token.transferFrom(token.address, accounts[1], 0, { from: accounts[1] });
    allocatedWei = await token.allowance.call(token.address, accounts[1]);
    assert.equal(allocatedWei.toNumber(), 0, 'allocation wasn\'t payed out.');
    // TODO: check ether balance actually increased
  });

  it('should handle The sale administrator sets floor = infinity, ceiling = 0', async function() {
    // create token contract, default ceiling == floor
    const token = await Nutz.new(0);
    await token.moveCeiling(100);
    let ceiling = await token.ceiling.call();
    const amountWei = web3.toWei(1, 'ether');
    let txHash = web3.eth.sendTransaction({ from: accounts[0], to: token.address, value: amountWei });
    await web3.eth.transactionMined(txHash);
    const babzBalanceBefore = await token.balanceOf.call(accounts[0]);
    assert.equal(babzBalanceBefore.toNumber(), ceiling.mul(amountWei).div(PRICE_FACTOR).toNumber(), 'token wasn\'t issued to account');
    await token.moveFloor(BYTES_32);
    const floor = await token.floor.call();
    await token.moveCeiling(0);
    ceiling = await token.ceiling.call();
    assert.equal(floor.toNumber(), BYTES_32, 'setting floor failed');
    assert.equal(ceiling.toNumber(), 0, 'setting ceiling failed');
    // try purchasing some tokens with ether
    try {
      txHash = web3.eth.sendTransaction({ from: accounts[0], to: token.address, value: amountWei });
      await web3.eth.transactionMined(txHash);
    } catch(error) {
      assertJump(error);
      // check balance, supply and reserve
      const babzBalanceAfter = await token.balanceOf.call(accounts[0]);
      assert.equal(babzBalanceAfter.toNumber(), babzBalanceBefore, 'balance should stay same after failed purchase');
      const supplyBabz = await token.activeSupply.call();
      assert.equal(supplyBabz.toNumber(), babzBalanceBefore, 'activeSupply should stay same after failed purchase');
      const reserveWei = await token.reserve.call();
      assert.equal(reserveWei.toNumber(), amountWei, 'ether should not have been deposited');
      return;
    }
    assert.fail('should have thrown before');
  });

  it('the sale administrator can’t raise the floor price if doing so would make it unable to purchase all of the tokens at the floor price', async function() {
    // create contract and buy some tokens
    const token = await Nutz.new(0);
    await token.moveCeiling(4000);
    let ceiling = await token.ceiling.call();
    const amountWei = web3.toWei(1, 'ether');
    const txHash = web3.eth.sendTransaction({ from: accounts[0], to: token.address, value: amountWei });
    await web3.eth.transactionMined(txHash);
    let supplyBabz = await token.activeSupply.call(accounts[0]);
    const reserveWei = await token.reserve.call();
    assert.equal(supplyBabz.toNumber(), ceiling.mul(amountWei).div(PRICE_FACTOR).toNumber(), 'amount wasn\'t issued to account');
    // move ceiling so we can move floor
    await token.moveCeiling(2000);
    ceiling = await token.ceiling.call();
    assert.equal(ceiling.toNumber(), 2000, 'setting ceiling failed');

    // move floor should fail, because reserve exceeded
    try {
      await token.moveFloor(2000);
    } catch(error) {
      return assertJump(error);
    }
    assert.fail('should have thrown before');
  });

  it('allocate_funds_to_beneficiary fails if allocating those funds would mean that the sale mechanism is no longer able to buy back all outstanding tokens',  async function() {
    // create token contract, default ceiling == floor
    const token = await Nutz.new(0);
    await token.moveCeiling(1500);
    await token.moveFloor(2000);
    const floor = await token.floor.call();
    const ceiling = await token.ceiling.call();
    assert.equal(ceiling.toNumber(), 1500, 'setting ceiling failed');
    const amountWei = web3.toWei(new BigNumber(1), 'ether');
    const txHash = web3.eth.sendTransaction({ from: accounts[0], to: token.address, value: amountWei });
    await web3.eth.transactionMined(txHash);
    const reserveWei = await token.reserve.call();
    assert.equal(reserveWei.toNumber(), amountWei.toNumber(), 'reserve incorrect');
    const babzBalance = await token.balanceOf.call(accounts[0]);
    assert.equal(babzBalance.toNumber(), ceiling.mul(amountWei).div(PRICE_FACTOR).toNumber(), 'token wasn\'t issued to account');

    const revenueWei = amountWei.minus(babzBalance.times(floor));
    const doublerevenueWei = revenueWei.times(2);
    try {
      await token.allocateEther(doublerevenueWei, accounts[1]);
    } catch(error) {
      return assertJump(error);
    }
    assert.fail('should have thrown before');
  });

  it('should return correct balances after transfer', async function() {
    // create contract and buy some tokens
    const token = await Nutz.new(0);
    await token.moveCeiling(100);
    const ceiling = await token.ceiling.call();
    const amountWei = web3.toWei(1, 'ether');
    const txHash = web3.eth.sendTransaction({ from: accounts[0], to: token.address, value: amountWei });
    await web3.eth.transactionMined(txHash);
    let babzBalance = await token.balanceOf.call(accounts[0]);
    assert.equal(babzBalance.toNumber(), ceiling.mul(amountWei).div(PRICE_FACTOR).toNumber(), 'amount wasn\'t issued to account');
    // transfer token to other account
    const halfbabzBalance = babzBalance.dividedBy(2);
    let transfer = await token.transfer(accounts[1], halfbabzBalance, "0x00");

    // check balances of sender and recepient
    const newbabzBalance = await token.balanceOf(accounts[0]);
    assert.equal(newbabzBalance.toNumber(), halfbabzBalance.toNumber(), 'amount hasn\'t been transfered');
    babzBalance = await token.balanceOf(accounts[1]);
    assert.equal(babzBalance.toNumber(), halfbabzBalance.toNumber(), 'amount hasn\'t been received');
  });

  it('should throw an error when trying to transfer more than balance', async function() {
    const token = await Nutz.new(0);
    try {
      await token.transfer(accounts[1], 101, "0x00");
    } catch(error) {
      return assertJump(error);
    }
    assert.fail('should have thrown before');
  });

});
