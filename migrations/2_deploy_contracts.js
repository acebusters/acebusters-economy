var Nutz = artifacts.require("./contracts/satelites/Nutz.sol");
var Power = artifacts.require("./contracts/satelites/Power.sol");
var PullPayment = artifacts.require("./contracts/satelites/PullPayment.sol");
var Storage = artifacts.require("./contracts/satelites/Storage.sol");
var Controller = artifacts.require("./contracts/controller/Controller.sol");

module.exports = function(deployer, network, accounts) {
  let controller;
  deployer.deploy([Nutz, Power, PullPayment, Storage]).then(function() {
    return deployer.deploy(Controller, Power.address, PullPayment.address, Nutz.address, Storage.address);
  }).then(function() {
    return Controller.deployed();
  }).then(function(_controller){
    controller = _controller;
    return Nutz.deployed();
  }).then(function(nutz) {
    nutz.transferOwnership(controller.address);
    return Power.deployed();
  }).then(function(power) {
    power.transferOwnership(controller.address);
    return PullPayment.deployed();
  }).then(function(pull) {
    pull.transferOwnership(controller.address);
    return Storage.deployed();
  }).then(function(storage) {
    storage.transferOwnership(controller.address);
    return controller.unpause();
  });
};
