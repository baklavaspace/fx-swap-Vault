// require("@nomiclabs/hardhat-waffle");    // redundant - replaced by toolbox
// require('@nomiclabs/hardhat-ethers');    // redundant - replaced by toolbox
// require("@nomiclabs/hardhat-etherscan"); // redundant - replaced by toolbox

require("@nomicfoundation/hardhat-toolbox")
require('@openzeppelin/hardhat-upgrades');

const ALCHEMY_API_KEY = "";
const ETH_ALCHEMY_API_KEY = "";

const fs = require('fs');
const MAINNET_PRIVATE_KEY = fs.readFileSync(".secret").toString().trim();
const TESTNET_PRIVATE_KEY = fs.readFileSync(".secret").toString().trim();

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: {
    version: "0.8.18",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  }, 
  networks: {
    mainnet: {
      // url: `https://goerli.infura.io/v3/3f6bc0d4637344c8b7efd24e118a5c45`,
      url: `https://eth-mainnet.g.alchemy.com/v2/${ETH_ALCHEMY_API_KEY}`,
      // url: `https://rpc.ankr.com/eth_goerli`,
      accounts: [MAINNET_PRIVATE_KEY],
      networkCheckTimeout: 999999,
      timeoutBlocks: 200,
      gas: 12400000,
      gasPrice: 17000000000,
    },
    goerli: {
      // url: `https://goerli.infura.io/v3/3f6bc0d4637344c8b7efd24e118a5c45`,
      url: `https://eth-goerli.alchemyapi.io/v2/${ALCHEMY_API_KEY}`,
      // url: `https://rpc.ankr.com/eth_goerli`,
      accounts: [TESTNET_PRIVATE_KEY],
      networkCheckTimeout: 999999,
      timeoutBlocks: 200,
      gas: 12400000,
      gasPrice: 20000000000,
    },
    avalancheFujiTestnet: {
      // url: `https://api.avax-test.network/ext/bc/C/rpc`,
      url: `https://rpc.ankr.com/avalanche_fuji`,
      accounts: [TESTNET_PRIVATE_KEY]
    },
    avalanche: {
      url: `https://rpc.ankr.com/avalanche`,
      accounts: [MAINNET_PRIVATE_KEY],
      gasPrice: 28000000000,
    },
    fxTestnet: {
      url: `https://testnet-fx-json-web3.functionx.io:8545`,
      accounts: [TESTNET_PRIVATE_KEY],
      networkCheckTimeout: 999999,
      timeoutBlocks: 200,
      gas: 12400000,
      gasPrice: 600000000000,
    },
    fxMainnet: {
      url: `https://fx-json-web3.functionx.io:8545`,
      accounts: [MAINNET_PRIVATE_KEY],
      networkCheckTimeout: 999999,
      timeoutBlocks: 200,
      gas: 12400000,
      gasPrice: 505000000000,
    }
  },
  etherscan: {
    // Your API key for Etherscan
    // Obtain one at https://etherscan.io/
    // apiKey: ""
    apiKey: {
      mainnet: "YOUR_ETHERSCAN_API_KEY",
      optimisticEthereum: "YOUR_OPTIMISTIC_ETHERSCAN_API_KEY",
      arbitrumOne: "YOUR_ARBISCAN_API_KEY",
      bscTestnet: "YOUR_BSCSCAN_API_KEY",
      avalancheFujiTestnet: "YOUR_SNOWTRACE_API_KEY", 
      avalanche: "YOUR_SNOWTRACE_API_KEY"
    }
  },
  mocha: {
    timeout: 40000
  }
};
