const Migrations = artifacts.require('./Migrations.sol')

module.exports = (deployer, network, accounts) => {
  deployer.deploy(Migrations, { gas: 2e5 })
}
