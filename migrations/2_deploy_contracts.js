var FXTToken = artifacts.require("FuzexSmartToken");
var Vesting = artifacts.require("TokenVesting");

module.exports = function(deployer){
    deployer.deploy(FXTToken).then(function() {
        return deployer.deploy(Vesting, FXTToken.address);
    });
};

