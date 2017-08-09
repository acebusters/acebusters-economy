require('babel-register');
require('babel-polyfill');

var mochaConfig = {};

if (process.env.CI_BUILD) {
  // Solcover executes in a temporary coverageEnv directory which is being deleted after run
  // Let's escape from that
  var resultDir = process.cwd().endsWith('coverageEnv') ? '../' : './';

  // Shippable CI likes test results in xunit format
  mochaConfig = {
    reporter: 'xunit',
    reporterOptions: {
      output: resultDir + 'xunit_testresults.xml'
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
