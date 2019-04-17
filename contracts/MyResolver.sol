pragma solidity ^0.5.0;

import "./SnowflakeResolver.sol";
import "./interfaces/SnowflakeInterface.sol";
import "./interfaces/IdentityRegistryInterface.sol";

import "./zeppelin/math/SafeMath.sol";
import "./zeppelin/math/SafeMath16.sol";

/**
 * @title Ice Protocol
 * @author Harsh Rajat
 * @notice Create Protocol Less File Storage, Grouping, Hassle free Encryption / Decryption and Stamping using Snowflake 
 * @dev This Contract forms File Storage / Stamping / Encryption part of Hydro Protocols
 */
contract IceProtocol is SnowflakeResolver {
    using SafeMath for uint16;
    using SafeMath for uint256;

    /* ***************
    * DEFINE VARIABLES
    *************** */
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
     * stored on a given index. Default group 0 indicates
     * root folder
    */ 
    mapping (uint256 => mapping(uint16 => Group)) groups;
    mapping (uint256 => uint16) groupIndex; // store the maximum group index reached to provide looping functionality
    
    /* for each user (EIN), look up the incoming transfer request
     * stored on a given index.
    */ 
    mapping (uint256 => mapping(uint256 => Association)) transfers;
    mapping (uint256 => uint256) transferIndex;
    
    /* ***************
    * DEFINE STRUCTURES
    *************** */
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
        
        string name; // the name of the file
        string hash; // store the hash of the file for verification | 0x000 for deleted files
        string[] metadata; // store any metadata required as per protocol
        uint256 timestamp; // to store the timestamp of the block when file is created
        uint16 groupAssociationID; // maps 1:1 to groupID of Group
        
        bool encrypted; // whether the file is encrypted
        mapping (address => string) encryptedHash; // Maps Individual address to the stored hash 
        
        uint256[] transferHistory; // To maintain histroy of transfer of all EIN
        uint256 transferInitiated; // To record EIN of the user to whom trasnfer is inititated
        bool markedForTransfer; // Mark the file as transferred
        
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

    /* ***************
    * DEFINE EVENTS
    *************** */
    // When Group is created
    event GroupCreated(
        uint indexed EIN,
        uint16 indexed groupID
    );
    
    // When Group is renamed
    event GroupRenamed(
        uint indexed EIN,
        uint16 indexed groupID
    );
    
    // When Group Status is changed
    event GroupStatusChanged(
        uint indexed EIN,
        uint16 indexed groupID,
        bool indexed groupStatus
    );
    
    /* ***************
    * DEFINE CONSTRUCTORS AND FUNCTIONS
    *************** */
    // 1. SNOWFLAKE CONSTRUCTOR / FUNCTIONS
    constructor (address snowflakeAddress) public 
    SnowflakeResolver("Ice", "Document Management / Stamping on Snowflake", 
    snowflakeAddress, false, false) { 
        globalAssociationIndex = 0;
    }
    
    // Function to return snowflake identity (EIN)
    function returnEIN() internal returns (uint256) {
        SnowflakeInterface snowflake = SnowflakeInterface(snowflakeAddress);
        IdentityRegistryInterface identityRegistry = IdentityRegistryInterface(snowflake.identityRegistryAddress());

        uint256 ein = identityRegistry.getEIN(msg.sender);
        require (identityRegistry.isResolverFor(ein, address(this)), "EIN has not set this resolver");
        
        return ein;
    }

    function onAddition(uint /* ein */, uint /* allowance */, bytes memory /* extraData */) public senderIsSnowflake() returns (bool) {
        // implement function here, or set the _callOnAddition flag to false in the SnowflakeResolver constructor
        return true;
    }

    function onRemoval(uint /* ein */, bytes memory /* extraData */) public senderIsSnowflake() returns (bool) {
        // implement function here, or set the _callOnRemoval flag to false in the SnowflakeResolver constructor
        return true;
    }
    
    // 3. GROUP FUNCTIONS
    /**
     * @dev Rename an existing Group for the user / ein
     * @param _groupIndex describes the associated index of the group for the user / ein
     * @param _groupName describes the new name of the group
     */
    function renameGroup(uint16 _groupIndex, string memory _groupName) public {
        // Returns EIN or Throws Error if not set
        uint256 ein = returnEIN(); 
        
        // Check if the group exists or not
        
        // Replace the group name
        Group memory group = groups[ein][_groupIndex];
        group.name = _groupName;
        
        groups[ein][_groupIndex] = group;
        
        // Trigger Event
        emit GroupRenamed(ein, _groupIndex);
    }
    
   /**
     * @dev Toggle an existing Group status (Activate | Deactivate) for the user / ein
     * @param _groupIndex describes the associated index of the group for the user / ein
     * @param _status describes the status of the group
     */
    function toggleGroupStatus(uint16 _groupIndex, bool _status) public {
        // Returns EIN or Throws Error if not set
        uint256 ein = returnEIN(); 
         
        // Check if the group exists or not
        uint16 currentGroupIndex = groupIndex[ein];
        require ((_groupIndex <= currentGroupIndex), "Group doesn't exist for the User / EIN");
        
        Group memory group = groups[ein][_groupIndex];
        group.disabled = _status;
        
        
        // Trigger Event
        emit GroupStatusChanged(ein, _groupIndex, _status);
    }
    
    // 4. TRANSFER FILE FUNCTIONS
}
