var IceGlobal = artifacts.require("IceGlobal");
var IceSort = artifacts.require("IceSort");
var Ice = artifacts.require("Ice");

// module.exports = function(deployer) {
//   deployer.deploy(IceProtocol) /*, "0xB536a9b68e7c1D2Fd6b9851Af2F955099B3A59a9"*/
// };

async function doDeploy(deployer, network) {
    await deployer.deploy(IceGlobal);
    await deployer.link(IceGlobal, Ice);
    await deployer.deploy(IceSort);
    await deployer.link(IceSort, Ice);
    await deployer.deploy(Ice);
}


module.exports = (deployer, network) => {
    deployer.then(async () => {
        await doDeploy(deployer, network);
    });
};