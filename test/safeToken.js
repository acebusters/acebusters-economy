const SafeToken = artifacts.require('./SafeToken.sol');
const assertJump = require('./helpers/assertJump');
const BigNumber = require('bignumber.js');
require('./helpers/transactionMined.js');
const BYTES_32 = '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';

contract('SafeToken', function(accounts) {
  

  it('should allow to purchase', async function() {
    // create token contract, default ceiling == floor
    const token = await SafeToken.new();
    const ceiling = await token.ceiling.call();
    // purchase some tokens with ether
    const amountWei = web3.toWei(1, 'ether');
    const txHash = web3.eth.sendTransaction({ from: accounts[0], to: token.address, value: amountWei });
    await web3.eth.transactionMined(txHash);
    // check balance, supply and reserve
    const balanceTkn = await token.balanceOf.call(accounts[0]);
    assert.equal(balanceTkn.toNumber(), amountWei / ceiling, 'token wasn\'t issued to account');
    const supplyTkn = await token.totalSupply.call();
    assert.equal(supplyTkn.toNumber(), amountWei / ceiling, 'token wasn\'t issued');
    const reserveWei = await token.totalReserve.call();
    assert.equal(reserveWei.toNumber(), amountWei, 'ether wasn\'t sent to contract');
  });

  it('should allow to sell', async function() {
    // create contract and purchase tokens for 1 ether
    const token = await SafeToken.new();
    const floor = await token.floor.call();
    const ceiling = await token.ceiling.call();
    const amountWei = web3.toWei(1, 'ether');
    const halfAmountWei = web3.toWei(0.5, 'ether');
    const txHash = web3.eth.sendTransaction({ from: accounts[0], to: token.address, value: amountWei });
    await web3.eth.transactionMined(txHash);
    let balanceTkn = await token.balanceOf.call(accounts[0]);
    assert.equal(balanceTkn.toNumber(), amountWei / ceiling, 'token wasn\'t issued to account');
    // sell half of the tokens
    await token.sellTokens(balanceTkn.dividedBy(2));
    // check balance, supply
    balanceTkn = await token.balanceOf.call(accounts[0]);
    assert.equal(balanceTkn.toNumber(), halfAmountWei / floor, 'token wasn\'t deducted by sell');
    const supplyTkn = await token.totalSupply.call();
    assert.equal(supplyTkn.toNumber(), halfAmountWei / floor, 'token wasn\'t destroyed');
    // check allocation and reserve
    let allocationWei = await token.allocatedTo.call(accounts[0]);
    assert.equal(allocationWei.toNumber(), halfAmountWei, 'ether wasn\'t allocated for withdrawal');
    const reserveWei = await token.totalReserve.call();
    assert.equal(reserveWei.toNumber(), halfAmountWei, 'ether allocation wasn\'t deducted from reserve');
    // pull the ether from the account
    await token.claimEther();
    allocationWei = await token.allocatedTo.call(accounts[0]);
    assert.equal(allocationWei.toNumber(), 0, 'allocation wasn\'t payed out.');
  });

  it('allocate_funds_to_beneficiary and claim_revenue', async function() {
    // create token contract, default ceiling == floor
    const token = await SafeToken.new(accounts[1]);
    await token.moveCeiling(1500);
    const floor = await token.floor.call();
    const ceiling = await token.ceiling.call();
    assert.equal(ceiling.toNumber(), 1500, 'setting ceiling failed');
    const amountWei = web3.toWei(new BigNumber(1), 'ether');
    const txHash = web3.eth.sendTransaction({ from: accounts[0], to: token.address, value: amountWei });
    await web3.eth.transactionMined(txHash);
    const reserveWei = await token.totalReserve.call();
    assert.equal(reserveWei.toNumber(), amountWei.toNumber(), 'reserve incorrect');
    const balanceTkn = await token.balanceOf.call(accounts[0]);
    assert.equal(balanceTkn.toNumber(), amountWei.dividedBy(ceiling).floor().toNumber(), 'token wasn\'t issued to account');

    const revenueWei = amountWei.minus(balanceTkn.times(floor));
    await token.allocateEther(revenueWei);
    let allocatedWei = await token.allocatedTo.call(accounts[1]);
    assert.equal(allocatedWei.toNumber(), revenueWei, 'ether wasn\'t allocated to beneficiary');
    // pull the ether from the account
    await token.claimEther({ from: accounts[1] });
    allocatedWei = await token.allocatedTo.call(accounts[1]);
    assert.equal(allocatedWei.toNumber(), 0, 'allocation wasn\'t payed out.');
  });

  it('should handle The sale administrator sets floor = 0, ceiling = infinity', async function() {
    // create token contract, default ceiling == floor
    const token = await SafeToken.new();
    let ceiling = await token.ceiling.call();
    const amountWei = web3.toWei(1, 'ether');
    let txHash = web3.eth.sendTransaction({ from: accounts[0], to: token.address, value: amountWei });
    await web3.eth.transactionMined(txHash);
    const balanceTknBefore = await token.balanceOf.call(accounts[0]);
    assert.equal(balanceTknBefore.toNumber(), amountWei / ceiling, 'token wasn\'t issued to account');

    await token.moveFloor(0);
    const floor = await token.floor.call();
    ceiling = await token.ceiling.call();
    assert.equal(floor.toNumber(), 0, 'setting floor failed');
    assert.equal(ceiling.toNumber(), BYTES_32, 'setting ceiling failed');
    // try purchasing some tokens with ether
    try {
      txHash = web3.eth.sendTransaction({ from: accounts[0], to: token.address, value: amountWei });
      await web3.eth.transactionMined(txHash);
    } catch(error) {
      assertJump(error);
      // check balance, supply and reserve
      const balanceTknAfter = await token.balanceOf.call(accounts[0]);
      assert.equal(balanceTknAfter.toNumber(), balanceTknBefore, 'balance should stay same after failed purchase');
      const supplyTkn = await token.totalSupply.call();
      assert.equal(supplyTkn.toNumber(), balanceTknBefore, 'totalSupply should stay same after failed purchase');
      const reserveWei = await token.totalReserve.call();
      assert.equal(reserveWei.toNumber(), amountWei, 'ether should not have been deposited');
      return;
    }
    assert.fail('should have thrown before');
  });

  it('the sale administrator can’t raise the floor price if doing so would make it unable to purchase all of the tokens at the floor price', async function() {
    // create contract and buy some tokens
    const token = await SafeToken.new();
    let ceiling = await token.ceiling.call();
    const amountWei = web3.toWei(1, 'ether');
    const txHash = web3.eth.sendTransaction({ from: accounts[0], to: token.address, value: amountWei });
    await web3.eth.transactionMined(txHash);
    let supplyTkn = await token.totalSupply.call(accounts[0]);
    assert.equal(supplyTkn.toNumber(), amountWei / ceiling, 'amount wasn\'t issued to account');
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
    const token = await SafeToken.new(accounts[1]);
    await token.moveCeiling(1500);
    const floor = await token.floor.call();
    const ceiling = await token.ceiling.call();
    assert.equal(ceiling.toNumber(), 1500, 'setting ceiling failed');
    const amountWei = web3.toWei(new BigNumber(1), 'ether');
    const txHash = web3.eth.sendTransaction({ from: accounts[0], to: token.address, value: amountWei });
    await web3.eth.transactionMined(txHash);
    const reserveWei = await token.totalReserve.call();
    assert.equal(reserveWei.toNumber(), amountWei.toNumber(), 'reserve incorrect');
    const balanceTkn = await token.balanceOf.call(accounts[0]);
    assert.equal(balanceTkn.toNumber(), amountWei.dividedBy(ceiling).floor().toNumber(), 'token wasn\'t issued to account');

    const revenueWei = amountWei.minus(balanceTkn.times(floor));
    const doubleRevenueWei = revenueWei.times(2);
    try {
      await token.allocateEther(doubleRevenueWei);
    } catch(error) {
      return assertJump(error);
    }
    assert.fail('should have thrown before');
  });

  it('should return correct balances after transfer', async function() {
    // create contract and buy some tokens
    const token = await SafeToken.new();
    const ceiling = await token.ceiling.call();
    const amountWei = web3.toWei(1, 'ether');
    const txHash = web3.eth.sendTransaction({ from: accounts[0], to: token.address, value: amountWei });
    await web3.eth.transactionMined(txHash);
    let balanceTkn = await token.balanceOf.call(accounts[0]);
    assert.equal(balanceTkn.toNumber(), amountWei / ceiling.toNumber(), 'amount wasn\'t issued to account');
    // transfer token to other account
    const halfBalanceTkn = balanceTkn.dividedBy(2);
    let transfer = await token.transfer(accounts[1], halfBalanceTkn);

    // check balances of sender and recepient
    const newBalanceTkn = await token.balanceOf(accounts[0]);
    assert.equal(newBalanceTkn.toNumber(), halfBalanceTkn.toNumber(), 'amount hasn\'t been transfered');
    balanceTkn = await token.balanceOf(accounts[1]);
    assert.equal(balanceTkn.toNumber(), halfBalanceTkn.toNumber(), 'amount hasn\'t been received');
  });

  it('should throw an error when trying to transfer more than balance', async function() {
    const token = await SafeToken.new();
    try {
      await token.transfer(accounts[1], 101);
    } catch(error) {
      return assertJump(error);
    }
    assert.fail('should have thrown before');
  });

});
