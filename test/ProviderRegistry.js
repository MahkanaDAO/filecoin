const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

describe("ProviderRegistry contract", function() {
    async function deploy() {
        const [owner, node1] = await ethers.getSigners();
        const ProviderRegistry = await ethers.getContractFactory("ProviderRegistry");
        const registry = await ProviderRegistry.deploy();

        return { owner, node1, registry };
    }

    it("should only allow owner to activate and deactivate nodes", async function() {
        const { node1, registry } = await loadFixture(deploy);

        const startDate = new Date("2020-01-01");
        const endDate = new Date("2021-01-01");
        await expect(registry.connect(node1).activateProvider(node1.address, startDate.getTime(), endDate.getTime(), 9, 18, 8)).to.be.reverted;
        await expect(registry.connect(node1).deactivateProvider(node1.address)).to.be.reverted;
    });

    it("should give defaults if no work history", async function() {
        const { node1, registry } = await loadFixture(deploy);
        const startDate = new Date("2020-01-01");
        const endDate = new Date("2021-01-01");
        await registry.activateProvider(node1.address, startDate.getTime(), endDate.getTime(), 9, 18, 8);
        expect(await registry.getRating(node1.address)).to.be.equal(90);
        expect(await registry.getFulfilledHours(node1.address)).to.equal(1);
    })

    it("should calculate reputation based on hours", async function() {
        const { node1, registry } = await loadFixture(deploy);

        const startDate = new Date("2020-01-01");
        const endDate = new Date("2021-01-01");
        await registry.activateProvider(node1.address, startDate.getTime(), endDate.getTime(), 9, 18, 16);
        await registry.addHours(node1.address, 1, 2);
        expect(await registry.getRating(node1.address)).to.equal(50);
        expect(await registry.getFulfilledHours(node1.address)).to.equal(1);
    });
});