const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("MetaNodeToken", function () {
  it("mints 10 million tokens to the deployer", async function () {
    const [deployer] = await ethers.getSigners();
    const Token = await ethers.getContractFactory("MetaNodeToken");
    const token = await Token.deploy();

    const supply = ethers.parseEther("10000000");
    expect(await token.totalSupply()).to.equal(supply);
    expect(await token.balanceOf(deployer.address)).to.equal(supply);
    expect(await token.symbol()).to.equal("MetaNode");
  });
});
