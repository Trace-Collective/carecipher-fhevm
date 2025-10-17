// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.24;

import { FHE } from "@fhevm/solidity/lib/FHE.sol";
import { ZamaConfig } from "@fhevm/solidity/config/ZamaConfig.sol";

contract SepoliaFHEVMConfig {
    constructor() {
        FHE.setCoprocessor(ZamaConfig.getSepoliaConfig());
    }

    function protocolId() public pure returns (uint256) {
        return ZamaConfig.getSepoliaProtocolId();
    }
}
