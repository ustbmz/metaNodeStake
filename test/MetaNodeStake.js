const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("MetaNodeStake", function () {
  async function deployStake() {
    const [admin, stranger] = await ethers.getSigners();

    const Token = await ethers.getContractFactory("MetaNodeToken");
    const token = await Token.deploy();

    const startBlock = 100n;
    const endBlock = 1000n;
    const metaNodePerBlock = ethers.parseEther("0.02");

    const Stake = await ethers.getContractFactory("MetaNodeStake");
    const stake = await upgrades.deployProxy(
      Stake,
      [await token.getAddress(), startBlock, endBlock, metaNodePerBlock],
      { initializer: "initialize" }
    );

    return { admin, stranger, token, stake, startBlock, endBlock, metaNodePerBlock };
  }

  it("records the reward schedule and grants roles to the deployer", async function () {
    const { admin, token, stake, startBlock, endBlock, metaNodePerBlock } = await deployStake();

    expect(await stake.startBlock()).to.equal(startBlock);
    expect(await stake.endBlock()).to.equal(endBlock);
    expect(await stake.MetaNodePerBlock()).to.equal(metaNodePerBlock);
    expect(await stake.MetaNode()).to.equal(await token.getAddress());
    expect(await stake.ETH_PID()).to.equal(0);
    await expect(stake.pool(0)).to.be.reverted;

    expect(await stake.hasRole(await stake.ADMIN_ROLE(), admin.address)).to.equal(true);
    expect(await stake.hasRole(await stake.UPGRADE_ROLE(), admin.address)).to.equal(true);
    expect(await stake.hasRole(await stake.DEFAULT_ADMIN_ROLE(), admin.address)).to.equal(true);

    const position = await stake.user(0, admin.address);
    expect(position.stAmount).to.equal(0);
    expect(position.finishedMetaNode).to.equal(0);
    expect(position.pendingMetaNode).to.equal(0);
  });

  it("rejects initializing the proxy twice", async function () {
    const { token, stake } = await deployStake();

    await expect(
      stake.initialize(await token.getAddress(), 1, 2, 1)
    ).to.be.revertedWithCustomError(stake, "InvalidInitialization");
  });

  it("rejects an end block before the start block", async function () {
    const { token } = await deployStake();
    const Stake = await ethers.getContractFactory("MetaNodeStake");

    await expect(
      upgrades.deployProxy(Stake, [await token.getAddress(), 10, 9, 1], {
        initializer: "initialize",
      })
    ).to.be.revertedWith("invalid parameters");
  });

  it("rejects a stranger changing the reward token", async function () {
    const { stranger, token, stake } = await deployStake();

    await expect(
      stake.connect(stranger).setMetaNode(await token.getAddress())
    ).to.be.revertedWithCustomError(stake, "AccessControlUnauthorizedAccount");
  });
});
