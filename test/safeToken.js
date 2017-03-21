const SafeToken = artifacts.require("./SafeToken.sol");
const assertJump = require('./helpers/assertJump');
require('./helpers/transactionMined.js');

contract('SafeToken', function(accounts) {
  

  it("should allow to purchase", async function() {
    // create token contract, default ceiling == floor
    const token = await SafeToken.new();
    const ceiling = await token.ceiling.call();
    // purchase some tokens with ether
    const amount = web3.toWei(1, 'ether');
    const txHash = web3.eth.sendTransaction({ from: accounts[0], to: token.address, value: amount });
    await web3.eth.transactionMined(txHash);
    // check balance, supply and reserve
    const balance = await token.balanceOf.call(accounts[0]);
    assert.equal(balance.toNumber(), amount * ceiling, "token wasn't issued to account");
    const supply = await token.totalSupply.call();
    assert.equal(supply.toNumber(), amount * ceiling, "token wasn't issued");
    const reserve = await token.totalReserve.call();
    assert.equal(reserve.toNumber(), amount, "ether wasn't sent to contract");
  });

  it("should allow to sell", async function() {
    // create contract and purchase tokens for 1 ether
    const token = await SafeToken.new();
    const floor = await token.floor.call();
    const amount = web3.toWei(0.5, 'ether');
    const txHash = web3.eth.sendTransaction({ from: accounts[0], to: token.address, value: amount * 2 });
    await web3.eth.transactionMined(txHash);
    let balance = await token.balanceOf.call(accounts[0]);
    assert.equal(balance.toNumber(), amount * 2 * 10, "token wasn't issued to account");
    // sell half of the tokens
    await token.sellTokens(amount * floor);
    // check balance, supply
    balance = await token.balanceOf.call(accounts[0]);
    assert.equal(balance.toNumber(), amount * floor, "token wasn't deducted by sell");
    const supply = await token.totalSupply.call();
    assert.equal(supply.toNumber(), amount * floor, "token wasn't destroyed");
    // check allocation and reserve
    let allocation = await token.allocatedTo.call(accounts[0]);
    assert.equal(allocation.toNumber(), amount, "ether wasn't allocated for withdrawal");
    const reserve = await token.totalReserve.call();
    assert.equal(reserve.toNumber(), amount, "ether allocation wasn't deducted from reserve");
    // pull the ether from the account
    await token.claimEther();
    allocation = await token.allocatedTo.call(accounts[0]);
    assert.equal(allocation.toNumber(), 0, "allocation wasn't payed out.");
  });

  it("allocate_funds_to_beneficiary and claim_revenue");

  it("allocate_funds_to_beneficiary can not allocate to random address");

  it("should handle The sale administrator sets floor = 0, ceiling = infinity");

  it("the sale administrator can’t raise the floor price if doing so would make it unable to purchase all of the tokens at the floor price");

  it("allocate_funds_to_beneficiary fails if allocating those funds would mean that the sale mechanism is no longer able to buy back all ");

  it("should return correct balances after transfer", async function() {
    // create contract and buy some tokens   
    const token = await SafeToken.new();
    const ceiling = await token.ceiling.call();
    const amount = web3.toWei(1, 'ether');
    const txHash = web3.eth.sendTransaction({ from: accounts[0], to: token.address, value: 2 * amount / ceiling });
    await web3.eth.transactionMined(txHash);
    let balance = await token.balanceOf.call(accounts[0]);
    assert.equal(balance.toNumber(), 2 * amount, "amount wasn't issued to account");
    // transfer token to other account
    let transfer = await token.transfer(accounts[1], amount);

    // check balances of sender and recepient
    let firstAccountBalance = await token.balanceOf(accounts[0]);
    assert.equal(firstAccountBalance, amount);
    let secondAccountBalance = await token.balanceOf(accounts[1]);
    assert.equal(secondAccountBalance, amount);
  });

  it("should throw an error when trying to transfer more than balance", async function() {
    const token = await SafeToken.new();
    try {
      await token.transfer(accounts[1], 101);
    } catch(error) {
      return assertJump(error);
    }
    assert.fail('should have thrown before');
  });

});
