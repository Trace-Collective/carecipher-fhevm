// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { FHE, euint16, externalEuint16 } from "@fhevm/solidity/lib/FHE.sol";
import { SepoliaFHEVMConfig } from "@fhevm/solidity/config/FHEVMConfig.sol";
import "fhevm/gateway/GatewayCaller.sol";

contract HealthVault is SepoliaFHEVMConfig, GatewayCaller {
    struct Record {
        address owner;
        string cid;
        euint16 allergyCode;
        euint16 riskScore;
        uint256 createdAt;
    }

    struct DecryptContext {
        uint256 recordId;
        address requester;
    }

    uint256 public nextId;
    mapping(uint256 => Record) public records;
    mapping(address => mapping(address => bool)) public granted;
    mapping(uint256 => DecryptContext) private pendingDecrypts;

    event RecordCreated(uint256 indexed id, address indexed owner, string cid);
    event AccessUpdated(address indexed patient, address indexed doctor, bool granted);
    event RiskDecrypted(uint256 indexed id, address indexed requester, uint16 plainRisk);

    error RecordNotFound();
    error Unauthorized();
    error UnknownRequest(uint256 requestId);

    function _storeRecord(address owner, string calldata cid, euint16 encAllergy, euint16 encRisk)
        private
        returns (uint256 id)
    {
        id = nextId;

        records[id] = Record({
            owner: owner,
            cid: cid,
            allergyCode: encAllergy,
            riskScore: encRisk,
            createdAt: block.timestamp
        });

        emit RecordCreated(id, owner, cid);
        unchecked {
            nextId = id + 1;
        }
    }

    function createRecord(
        string calldata cid,
        euint16 encAllergy,
        euint16 encRisk
    ) external {
        _storeRecord(msg.sender, cid, encAllergy, encRisk);
    }

    function createRecordFromExternal(
        string calldata cid,
        externalEuint16 encAllergy,
        bytes calldata allergyProof,
        externalEuint16 encRisk,
        bytes calldata riskProof
    ) external {
        euint16 allergy = _ingestExternal(encAllergy, allergyProof);
        euint16 risk = _ingestExternal(encRisk, riskProof);

        _storeRecord(msg.sender, cid, allergy, risk);
    }

    function grantAccess(address doctor, bool isGranted) external {
        granted[msg.sender][doctor] = isGranted;
        emit AccessUpdated(msg.sender, doctor, isGranted);
    }

    function addRiskDelta(uint256 id, euint16 delta) external {
        Record storage record = _authorize(id);
        _applyRiskDelta(record, delta);
    }

    function addRiskDeltaFromExternal(uint256 id, externalEuint16 delta, bytes calldata proof) external {
        Record storage record = _authorize(id);
        euint16 internalDelta = _ingestExternal(delta, proof);
        _applyRiskDelta(record, internalDelta);
    }

    function _authorize(uint256 id) private view returns (Record storage record) {
        record = records[id];
        if (record.owner == address(0)) {
            revert RecordNotFound();
        }
        address owner = record.owner;
        if (msg.sender != owner && !granted[owner][msg.sender]) {
            revert Unauthorized();
        }
    }

    function _applyRiskDelta(Record storage record, euint16 delta) private {
        euint16 permittedRisk = FHE.allowThis(record.riskScore);
        euint16 permittedDelta = FHE.allowThis(delta);
        record.riskScore = FHE.allowThis(FHE.add(permittedRisk, permittedDelta));
    }

    function requestRiskDecrypt(uint256 id) external returns (uint256 requestId) {
        Record storage record = records[id];
        if (record.owner == address(0)) {
            revert RecordNotFound();
        }
        address owner = record.owner;
        if (msg.sender != owner && !granted[owner][msg.sender]) {
            revert Unauthorized();
        }

        uint256[] memory ciphertextHandles = Gateway.toUint256(record.riskScore);
        requestId = Gateway.requestDecryption(
            ciphertextHandles,
            this.onRiskDecrypted.selector,
            0,
            block.timestamp + 300,
            false
        );

        pendingDecrypts[requestId] = DecryptContext({ recordId: id, requester: msg.sender });
    }

    function onRiskDecrypted(
        uint256 requestId,
        uint16 plainRisk
    ) external onlyGateway returns (bool) {
        DecryptContext memory ctx = pendingDecrypts[requestId];
        if (ctx.requester == address(0)) {
            revert UnknownRequest(requestId);
        }

        delete pendingDecrypts[requestId];

        emit RiskDecrypted(ctx.recordId, ctx.requester, plainRisk);
        return plainRisk > 0;
    }

    function _ingestExternal(externalEuint16 inputHandle, bytes calldata proof) private returns (euint16) {
        euint16 value = FHE.fromExternal(inputHandle, proof);
        return FHE.allowThis(value);
    }
}
