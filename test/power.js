const Nutz = artifacts.require('./Nutz.sol');
const Power = artifacts.require('./Power.sol');
require('./helpers/transactionMined.js');

contract('Power', (accounts) => {

  it('should init contract', async () => {
    const downtime = 12*7*24*3600; // 3 month
    const token = await Nutz.new(downtime);
    const powerAddr = await token.powerAddr.call();
    const power = Power.at(powerAddr);
    await token.dilutePower(10000);
    const authorizedShares = await power.totalSupply.call();
    assert.equal(authorizedShares.toNumber(), 10000, 'shares not authorized');
  });

  it("should allow to power up and power down.", async () => {
    const downtime = 12*7*24*3600; // 3 month
    const benefitiary = accounts[1];
    const token = await Nutz.new(downtime);
    await token.moveCeiling(100);
    const powerAddr = await token.powerAddr.call();
    const power = Power.at(powerAddr);
    await token.dilutePower(10000);
    
    // get some tokens
    let txHash = web3.eth.sendTransaction({ gas: 200000, from: accounts[0], to: token.address, value: 10000000 });
    await web3.eth.transactionMined(txHash);
    let ntzBal = await token.balanceOf.call(accounts[0]);
    assert.equal(ntzBal.toNumber(), 100000, 'purchase failed');

    // powerup these tokens and check shares
    await token.transfer(power.address, 200);
    let powBal = await power.balanceOf.call(accounts[0]);
    assert.equal(powBal.toNumber(), 20, 'first power up failed');

    // power up some tokens with other account
    txHash = web3.eth.sendTransaction({ gas: 200000, from: accounts[3], to: token.address, value: 10000000 });
    await web3.eth.transactionMined(txHash);
    
    await token.transfer(power.address, 400, {from: accounts[3]});
    powBal = await power.balanceOf.call(accounts[3]);
    assert.equal(powBal.toNumber(), 19, 'second power up failed');

    // power down and check
    await power.transfer(token.address, 11);
    await power.downTickTest(0, (Date.now() / 1000 | 0) + downtime);
    powBal = await power.balanceOf.call(accounts[0]);
    assert.equal(powBal.toNumber(), 9, 'power down failed in Power contract');
    // check balances in token contract
    ntzBal = await token.balanceOf.call(accounts[0]);
    assert.equal(ntzBal.toNumber(), 100020, 'power down failed in Nutz contract');
    const ts = await token.activeSupply.call();
    assert.equal(ts.toNumber(), 200000, 'config failed.');
  });

});
