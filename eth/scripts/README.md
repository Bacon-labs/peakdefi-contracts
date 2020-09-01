# Deployment Readme

This is the guide to deploying the smart contracts on Ethereum Mainnet.

## 1. Deploy PEAK-USDC UniswapOracle

### Precondition

The PEAK-USDC Uniswap V2 pair must have been deployed on Ethereum Mainnet and has liquidity.

`secret.json` is put under `eth/`, which contains the mnemonics for the deployer account in the format

```json
{
    "account": "0x123456",
    "mnemonic": "some mnemonic"
}
```

### Script

Under `eth/`, run

```bash
npx buidler run scripts/deploy-oracle.js --network mainnet
```

## 2. Deploy BetokenFactory

### Precondition

Finished step 1.

Replaced `MARKETPEAK_WALLET_ADDR` and `PEAK_UNISWAP_ORACLE_ADDR` in `deployment-configs/mainnet-factory.json` with the correct values.

### Script

Under `eth/`, run

```bash
npx buidler run scripts/deploy-mainnet-factory.js --network mainnet
```

### Things to do after

Give `PeakStaking` and `PeakReward` the minter role in the MarketPeak token contract.

The deployer address now has the signer role in `PeakReward`, meaning it can initialize the referral structure. Call `PeakReward.register()` for each referral pair. Call `PeakReward.renounceSignerRole()` to give up the right to do so after initialization.

## 3. Deploy BetokenFund

### Precondition

Finished step 2.

Replaced all the values in `deployment-configs/mainnet-fund.json` with the desired values.

### Script

Under `eth/`, run

```bash
npx buidler run scripts/deploy-mainnet-fund.js --network mainnet
```

### Things to do after

The deployer account now has ownership of `BetokenFund`, which gives admin rights. Transfer the ownership to your desired account.
