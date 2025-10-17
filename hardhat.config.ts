import "@fhevm/hardhat-plugin";
import "@nomicfoundation/hardhat-chai-matchers";
import "@nomicfoundation/hardhat-ethers";
import dotenv from "dotenv";
import fs from "fs";
import path from "path";
import { HardhatUserConfig } from "hardhat/config";

dotenv.config();

const cacheConfigDir = path.join(__dirname, "fhevmTemp", "@fhevm", "solidity", "config");
const cacheConfigPath = path.join(cacheConfigDir, "FHEVMConfig.sol");

if (!fs.existsSync(cacheConfigPath)) {
  fs.mkdirSync(cacheConfigDir, { recursive: true });
  fs.writeFileSync(
    cacheConfigPath,
    [
      "// SPDX-License-Identifier: BSD-3-Clause-Clear",
      "pragma solidity ^0.8.24;",
      "",
      "import { FHE } from \"@fhevm/solidity/lib/FHE.sol\";",
      "import { ZamaConfig } from \"@fhevm/solidity/config/ZamaConfig.sol\";",
      "",
      "contract SepoliaFHEVMConfig {",
      "    constructor() {",
      "        FHE.setCoprocessor(ZamaConfig.getSepoliaConfig());",
      "    }",
      "",
      "    function protocolId() public pure returns (uint256) {",
      "        return ZamaConfig.getSepoliaProtocolId();",
      "    }",
      "}",
      "",
    ].join("\n"),
    { encoding: "utf8" },
  );
}

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.28",
    settings: {
      evmVersion: "cancun", // FHEVM requires Cancun fork
    },
  },
  networks: {
    sepolia: {
      url: process.env.SEPOLIA_RPC_URL || "",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      chainId: 11155111,
    },
  },
};

export default config;
