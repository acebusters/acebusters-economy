const Nutz = artifacts.require('./Nutz.sol');
const NutzMock = artifacts.require('./helpers/NutzMock.sol');
const ERC223ReceiverMock = artifacts.require('./helpers/ERC223ReceiverMock.sol');
const assertJump = require('./helpers/assertJump');
const BigNumber = require('bignumber.js');
require('./helpers/transactionMined.js');
const INFINITY = '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';
const NTZ_DECIMALS = new BigNumber(10).pow(12);
const babz = (ntz) => new BigNumber(NTZ_DECIMALS).mul(ntz);
const PRICE_FACTOR = new BigNumber(10).pow(6);
const ONE_ETH = web3.toWei(1, 'ether');

contract('Nutz', (accounts) => {

  it('should allow to purchase', async () => {
    // create token contract
    const ceiling = new BigNumber(30000);
    const token = await NutzMock.new(0, 0, ceiling, INFINITY);
    // purchase some tokens with ether
    const txHash = web3.eth.sendTransaction({ from: accounts[0], to: token.address, value: ONE_ETH });
    await web3.eth.transactionMined(txHash);
    // check balance, supply and reserve
    const babzBalance = await token.balanceOf.call(accounts[0]);
    assert.equal(babzBalance.toNumber(), ceiling.mul(NTZ_DECIMALS).toNumber(), 'token wasn\'t issued to account');
    const supplyBabz = await token.activeSupply.call();
    assert.equal(supplyBabz.toNumber(), ceiling.mul(NTZ_DECIMALS).toNumber(), 'token wasn\'t issued');
    const reserveWei = await token.reserve.call();
    assert.equal(reserveWei.toNumber(), ONE_ETH, 'ether wasn\'t sent to contract');
  });

  it('should allow to sell', async () => {
    // create contract and purchase tokens for 1 ether
    const ceiling = new BigNumber(1000);
    const token = await NutzMock.new(0, 0, ceiling, 1000);
    const txHash = web3.eth.sendTransaction({ from: accounts[0], to: token.address, value: ONE_ETH });
    await web3.eth.transactionMined(txHash);
    let babzBalance = await token.balanceOf.call(accounts[0]);
    assert.equal(babzBalance.toNumber(), ceiling.mul(ONE_ETH).div(PRICE_FACTOR).toNumber(), 'token wasn\'t issued to account');
    // sell half of the tokens
    await token.transfer(token.address, babzBalance.div(2), "0x00");
    // check balance, supply
    let newBabzBal = await token.balanceOf.call(accounts[0]);
    assert.equal(newBabzBal.toNumber(), babzBalance.div(2).toNumber(), 'token wasn\'t deducted by sell');
    const supplyBabz = await token.activeSupply.call();
    assert.equal(supplyBabz.toNumber(), babzBalance.div(2).toNumber(), 'token wasn\'t destroyed');
    // check allocation and reserve
    let allocationWei = await token.allowance.call(token.address, accounts[0]);
    const HALF_ETH = web3.toWei(0.5, 'ether');
    assert.equal(allocationWei.toString(), HALF_ETH, 'ether wasn\'t allocated for withdrawal');
    const reserveWei = await token.reserve.call();
    assert.equal(reserveWei.toString(), HALF_ETH, 'ether allocation wasn\'t deducted from reserve');
    // pull the ether from the account
    await token.transferFrom(token.address, accounts[0], 0);
    allocationWei = await token.allowance.call(token.address, accounts[0]);
    assert.equal(allocationWei.toNumber(), 0, 'allocation wasn\'t payed out.');
    // TODO: check my ether balance increased
  });

  it('setting floor to infinity should disable sell', async () => {
    // create contract and purchase tokens for 1 ether
    const token = await NutzMock.new(0, 0, 1000, 1000);
    const txHash = web3.eth.sendTransaction({ from: accounts[0], to: token.address, value: ONE_ETH });
    await web3.eth.transactionMined(txHash);
    let babzBalance = await token.balanceOf.call(accounts[0]);
    assert.equal(babzBalance, babz(1000).toNumber(), 'token wasn\'t issued to account');
    // set floor to infinity
    await token.moveFloor(INFINITY);
    // try sell half of the tokens
    try {
      await token.transfer(token.address, babzBalance.div(2), "0x00");
    } catch(error) {
      return assertJump(error);
    }
    assert.fail('should have thrown before');
  });

  it('setting floor to infinity should disable claim', async () => {
    // create contract and purchase tokens for 1 ether
    const token = await NutzMock.new(0, 0, 1000, 1000);
    const txHash = web3.eth.sendTransaction({ from: accounts[0], to: token.address, value: ONE_ETH });
    await web3.eth.transactionMined(txHash);
    let babzBalance = await token.balanceOf.call(accounts[0]);
    assert.equal(babzBalance, babz(1000).toNumber(), 'token wasn\'t issued to account');
    // try sell half of the tokens
    await token.transfer(token.address, babzBalance.div(2), "0x00");
    // set floor to infinity
    await token.moveFloor(INFINITY);
    try {
      await token.transferFrom(token.address, accounts[0], 0);
    } catch(error) {
      return assertJump(error);
    }
    assert.fail('should have thrown before');
  });

  it('should call erc223 when purchase', async () => {
    let receiver = await ERC223ReceiverMock.new();
    const token = await NutzMock.new(0, 0, 1500, INFINITY);
    const txHash = web3.eth.sendTransaction({ from: accounts[0], to: receiver.address, value: ONE_ETH });
    await web3.eth.transactionMined(txHash);
    await receiver.forward(token.address, ONE_ETH);
    const isCalled = await receiver.called.call();
    assert(isCalled, 'erc223 interface has not been invoked on purchase');
  });

  it('should allow to disable transfer to non-contract accounts.', async () => {
    const token = await NutzMock.new(0, babz(12000), 0, INFINITY);
    const bal = await token.balanceOf.call(accounts[0]);
    await token.setOnlyContractHolders(true);
    try {
      await token.transfer(accounts[1], bal.div(2), "0x00");
    } catch(error) {
      return assertJump(error);
    }
    assert.fail('should have thrown before');
  });

  it('should adjust getFloor automatically when active supply inflated', async () => {
    // create token contract, and issue some tokens that are not backed by ETH
    const token = await NutzMock.new(0, babz(12000), 12000, 15000);
    // purchase some tokens with ether
    const txHash = web3.eth.sendTransaction({ from: accounts[0], to: token.address, value: ONE_ETH });
    await web3.eth.transactionMined(txHash);
    
    const bal = await token.balanceOf.call(accounts[0]);
    // sell more tokens than issued by eth
    await token.transfer(token.address, bal, "0x00");
    const reserve = await token.reserve.call();
    assert.equal(reserve.toNumber(), 0, 'reserve has not been emptied');
  });

  it('allocate_funds_to_beneficiary and claim_revenue', async () => {
    // create token contract, default ceiling == floor
    const ceiling = new BigNumber(1500);
    const token = await NutzMock.new(0, 0, ceiling, 3000);
    // purchase NTZ for 1 ETH
    const txHash = web3.eth.sendTransaction({ from: accounts[0], to: token.address, value: ONE_ETH });
    await web3.eth.transactionMined(txHash);
    const floor = await token.floor.call();
    const reserveWei = await token.reserve.call();
    assert.equal(reserveWei.toNumber(), ONE_ETH, 'reserve incorrect');
    const babzBalance = await token.balanceOf.call(accounts[0]);
    assert.equal(babzBalance.toNumber(), ceiling.mul(ONE_ETH).div(PRICE_FACTOR).toNumber(), 'token wasn\'t issued to account');

    const revenueWei = new BigNumber(ONE_ETH).minus(babzBalance.div(floor).mul(PRICE_FACTOR));
    await token.allocateEther(revenueWei, accounts[1]);
    let allocatedWei = await token.allowance.call(token.address, accounts[1]);
    assert.equal(allocatedWei.toNumber(), revenueWei.toNumber(), 'ether wasn\'t allocated to beneficiary');
    // pull the ether from the account
    await token.transferFrom(token.address, accounts[1], 0, { from: accounts[1] });
    allocatedWei = await token.allowance.call(token.address, accounts[1]);
    assert.equal(allocatedWei.toNumber(), 0, 'allocation wasn\'t payed out.');
    // TODO: check ether balance actually increased
  });

  it('should handle The sale administrator sets floor = infinity, ceiling = 0', async () => {
    // create token contract, default ceiling == floor
    let ceiling = new BigNumber(100);
    const token = await NutzMock.new(0, 0, ceiling, INFINITY);
    let txHash = web3.eth.sendTransaction({ from: accounts[0], to: token.address, value: ONE_ETH });
    await web3.eth.transactionMined(txHash);
    const babzBalanceBefore = await token.balanceOf.call(accounts[0]);
    assert.equal(babzBalanceBefore.toNumber(), ceiling.mul(ONE_ETH).div(PRICE_FACTOR).toNumber(), 'token wasn\'t issued to account');
    await token.moveFloor(INFINITY);
    const floor = await token.floor.call();
    await token.moveCeiling(0);
    ceiling = await token.ceiling.call();
    assert.equal(floor.toNumber(), INFINITY, 'setting floor failed');
    assert.equal(ceiling.toNumber(), 0, 'setting ceiling failed');
    // try purchasing some tokens with ether
    try {
      txHash = web3.eth.sendTransaction({ from: accounts[0], to: token.address, value: ONE_ETH });
      await web3.eth.transactionMined(txHash);
    } catch(error) {
      assertJump(error);
      // check balance, supply and reserve
      const babzBalanceAfter = await token.balanceOf.call(accounts[0]);
      assert.equal(babzBalanceAfter.toNumber(), babzBalanceBefore, 'balance should stay same after failed purchase');
      const supplyBabz = await token.activeSupply.call();
      assert.equal(supplyBabz.toNumber(), babzBalanceBefore, 'activeSupply should stay same after failed purchase');
      const reserveWei = await token.reserve.call();
      assert.equal(reserveWei.toNumber(), ONE_ETH, 'ether should not have been deposited');
      return;
    }
    assert.fail('should have thrown before');
  });

  it('the sale administrator can’t raise the floor price if doing so would make it unable to purchase all of the tokens at the floor price', async () => {
    // create contract and buy some tokens
    let ceiling = new BigNumber(4000);
    const token = await NutzMock.new(0, 0, ceiling, INFINITY);
    const txHash = web3.eth.sendTransaction({ from: accounts[0], to: token.address, value: ONE_ETH });
    await web3.eth.transactionMined(txHash);
    let supplyBabz = await token.activeSupply.call(accounts[0]);
    const reserveWei = await token.reserve.call();
    assert.equal(supplyBabz.toNumber(), ceiling.mul(ONE_ETH).div(PRICE_FACTOR).toNumber(), 'amount wasn\'t issued to account');
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

  it('allocate_funds_to_beneficiary fails if allocating those funds would mean that the sale mechanism is no longer able to buy back all outstanding tokens',  async () => {
    // create token contract, default ceiling == floor
    const ceiling = new BigNumber(1500);
    const token = await NutzMock.new(0, 0, ceiling, 2000);
    const txHash = web3.eth.sendTransaction({ from: accounts[0], to: token.address, value: ONE_ETH });
    await web3.eth.transactionMined(txHash);
    const floor = await token.floor.call();
    const reserveWei = await token.reserve.call();
    assert.equal(reserveWei.toNumber(), ONE_ETH, 'reserve incorrect');
    const babzBalance = await token.balanceOf.call(accounts[0]);
    assert.equal(babzBalance.toNumber(), ceiling.mul(ONE_ETH).div(PRICE_FACTOR).toNumber(), 'token wasn\'t issued to account');

    const revenueWei = new BigNumber(ONE_ETH).minus(babzBalance.times(floor));
    const doublerevenueWei = revenueWei.times(2);
    try {
      await token.allocateEther(doublerevenueWei, accounts[1]);
    } catch(error) {
      return assertJump(error);
    }
    assert.fail('should have thrown before');
  });

  it('should return correct balances after transfer', async () => {
    // create contract and buy some tokens
    const ceiling = new BigNumber(100);
    const token = await NutzMock.new(0, 0, ceiling, INFINITY);
    const txHash = web3.eth.sendTransaction({ from: accounts[0], to: token.address, value: ONE_ETH });
    await web3.eth.transactionMined(txHash);
    let babzBalance = await token.balanceOf.call(accounts[0]);
    assert.equal(babzBalance.toNumber(), ceiling.mul(ONE_ETH).div(PRICE_FACTOR).toNumber(), 'amount wasn\'t issued to account');
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
