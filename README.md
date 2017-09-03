[![Run Status](https://api.shippable.com/projects/58edf58cbe95a307002d2864/badge?branch=master)](https://app.shippable.com/github/acebusters/economy)
[![Coverage Badge](https://api.shippable.com/projects/58edf58cbe95a307002d2864/coverageBadge?branch=master)](https://app.shippable.com/github/acebusters/economy)

## Safe Token Sale

- idea according to [Vlad Zamfir's Safe Token Sale](https://medium.com/@Vlad_Zamfir/a-safe-token-sale-mechanism-8d73c430ddd1).
- extended with Power concept: [Acebusters Economy Paper](http://www.acebusters.com/files/The%20Acebusters%20Economy.pdf)
- [javascript simulator](http://acebusters.com/economy.html)

### installation

```
npm install
```

### run tests

```
npm test
```

or run individual tests like this:

```
npm test test/nutz.js
```

To avoid recompiling contracts all the time, consider patching truffle with supplied patch:
```
patch node_modules/truffle/build/cli.bundled.js truffle-test-cache.patch
```

### code coverage

```
npm run coverage
```

Executes instrumented tests on a separate testrpc. Coverage report is dumped to the terminal and into `coverage/index.html` (Istanbul HTML format)

## License
Code released under the [MIT License](https://github.com/acebusters/safe-token-sale/blob/master/LICENSE).
