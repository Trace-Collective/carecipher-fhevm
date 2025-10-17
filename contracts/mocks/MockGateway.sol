// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract MockGateway {
    struct Request {
        address target;
        bytes4 callback;
        uint256 userData;
        uint256 deadline;
        bool keepInGateway;
        uint256[] handles;
    }

    uint256 public nextRequestId;
    mapping(uint256 => Request) public requests;

    event DecryptionRequested(uint256 indexed requestId, address indexed target, uint256[] handles);
    event DecryptionFulfilled(uint256 indexed requestId, bool accepted);

    function requestDecryption(
        uint256[] calldata ctsHandles,
        bytes4 callbackSelector,
        uint256 userData,
        uint256 deadline,
        bool keepInGateway
    ) external returns (uint256 requestId) {
        requestId = nextRequestId++;
        requests[requestId] = Request({
            target: msg.sender,
            callback: callbackSelector,
            userData: userData,
            deadline: deadline,
            keepInGateway: keepInGateway,
            handles: ctsHandles
        });

        emit DecryptionRequested(requestId, msg.sender, ctsHandles);
    }

    function fulfill(uint256 requestId, uint16 plainRisk) external returns (bool accepted) {
        Request storage request = requests[requestId];
        require(request.target != address(0), "MockGateway: unknown request");

        (bool ok, bytes memory data) = request.target.call(
            abi.encodeWithSelector(request.callback, requestId, plainRisk)
        );
        accepted = ok && data.length == 32 && abi.decode(data, (bool));

        emit DecryptionFulfilled(requestId, accepted);
    }
}

