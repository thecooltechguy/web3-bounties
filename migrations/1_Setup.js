const SecurityToken = artifacts.require("SecurityToken");
const BountyProtocol = artifacts.require("BountyProtocol");

module.exports = async function (deployer) {
  await deployer.deploy(SecurityToken, "1000000000000000000000000"); // 1M tokens
  const securityTokenInstance = await SecurityToken.deployed();

  await deployer.deploy(BountyProtocol, securityTokenInstance.address);
};