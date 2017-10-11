const fromCents = function fromCents(cents) {
  return cents.div(Math.pow(10, 12));
}

const printValue = function printValue(cents, ticker) {
  const l = fromCents(cents).toString().length;
  let tabs = `\t\t\t`;
  if (l > 13) tabs = '\t\t';
  if (l >= 19) tabs = '\t';
  if (l < 4) tabs = '\t\t\t\t';
  return `${fromCents(cents)} ${ticker}${tabs} ${cents}`;
}

const printEconomy = async function(controller, nutz, power, user) {
  console.log(`---`);
  console.log(`Complete supply babz:\t ${printValue(await controller.completeSupply.call(), 'NTZ')}`);
  console.log(`Active supply babz:\t ${printValue(await controller.activeSupply.call(), 'NTZ')}`);
  console.log(`Total power:\t\t ${printValue(await power.totalSupply.call(), 'ABP')}`);
  console.log(`Authorized power:\t ${printValue(await controller.authorizedPower.call(), 'ABP')}`);
  console.log(`Outstanding power:\t ${printValue(await controller.outstandingPower.call(), 'ABP')}`);
  console.log(`Power pool:\t\t ${printValue(await controller.powerPool.call(), 'NTZ')}`);
  console.log(`Burn pool:\t\t ${printValue(await controller.burnPool.call(), 'NTZ')}`);

  if (user) {
    console.log(`User Babz:\t\t ${printValue(await nutz.balanceOf.call(user), 'NTZ')}`);
    let userPower = await power.balanceOf.call(user);
    console.log(`User Power:\t\t ${printValue(userPower, 'ABP')}`);
    console.log(`Babz for power down?:\t ${printValue(userPower.mul(await controller.completeSupply.call()).div(await controller.authorizedPower.call()), 'NTZ')}`)
  }
  console.log(`---`);
}

module.exports = {
  printValue, printEconomy, fromCents
}
