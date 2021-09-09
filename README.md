# How it works
This project uses a slightly modified version of the [opyn perpetual vault template](https://github.com/opynfinance/perp-vault-templates).

Modifications made to the opyn perp vault template allow commiting of two oTokens to allow for more complex strategy like [straddles](https://www.investopedia.com/terms/s/straddle.asp), [strangles](https://www.investopedia.com/terms/s/strangle.asp) etc.

When deposits are made into the vault , the vault owner can mint a FIRB to earn fixed yield and MPH Reward which is used to mint and sell options to earn premium or purchase options which are cash settled in the event they expire ITM.

This strategy basically is a principal protected note because the depositor is assured of a certain percentage of their deposits.

# Status
This project is currently a WIP and is not currently safe to use.

# Todo
- Add More Test
Though locally tested, more integration tests needs to be carried out.

- Architecture/Design
Make the contract architecture more flexible

# Advanced Sample Hardhat Project

This project demonstrates an advanced Hardhat use case, integrating other tools commonly used alongside Hardhat in the ecosystem.

The project comes with a sample contract, a test for that contract, a sample script that deploys that contract, and an example of a task implementation, which simply lists the available accounts. It also comes with a variety of other tools, preconfigured to work with the project code.

Try running some of the following tasks:

```shell
npx hardhat accounts
npx hardhat compile
npx hardhat clean
npx hardhat test
npx hardhat node
npx hardhat help
REPORT_GAS=true npx hardhat test
npx hardhat coverage
npx hardhat run scripts/deploy.js
node scripts/deploy.js
npx eslint '**/*.js'
npx eslint '**/*.js' --fix
npx prettier '**/*.{json,sol,md}' --check
npx prettier '**/*.{json,sol,md}' --write
npx solhint 'contracts/**/*.sol'
npx solhint 'contracts/**/*.sol' --fix
```

# Etherscan verification

To try out Etherscan verification, you first need to deploy a contract to an Ethereum network that's supported by Etherscan, such as Ropsten.

In this project, copy the .env.template file to a file named .env, and then edit it to fill in the details. Enter your Etherscan API key, your Ropsten node URL (eg from Alchemy), and the private key of the account which will send the deployment transaction. With a valid .env file in place, first deploy your contract:

```shell
hardhat run --network ropsten scripts/deploy.js
```

Then, copy the deployment address and paste it in to replace `DEPLOYED_CONTRACT_ADDRESS` in this command:

```shell
npx hardhat verify --network ropsten DEPLOYED_CONTRACT_ADDRESS "Hello, Hardhat!"
```
