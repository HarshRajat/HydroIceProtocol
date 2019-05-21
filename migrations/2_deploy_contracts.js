var IceUtil = artifacts.require("IceUtil");

var IceGlobal = artifacts.require("IceGlobal");
var IceSort = artifacts.require("IceSort");

var IceFMS = artifacts.require("IceFMS");
var IceFMSAdv = artifacts.require("IceFMSAdv");

var Ice = artifacts.require("Ice");

// module.exports = function(deployer) {
//   deployer.deploy(IceProtocol) /*, "0xB536a9b68e7c1D2Fd6b9851Af2F955099B3A59a9"*/
// };

async function doDeploy(deployer, network) {
    await deployer.deploy(IceGlobal);
    await deployer.link(IceGlobal, IceFMS);
    await deployer.link(IceGlobal, IceFMSAdv);
    await deployer.link(IceGlobal, Ice);

    await deployer.deploy(IceSort);
    await deployer.link(IceSort, IceFMS);
    await deployer.link(IceSort, IceFMSAdv);
	await deployer.link(IceSort, Ice);

    await deployer.deploy(IceUtil);
    await deployer.link(IceUtil, IceFMS);
    await deployer.link(IceUtil, IceFMSAdv);
    await deployer.link(IceUtil, Ice);

    await deployer.deploy(IceFMSAdv);
	await deployer.link(IceFMSAdv, IceFMS);
	await deployer.link(IceFMSAdv, Ice);

	await deployer.deploy(IceFMS);
    await deployer.link(IceFMS, Ice);

    await deployer.deploy(Ice);
}


module.exports = (deployer, network) => {
    deployer.then(async () => {
        await doDeploy(deployer, network);
    });
};