import hre, { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log(`Deploying HealthVault with account: ${deployer.address}`);
  const balance = await ethers.provider.getBalance(deployer.address);
  console.log(`Deployer balance: ${ethers.formatEther(balance)} ETH`);

  const factory = await ethers.getContractFactory("HealthVault");
  const contract = await factory.deploy();
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  console.log(`HealthVault deployed to: ${address}`);

  const gateway = await contract.gatewayAddress();
  console.log(`Gateway configured at: ${gateway}`);

  console.log(`Network: ${hre.network.name}`);
  console.log("Next steps:");
  console.log(`  - Verify constructor wiring: pnpm hardhat verify --network ${hre.network.name} ${address}`);
  console.log("  - Register contract addresses with your front-end / relayer stack.");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

