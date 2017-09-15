var Nutz = artifacts.require("./contracts/satelites/Nutz.sol");
var Power = artifacts.require("./contracts/satelites/Power.sol");
var PullPayment = artifacts.require("./contracts/satelites/PullPayment.sol");
var Storage = artifacts.require("./contracts/satelites/Storage.sol");
var Controller = artifacts.require("./contracts/controller/Controller.sol");

module.exports = function(deployer, network, accounts) {
  let power, pull, nutz, storage;
  deployer.deploy(Nutz)
  .then(function() {
    return deployer.deploy(Power);
  }).then(function() {
    return deployer.deploy(PullPayment);
  }).then(function() {
    return deployer.deploy(Storage);
  }).then(function() {
    return Nutz.deployed();
  }).then(function(_nutz) {
    nutz = _nutz;
    return Power.deployed();
  }).then(function(_power) {
    power = _power;
    return PullPayment.deployed();
  }).then(function(_pull) {
    pull = _pull;
    return Storage.deployed();
  }).then(function(_storage) {
    storage = _storage;
    return deployer.deploy(Controller, power.address, pull.address, nutz.address, storage.address);
  }).then(function() {
    return Controller.deployed();
  }).then(function(controller){
    console.log('Transfering satellites\' ownership to Controller..');
    nutz.transferOwnership(controller.address);
    power.transferOwnership(controller.address);
    pull.transferOwnership(controller.address);
    storage.transferOwnership(controller.address);
    console.log('Unpausing Controller..');
    return controller.unpause();
  });
};
