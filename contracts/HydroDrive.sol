pragma solidity ^0.5.0;

import "./SnowflakeResolver.sol";

import "./interfaces/SnowflakeInterface.sol";
import "./interfaces/IdentityRegistryInterface.sol";
import "./interfaces/IceInterface.sol";

/**
 * @title Ice Protocol
 * @author Harsh Rajat
 * @notice Create Protocol Less File Storage, Grouping, Hassle free Encryption / Decryption and Stamping using Snowflake
 * @dev This Contract forms File Storage / Stamping / Encryption part of Hydro Protocols
 */
contract HydroDrive is SnowflakeResolver {
    /* for referencing Ice, SnowFlake, Identity Registry (ERC-1484).
     */
    IceInterface public ice;
    SnowflakeInterface public snowflake;
    IdentityRegistryInterface public identityRegistry;


    /* ***************
    * DEFINE CONSTRUCTORS AND RELATED FUNCTIONS
    *************** */
    address IceAddress = 0x143c43180cAE3EF019cD915b3059BCe5AC177538; // For local use
    address snowflakeAddress = 0xcF1877AC788a303cAcbbfE21b4E8AD08139f54FA; // For local use
    constructor (/*address IceAddress, address snowflakeAddress*/) public 
    SnowflakeResolver("Hydro Drive", "File Storage and Management", snowflakeAddress, false, false) {
        // Reference Hydro Protocols
        ice = IceInterface(IceAddress);
        snowflake = SnowflakeInterface(snowflakeAddress);
        identityRegistry = IdentityRegistryInterface(snowflake.identityRegistryAddress());
    }
    
    function onAddition(uint /* ein */, uint /* allowance */, bytes memory /* extraData */) 
    public 
    senderIsSnowflake() 
    returns (bool) {
        return true;
    }

    function onRemoval(uint /* ein */, bytes memory /* extraData */) 
    public 
    senderIsSnowflake() 
    returns (bool) {
        return true;
    }
    
    function whoEIN()
    public view
    returns (uint256, address) {
        return (
            identityRegistry.getEIN(msg.sender),
            msg.sender
        );
    }

    // *. FOR DEBUGGING CONTRACT
    // To Build Groups & File System for users
    function debugBuildFS()
    public {
        // Create Groups
        ice.createGroup("A.Images");
    }

}
