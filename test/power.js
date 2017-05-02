const SafeToken = artifacts.require('./SafeToken.sol');
const Power = artifacts.require('./Power.sol');

contract('Power', function(accounts) {
  

  it('should init contract', async function() {
    const token = await SafeToken.new(0);
    const power = await Power.new(token.address, 1, 1000);
    const max = await power.maxPower.call();
    assert.equal(max.toNumber(), 100, 'maxPower wasn\'t initialized');
    const outstanding = await power.balanceOf.call(token.address);
    assert.equal(outstanding.toNumber(), 1000, 'outstanding shares haven\'t been initialized');
  });

});
