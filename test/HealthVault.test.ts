import { expect } from "chai";
import { ethers, network } from "hardhat";
import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { FhevmType } from "@fhevm/mock-utils";

const GATEWAY_SLOT = ethers.keccak256(ethers.toUtf8Bytes("carecipher.fhevm.gateway"));

async function setGatewaySlot(contractAddress: string, newGateway: string) {
  await network.provider.send("hardhat_setStorageAt", [
    contractAddress,
    GATEWAY_SLOT,
    ethers.zeroPadValue(newGateway, 32),
  ]);
}

async function encryptUint16(value: number, contractAddress: string, userAddress: string) {
  const input = hre.fhevm.createEncryptedInput(contractAddress, userAddress);
  input.add16(value);
  const { handles, inputProof } = await input.encrypt();
  return {
    handle: ethers.hexlify(handles[0]),
    proof: ethers.hexlify(inputProof),
  };
}

async function decryptUint16(handle: string) {
  const result = await hre.fhevm.debugger.decryptEuint(FhevmType.euint16, handle);
  return Number(result);
}

describe("HealthVault", () => {
  async function deployFixture() {
    const [owner, doctor, stranger] = await ethers.getSigners();

    const MockGateway = await ethers.getContractFactory("MockGateway");
    const gateway = await MockGateway.deploy();
    await gateway.waitForDeployment();

    const HealthVault = await ethers.getContractFactory("HealthVault");
    const vault = await HealthVault.deploy();
    await vault.waitForDeployment();

    await setGatewaySlot(await vault.getAddress(), await gateway.getAddress());
    await hre.fhevm.assertCoprocessorInitialized(await vault.getAddress(), "HealthVault");

    return { vault, gateway, owner, doctor, stranger };
  }

  it("creates records with encrypted payloads", async () => {
    const { vault, owner } = await loadFixture(deployFixture);
    const cid = "ipfs://allergy";
    const encAllergy = await encryptUint16(42, await vault.getAddress(), owner.address);
    const encRisk = await encryptUint16(100, await vault.getAddress(), owner.address);

    await expect(
      vault.createRecordFromExternal(cid, encAllergy.handle, encAllergy.proof, encRisk.handle, encRisk.proof),
    )
      .to.emit(vault, "RecordCreated")
      .withArgs(0n, owner.address, cid);

    const record = await vault.records(0);
    expect(record.owner).to.equal(owner.address);
    expect(record.cid).to.equal(cid);
    expect(record.createdAt).to.be.greaterThan(0n);

    const risk = await decryptUint16(record.riskScore);
    expect(risk).to.equal(100);
  });

  it("allows patients to manage access control", async () => {
    const { vault, owner, doctor } = await loadFixture(deployFixture);

    await expect(vault.connect(owner).grantAccess(doctor.address, true))
      .to.emit(vault, "AccessUpdated")
      .withArgs(owner.address, doctor.address, true);

    expect(await vault.granted(owner.address, doctor.address)).to.equal(true);

    await vault.connect(owner).grantAccess(doctor.address, false);
    expect(await vault.granted(owner.address, doctor.address)).to.equal(false);
  });

  it("applies risk delta for authorized users only", async () => {
    const { vault, owner, doctor, stranger } = await loadFixture(deployFixture);
    const contractAddress = await vault.getAddress();

    const allergy = await encryptUint16(7, contractAddress, owner.address);
    const initialRisk = await encryptUint16(90, contractAddress, owner.address);
    await vault.createRecordFromExternal(
      "ipfs://cid",
      allergy.handle,
      allergy.proof,
      initialRisk.handle,
      initialRisk.proof,
    );

    const delta = await encryptUint16(15, contractAddress, doctor.address);

    await expect(
      vault.connect(stranger).addRiskDeltaFromExternal(0, delta.handle, delta.proof),
    ).to.be.revertedWithCustomError(vault, "Unauthorized");

    await vault.grantAccess(doctor.address, true);
    await expect(vault.connect(doctor).addRiskDeltaFromExternal(0, delta.handle, delta.proof)).to.not.be.reverted;

    const record = await vault.records(0);
    const risk = await decryptUint16(record.riskScore);
    expect(risk).to.equal(105);
  });

  it("requests and completes decryption via gateway caller", async () => {
    const { vault, gateway, owner, doctor, stranger } = await loadFixture(deployFixture);
    const contractAddress = await vault.getAddress();

    const allergy = await encryptUint16(12, contractAddress, owner.address);
    const risk = await encryptUint16(88, contractAddress, owner.address);
    await vault.createRecordFromExternal(
      "ipfs://cid",
      allergy.handle,
      allergy.proof,
      risk.handle,
      risk.proof,
    );
    await vault.grantAccess(doctor.address, true);

    const tx = await vault.connect(doctor).requestRiskDecrypt(0);
    const receipt = await tx.wait();
    const gatewayAddress = await gateway.getAddress();
    const event = receipt!.logs
      .filter((log) => log.address === gatewayAddress)
      .map((log) => {
        try {
          return gateway.interface.parseLog(log);
        } catch {
          return undefined;
        }
      })
      .find((parsed) => parsed !== undefined);

    expect(event, "Gateway event not found").to.not.be.undefined;
    const requestId = event!.args.requestId;

    await expect(vault.connect(stranger).onRiskDecrypted(requestId, 77)).to.be.revertedWithCustomError(
      vault,
      "UnauthorizedGateway",
    );

    await expect(gateway.fulfill(requestId, 77))
      .to.emit(vault, "RiskDecrypted")
      .withArgs(0n, doctor.address, 77);
  });
});
