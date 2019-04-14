pragma solidity ^0.5.0;

import "./SnowflakeResolver.sol";
import "./zeppelin/math/SafeMath.sol";
import "./zeppelin/math/SafeMath16.sol";
import "./interfaces/HydroInterface.sol";
import "./interfaces/SnowflakeInterface.sol";
import "./interfaces/IdentityRegistryInterface.sol";

/**
 * @title Ice Protocol
 * @notice Create Protocol Less File Storage, Grouping, Hassle free Encryption / Decryption and Stamping using Snowflake 
 * @dev This Contract forms File Storage / Stamping / Encryption part of Hydro Protocols
 */
contract IceProtocol is SnowflakeResolver {   
    using SafeMath for uint16;
    using SafeMath for uint256;

    /* for each file stored, ensure they can be retrieved publicly.
    * associationIndex starts at 0 and will always increment
    * given an associationIndex, any file can be retrieved.
    */
    mapping (uint256 => mapping(uint256 => Association)) public association;
    uint256 public globalAssociationIndex; // store the index of association to retrieve files
    
    /* for each user (EIN), look up the file they have
     * stored on a given index.
    */ 
    mapping (uint256 => mapping(uint256 => File)) files;
    mapping (uint256 => uint256) fileIndex; // store the maximum file index reached to provide looping functionality
    
    /* for each user (EIN), look up the group they have
     * stored on a given index.
    */ 
    mapping (uint256 => mapping(uint16 => Group)) groups;
    mapping (uint256 => uint16) groupIndex; // store the maximum group index reached to provide looping functionality
    
    /* To define global file association with EIN
    * Combining EIN and fileRecord will give access to 
    * file data.
    */
    struct Association {
        uint256 EIN; // the EIN of the owner
        uint256 fileRecord; // the key at which the file struct is stored 
    }

    /* To define File structure of all stored files
    */
    struct File {
        /* Define the protocol of the storage,
        * JS Library of ours reserves the following values
        * 0 - OnChain | 1 - IPFS
        */
        uint8 protocol;
        
        string hash; // store the hash of the file for verification
        string[] metadata; // store any metadata required as per protocol
        
        uint16 groupAssociationID; // maps 1:1 to groupID of Group
        
        uint256 timestamp; // to store the timestamp of the block when file is created
        
        bool encrypted; // whether the file is encrypted
        mapping (address => string) encryptedHash; // Maps Individual address to the stored hash 
        
        bool requiresStamping; // Whether the file requires stamping 
        
        bool disabled; // Mark the file as disabled if no longer needed
    }   
    
    /* To connect Files in linear grouping,
    * sort of like a folder
    */
    struct Group {
        uint16 groudID; // the id of the Group
        string name; // the name of the group
        
        bool disabled; // Mark the group as disabled if no longer neededs
    }

    event FileAdded( 
        uint indexed fileID
    );
    
    constructor (address snowflakeAddress) public 
    SnowflakeResolver("Ice", "Document Management / Stamping on Snowflake", 
    snowflakeAddress, false, false) { 
        globalAssociationIndex = 0;
    }
    
    /**
     * @dev Addd File metadata and Create a new Group
     * @param hash of the File
     *
     */
    function addFileWithGroup(string memory hash, uint8 protocol, uint8 status, string memory groupName) public {
        SnowflakeInterface snowflake = SnowflakeInterface(snowflakeAddress);
        IdentityRegistryInterface identityRegistry = IdentityRegistryInterface(snowflake.identityRegistryAddress());

        uint256 ein = identityRegistry.getEIN(msg.sender);
        require(identityRegistry.isResolverFor(ein, address(this)), "ein has not set this resolver");
        
    }
    
    /**
     * @dev Add File metadata to an existing Group
     * @param hash of the File
     * 
     */
    function addFileToGroup(string memory hash, uint8 protocol, uint8 status, uint8 groupID) public {
        SnowflakeInterface snowflake = SnowflakeInterface(snowflakeAddress);
        IdentityRegistryInterface identityRegistry = IdentityRegistryInterface(snowflake.identityRegistryAddress());

        uint256 ein = identityRegistry.getEIN(msg.sender);
        require(identityRegistry.isResolverFor(ein, address(this)), "ein has not set this resolver");
        
    }
    
    /**
     * @dev Add File entire functionality
     * @param hash of the file
     * @param protocol used to store the file
     * @param status of the file (0 = Normal | 1 = Encrypted)
     * @param groupID refers to the existing group
     * @param groupName refers to the groupName
     */
    function _addFile(uint EIN, string memory hash, uint8 protocol, uint8 status, uint8 groupID, string memory groupName) private {
        SnowflakeInterface snowflake = SnowflakeInterface(snowflakeAddress);
        IdentityRegistryInterface identityRegistry = IdentityRegistryInterface(snowflake.identityRegistryAddress());

        uint256 ein = identityRegistry.getEIN(msg.sender);
        require(identityRegistry.isResolverFor(ein, address(this)), "ein has not set this resolver");
        
        // Check if group already exists
    }
    
    /**
     * @dev Create a new Group for the user
     */
    function createGroup(string memory groupName) public {
        SnowflakeInterface snowflake = SnowflakeInterface(snowflakeAddress);
        IdentityRegistryInterface identityRegistry = IdentityRegistryInterface(snowflake.identityRegistryAddress());

        uint256 ein = identityRegistry.getEIN(msg.sender);
        require(identityRegistry.isResolverFor(ein, address(this)), "ein has not set this resolver");
        
        uint16 nextGroupIndex = 0;
        
        // Check if this is unitialized, if so, initialize it
        if (groupIndex[ein] != 0x0000) {
            nextGroupIndex = uint16(groupIndex[ein]);
            nextGroupIndex.add(1);
        }
        
        // Create the new group
        Group memory group = Group(
            nextGroupIndex,
            groupName,
            false
        );
        
        // Assign it to User (EIN)
        groups[ein][nextGroupIndex] = group;
        groupIndex[ein] = nextGroupIndex;
    }
    
    function renameGroup(uint16 groupIndex, string memory groupName) public {
        
    }
    
    // Checks whether the provided (v, r, s) signature was created by the private key associated with _address
    function isSigned(address _address, bytes32 messageHash, uint8 v, bytes32 r, bytes32 s) public pure returns (bool) {
        return (_isSigned(_address, messageHash, v, r, s) || _isSignedPrefixed(_address, messageHash, v, r, s));
    }

    // Checks unprefixed signatures
    function _isSigned(address _address, bytes32 messageHash, uint8 v, bytes32 r, bytes32 s) internal pure returns (bool) {
        return ecrecover(messageHash, v, r, s) == _address;
    }

    // Checks prefixed signatures (e.g. those created with web3.eth.sign)
    function _isSignedPrefixed(address _address, bytes32 messageHash, uint8 v, bytes32 r, bytes32 s) internal pure returns (bool) {
        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        bytes32 prefixedMessageHash = keccak256(abi.encodePacked(prefix, messageHash));
        return ecrecover(prefixedMessageHash, v, r, s) == _address;
    }
}
