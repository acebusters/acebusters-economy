require('babel-register');
require('babel-polyfill');

var mochaConfig = {};

if (process.env.CI_BUILD) {
  // Shippable CI likes test results in xunit format
  mochaConfig = {
    reporter: 'xunit',
    reporterOptions: {
      output: 'xunit_testresults.xml'
    }
  };
}

module.exports = {
  networks: {
    development: {
      host: "localhost",
      port: 8545,
      network_id: "*" // Match any network id
    },
    coverage: {
      host: "localhost",
      network_id: "*",
      port: 8555,
      gas: 0xfffffffffff,
      gasPrice: 0x01
    }
  },
  mocha: mochaConfig
};
