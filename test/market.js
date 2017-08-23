const Nutz = artifacts.require('./satelites/Nutz.sol');
const Storage = artifacts.require('./satelites/Storage.sol');
const PullPayment = artifacts.require('./satelites/PullPayment.sol');
const Market = artifacts.require('./controller/MarketEnabled.sol');
const BigNumber = require('bignumber.js');
const assertJump = require('./helpers/assertJump');
const INFINITY = '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';
const NTZ_DECIMALS = new BigNumber(10).pow(12);
const babz = (ntz) => new BigNumber(NTZ_DECIMALS).mul(ntz);
const ntz = (babz) => new BigNumber(babz).div(NTZ_DECIMALS);
const ONE_ETH = web3.toWei(1, 'ether');
const eth = (wei) => web3.fromWei(wei, 'ether');

contract('MarketEnabled', (accounts) => {
  let market;
  let nutz;
  let storage;
  let pull;

  beforeEach(async () => {
    nutz = await Nutz.new();
    storage = await Storage.new();
    pull = await PullPayment.new();
    market = await Market.new(pull.address, storage.address, nutz.address);
    nutz.transferOwnership(market.address);
    storage.transferOwnership(market.address);
    pull.transferOwnership(market.address);
    await market.unpause();
  });

  async function setSellPrice(newPrice) {
    await market.moveFloor(newPrice);
    await market.moveCeiling(newPrice);
  };

  describe('#purchase', () => {

    describe(`regular scenario. Purchase NTZ for 30000 NTZ/ETH with 1 ETH`, () => {
      const sellPrice = 30000;
      const expectedNumberOfNtz = 30000;

      beforeEach(async () => {
        await setSellPrice(sellPrice);
      });

      it('should change active supply', async() => {
        // purchase some tokens with 1 ether
        await nutz.purchase({ from: accounts[0], value: ONE_ETH });

        const supplyBabz = await nutz.activeSupply.call();
        assert.equal(supplyBabz.toNumber(), babz(expectedNumberOfNtz).toNumber(), 'active supply should include newly minted NTZ');
      });

      it('should not change purchase price', async() => {
        // purchase some tokens with 1 ether
        await nutz.purchase({ from: accounts[0], value: ONE_ETH });

        // we should be able to buy back issued NTZ by the same price
        const purchasePrice = await market.floor();
        assert.equal(purchasePrice.toNumber(), sellPrice, 'Purchase price should remain unchanged');
      });

      it('should sent ETH to the contract', async() => {
        // purchase some tokens with 1 ether
        await nutz.purchase({ from: accounts[0], value: ONE_ETH });

        const reserveWei = web3.eth.getBalance(market.address);
        assert.equal(reserveWei.toNumber(), ONE_ETH, '1 ETH should be sent to contract');
      });

      it('should add NTZ to the balance', async() => {
        // purchase tokens with 1 ether
        await nutz.purchase({ from: accounts[0], value: ONE_ETH });

        const balanceBabz = await nutz.balanceOf.call(accounts[0]);
        assert.equal(balanceBabz.toNumber(), babz(expectedNumberOfNtz).toNumber(), 'Purchased NTZ amount');
      });
    });


    const validScenarios = [
      { price: 30000, wei: ONE_ETH, expectedNtz: 30000 },
      { price: 5000, wei: ONE_ETH / 2000, expectedNtz: 2.5 },
      { price: 1, wei: ONE_ETH / 10 ** 12, expectedNtz: 1 / 10 ** 12 }
    ];

    for (var i = 0; i < validScenarios.length; i++) {
      let scenarioSpec = validScenarios[i];

      it(`should buy ${scenarioSpec.expectedNtz} NTZ for ${eth(scenarioSpec.wei)} ETH at the price ${scenarioSpec.price} NTZ/ETH`, async () => {
        await setSellPrice(scenarioSpec.price);
        await nutz.purchase({ from: accounts[0], value: scenarioSpec.wei });

        const balanceBabz = await nutz.balanceOf.call(accounts[0]);
        assert.equal(ntz(balanceBabz).toNumber(), scenarioSpec.expectedNtz, 'Purchased NTZ amount');
      });
    }

    it(`should not allow to buy less then 1 babz`, async () => {
      // set price to 1 NTZ/ETH, so 1 babz cost 1/10^12
      await setSellPrice(1);
      const babzCostWei = ONE_ETH / 10 ** 12;

      try {
        // try to buy tokens with amount of ether one wei short from enough to buy just 1 babz
        await nutz.purchase({ from: accounts[0], value: babzCostWei - 1 });
        assert.fail('should have thrown before');
      } catch(error) {
        assertJump(error);
      }
    });

  });

});
