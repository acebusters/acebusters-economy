contract('SafeToken', function(accounts) {

  it("should allow to purchase", function() {
    var safe = SafeToken.deployed();
    return safe.purchaseTokens({from: accounts[0], value: 5000}).then(function() {
      return safe.balanceOf.call(accounts[0]);
    }).then(function(balance) {
      assert.equal(balance.valueOf(), 50000, "50000 wasn't issued to account");
    });
  });

  it("should allow to sell", function() {
    var safe = SafeToken.deployed();
    return safe.sellTokens(2500).then(function() {
      return safe.balanceOf.call(accounts[0]);
    }).then(function(balance) {
      assert.equal(balance.valueOf(), 25000, "25000 wasn't deducted by sell");
    });
  });

  it("should send coin correctly", function() {
    var safe = SafeToken.deployed();

    // Get initial balances of first and second account.
    var account_one = accounts[0];
    var account_two = accounts[1];

    var account_one_starting_balance;
    var account_two_starting_balance;
    var account_one_ending_balance;
    var account_two_ending_balance;

    var amount = 10;

    return safe.balanceOf.call(account_one).then(function(balance) {
      account_one_starting_balance = balance.toNumber();
      return safe.balanceOf.call(account_two);
    }).then(function(balance) {
      account_two_starting_balance = balance.toNumber();
      return safe.transfer(account_two, amount, {from: account_one});
    }).then(function() {
      return safe.balanceOf.call(account_one);
    }).then(function(balance) {
      account_one_ending_balance = balance.toNumber();
      return safe.balanceOf.call(account_two);
    }).then(function(balance) {
      account_two_ending_balance = balance.toNumber();

      assert.equal(account_one_ending_balance, account_one_starting_balance - amount, "Amount wasn't correctly taken from the sender");
      assert.equal(account_two_ending_balance, account_two_starting_balance + amount, "Amount wasn't correctly sent to the receiver");
    });
  });
});
