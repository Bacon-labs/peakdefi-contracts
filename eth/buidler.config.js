usePlugin('@nomiclabs/buidler-truffle5')

let secret

try {
  secret = require('./secret.json')
} catch {
  secret = {
    account: '',
    mnemonic: ''
  }
}

module.exports = {
  solc: {
    version: '0.5.17',
    optimizer: {
      enabled: true,
      runs: 200
    }
  },
  networks: {
    ganache: {
      url: 'http://localhost:8545'
    },
    rinkeby: {
      url: 'https://rinkeby.infura.io/v3/2f4ac5ce683c4da09f88b2b564d44199',
      gasPrice: 1e9,
      gas: 'auto',
      from: secret.account,
      accounts: {
        mnemonic: secret.mnemonic
      }
    }
  }
}
