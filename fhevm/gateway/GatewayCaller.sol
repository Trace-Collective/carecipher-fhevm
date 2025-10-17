// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.24;

import { euint16 } from "@fhevm/solidity/lib/FHE.sol";

interface IGateway {
    function requestDecryption(
        uint256[] calldata ctsHandles,
        bytes4 callbackSelector,
        uint256 userData,
        uint256 deadline,
        bool keepInGateway
    ) external returns (uint256);
}

library Gateway {
    bytes32 private constant GATEWAY_STORAGE_SLOT = keccak256("carecipher.fhevm.gateway");

    struct Layout {
        address gateway;
    }

    function _layout() private pure returns (Layout storage l) {
        bytes32 slot = GATEWAY_STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }

    function setGateway(address gatewayAddress) internal {
        _layout().gateway = gatewayAddress;
    }

    function addressOf() internal view returns (address) {
        return _layout().gateway;
    }

    function toUint256(euint16 value) internal pure returns (uint256[] memory handles) {
        handles = new uint256[](1);
        handles[0] = uint256(euint16.unwrap(value));
    }

    function requestDecryption(
        uint256[] memory ctsHandles,
        bytes4 callbackSelector,
        uint256 userData,
        uint256 deadline,
        bool keepInGateway
    ) internal returns (uint256) {
        address gateway = addressOf();
        if (gateway == address(0)) {
            revert("Gateway not configured");
        }
        return IGateway(gateway).requestDecryption(ctsHandles, callbackSelector, userData, deadline, keepInGateway);
    }
}

abstract contract GatewayCaller {
    error GatewayNotConfigured();
    error UnauthorizedGateway(address caller);

    address internal constant SEPOLIA_GATEWAY = 0x33347831500F1e73f0ccCBb95c9f86B94d7b1123;

    constructor() {
        if (SEPOLIA_GATEWAY == address(0)) {
            revert GatewayNotConfigured();
        }
        Gateway.setGateway(SEPOLIA_GATEWAY);
    }

    function gatewayAddress() public view returns (address) {
        return Gateway.addressOf();
    }

    modifier onlyGateway() {
        if (msg.sender != Gateway.addressOf()) {
            revert UnauthorizedGateway(msg.sender);
        }
        _;
    }
}
