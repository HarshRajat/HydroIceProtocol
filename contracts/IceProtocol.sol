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
    mapping (uint256 => mapping(uint256 => Association)) private association;
    uint256 private globalAssociationIndex; // store the index of association to retrieve files
    
    /* for each user (EIN), look up the file they have
     * stored on a given index.
    */ 
    mapping (uint256 => mapping(uint256 => File)) private files;
    mapping (uint256 => mapping(uint256 => uint256)) private fileOrder; // Store descending order of files
    mapping (uint256 => uint256) private fileIndex; // store the maximum file index reached to provide looping functionality
    
    /* for each user (EIN), look up the group they have
     * stored on a given index. Default group 0 indicates
     * root folder
    */ 
    mapping (uint256 => mapping(uint16 => Group)) private groups;
    mapping (uint256 => uint16) private groupIndex; // store the maximum group index reached to provide looping functionality
    
    /* for each user (EIN), look up the incoming transfer request
     * stored on a given index.
    */ 
    mapping (uint256 => mapping(uint256 => Association)) private transfers;
    mapping (uint256 => mapping(uint256 => uint256)) private transferOrder; // Store descending order of transfers
    mapping (uint256 => uint256) private transferIndex; // store the maximum file index reached to provide looping functionality
    
    /* for each user (EIN), look up the incoming sharing files
     * stored on a given index.
    */ 
    mapping (uint256 => mapping(uint256 => Association)) private sharings;
    mapping (uint256 => mapping(uint256 => uint256)) private sharingOrder; // Store descending order of sharing
    mapping (uint256 => uint256) private shareIndex; // store the maximum file index reached to provide looping functionality
    
    /* for each user (EIN), have a whitelist and blacklist
     * association which can handle certain functions automatically.
    */
    mapping (uint256 => mapping(uint256 => bool)) private whitelist;
    mapping (uint256 => mapping(uint256 => bool)) private blacklist;
    
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
        uint256 transfereeEIN; // To record EIN of the user to whom trasnfer is inititated
        bool markedForTransfer; // Mark the file as transferred
        
        bool requiresStamping; // Whether the file requires stamping 
        
        bool disabled; // Mark the file as disabled if no longer needed
    }
    
    modifier _onlyFileExists(uint256 _fileIndex) {
        // Returns EIN or Throws Error if not set
        uint256 ein = ownerEIN(); 
         
        // Check if the group file exists or not
        uint256 currentFileIndex = fileIndex[ein];
        require ((_fileIndex <= currentFileIndex), "File doesn't exist for the User / EIN");
        _;
    }
    
    modifier _onlyNonDisabledFile(uint256 _fileIndex) {
        // Returns EIN or Throws Error if not set
        uint256 ein = ownerEIN(); 
         
        // Check if the group file exists or not
        File memory currentFile = files[ein][_fileIndex];
        require ((currentFile.disabled == false), "Can't proceed, file is Disabled.");
        _;
    }
    
    modifier _onlyUnmarkedTransferFile(uint256 _fileIndex) {
        // Returns EIN or Throws Error if not set
        uint256 ein = ownerEIN(); 
         
        // Check if the group file exists or not
        File memory currentFile = files[ein][_fileIndex];
        require ((currentFile.markedForTransfer == false), "Can't proceed, file is already marked for Transfer.");
        _;
    }
    
    
    
    modifier _onlyValidEIN(uint256 _ein) {
        SnowflakeInterface snowflake = SnowflakeInterface(snowflakeAddress);
        IdentityRegistryInterface identityRegistry = IdentityRegistryInterface(snowflake.identityRegistryAddress());

        require ((identityRegistry.identityExists(_ein) == true), "The EIN doesn't exists");
        _;
    }
    
    function initiateFileTransfer(uint256 _fileIndex, uint256 _transferreeEIN) public 
    _onlyNonDisabledFile(_fileIndex) _onlyUnmarkedTransferFile(_fileIndex) _onlyValidEIN(_transferreeEIN) _onlyNonOwner(_transferreeEIN) {
        
        // Returns EIN or Throws Error if not set
        uint256 ein = ownerEIN(); 
         
        // Mark the file for transfer
        File memory currentFile = files[ein][_fileIndex];
        currentFile.markedForTransfer = true;
        currentFile.transfereeEIN = _transferreeEIN;
        
        files[ein][_fileIndex] = currentFile;
        
        // Add file to 
        
        // Trigger Event
        emit FileTransferInitiated(ein, _transferreeEIN, _fileIndex);
    }
    
    function acceptFileTransfer(uint256 transferEIN, )
    
    /* To connect Files in linear grouping,
    * sort of like a folder, 0 or default grooupID is root
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
    
    // When Transfer is initiated from owner
    event FileTransferInitiated(
        uint indexed EIN,
        uint indexed transfereeEIN,
        uint indexed fileID
    );
    
    // When whitelist is updated
    event AddedToWhitelist(
        uint indexed EIN,
        uint indexed recipientEIN
    );
    
    event RemovedFromWhitelist(
        uint indexed EIN,
        uint indexed recipientEIN
    );
    
    // When blacklist is updated
    event AddedToBlacklist(
        uint indexed EIN,
        uint indexed recipientEIN
    );
    
    event RemovedFromBlacklist(
        uint indexed EIN,
        uint indexed recipientEIN
    );
    
    /* ***************
    * DEFINE CONSTRUCTORS AND RELATED FUNCTIONS
    *************** */
    // SNOWFLAKE CONSTRUCTOR / FUNCTIONS
    constructor (address snowflakeAddress) public 
    SnowflakeResolver("Ice", "Document Management / Stamping on Snowflake", 
    snowflakeAddress, false, false) { 
        globalAssociationIndex = 0;
    }
    
    // Function to return snowflake identity (EIN)
    function ownerEIN() internal returns (uint256) {
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
    
    /* ***************
    * DEFINE MODIFIERS
    *************** */
    /**
     * @dev Modifier to check that only owner of EIN can access this
     * @param _ein The EIN of the Passer
     */
     modifier _onlyOwner(uint _ein) {   
         // Returns EIN or Throws Error if not set
        uint256 ein = ownerEIN();
        
         require ((ein == _ein), "Only the Owner of EIN can access this.");
         _;
     }
     
     /**
     * @dev Modifier to check that only non-owner of EIN can access this
     * @param _ein The EIN of the Passer
     */
     modifier _onlyNonOwner(uint _ein) {   
         // Returns EIN or Throws Error if not set
        uint256 ein = ownerEIN();
        
         require ((ein != _ein), "Only the Owner of EIN can access this.");
         _;
     }
     
    /* ***************
    * DEFINE CONTRACT FUNCTIONS
    *************** */
    // 1. FILE FUNCTIONS
    /**
     * @dev Addd File metadata and Create a new Group
     * @param hash of the File
     *
     */
    function addFileWithGroup(string memory hash, uint8 protocol, uint8 status, string memory groupName) public {
        // Returns EIN or Throws Error if not set
        uint256 ein = ownerEIN(); 
    }
    
    /**
     * @dev Add File metadata to an existing Group
     * @param hash of the File
     * 
     */
    function addFileToGroup(string memory hash, uint8 protocol, uint8 status, uint8 groupID) public {
        uint256 ein = ownerEIN(); // Returns EIN or Throws Error if not set
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
        uint256 ein = ownerEIN(); // Returns EIN or Throws Error if not set
    }
    
    // 2. GROUP FUNCTIONS
    /**
     * @dev Create a new Group for the user
     * @param _groupName describes the name of the group
     */
    function createGroup(string memory _groupName) public {
        // Returns EIN or Throws Error if not set
        uint256 ein = ownerEIN(); 
        
        // Check if this is unitialized, if so, initialize it, default value will bee 0
        uint16 nextGroupIndex = groupIndex[ein] + 1;
        require (nextGroupIndex >= groupIndex[ein], "Limit reached on number of groups, can't create more groups");
        
        // Create the new group
        Group memory group = Group(
            nextGroupIndex,
            _groupName,
            false
        );
        
        // Assign it to User (EIN)
        groups[ein][nextGroupIndex] = group;
        groupIndex[ein] = nextGroupIndex;
        
        // Trigger Event
        emit GroupCreated(ein, nextGroupIndex);
    }
    
    /**
     * @dev Modifier to check that Group ID = 0 is not modified as this is root
     * @param _groupIndex The index of the group
     */
    modifier _onlyNonRootGroup(uint16 _groupIndex) {
        require ((_groupIndex > 0), "Cannot modify root group.");
        _;
    }
    
    /**
     * @dev Function to check if group exists
     * @param _ein the EIN of the user
     * @param _groupIndex the index of the group
     */
    function _groupExists(uint256 _ein, uint16 _groupIndex) internal view _onlyNonRootGroup(_groupIndex) returns (bool) {
        // Check if the group exists or not
        uint16 currentGroupIndex = uint16(groupIndex[_ein]);
        
        if (_groupIndex <= currentGroupIndex) {
            return true;
        }
        
        return false;
    }
    
    /**
     * @dev Rename an existing Group for the user / ein
     * @param _groupIndex describes the associated index of the group for the user / ein
     * @param _groupName describes the new name of the group
     */
    function renameGroup(uint16 _groupIndex, string memory _groupName) public _onlyNonRootGroup(_groupIndex) {
        // Returns EIN or Throws Error if not set
        uint256 ein = ownerEIN(); 
        
        // Check if the group exists or not
        require ((_groupExists(ein, _groupIndex) == true), "Group doesn't exist for the User / EIN");
        
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
    function toggleGroupStatus(uint16 _groupIndex, bool _status) public _onlyNonRootGroup(_groupIndex) {
        // Returns EIN or Throws Error if not set
        uint256 ein = ownerEIN(); 
         
        // Check if the group exists or not
        uint16 currentGroupIndex = uint16(groupIndex[ein]);
        require ((_groupIndex <= currentGroupIndex), "Group doesn't exist for the User / EIN");
        
        Group memory group = groups[ein][_groupIndex];
        group.disabled = _status;
        
        groups[ein][_groupIndex] = group;
        
        // Trigger Event
        emit GroupStatusChanged(ein, _groupIndex, _status);
    }
    
    // 3. TRANSFER FILE FUNCTIONS
    
    // 5. WHITELIST / BLACKLIST FUNCTIONS
    /**
     * @dev Check if a non-owner user(ein) is whitelisted
     * @param _ein is the ein of the owner
     * @param _nonOwnerEIN is the ein of the recipient
     */
    function isWhitelisted(uint256 _ein, uint256 _nonOwnerEIN) public
    _onlyOwner(ein) _onlyNonOwner(ein)
    Returns (bool) {
        
        return whitelist[_ein][_nonOwnerEIN];
    }
    
    /**
    * @dev Check if a non-owner user(ein) is blacklisted
    * @param _ein is the ein of the owner
    * @param _nonOwnerEIN is the ein of the recipient
    */
    function isBlacklisted(uint256 _ein, uint256 _nonOwnerEIN) public
    _onlyOwner(ein) _onlyNonOwner(ein)
    Returns (bool) {
        
        return blacklist[_ein][_nonOwnerEIN];
    }
    
    /**
    * @dev Add a non-owner user to whitelist
    * @param _ein is the ein of the owner
    * @param _nonOwnerEIN is the ein of the recipient
    */
    function addToWhitelist(uint256 _nonOwnerEIN) public
    _onlyNonOwner(_nonOwnerEIN) _onlyValidEIN(_nonOwnerEIN) {
        
        //Check if user (EIN) is not on blacklist
        require ((isBlacklisted(_nonOwnerEIN) == false), "EIN is blacklisted, remove EIN from blacklist first to proceed.");
        
        // Returns EIN or Throws Error if not set
        uint256 ein = ownerEIN(); 
        
        whitelist[ein][_nonOwnerEIN] = true;
        
        // Trigger Event
        emit AddedToWhitelist(ein, _nonOwnerEIN);
    }
    
    /**
    * @dev Remove a non-owner user from whitelist
    * @param _ein is the ein of the owner
    * @param _nonOwnerEIN is the ein of the recipient
    */
    function removeFromWhitelist(uint256 _nonOwnerEIN) public
    _onlyNonOwner(_nonOwnerEIN) _onlyValidEIN(_nonOwnerEIN) {
        
        //Check if user (EIN) is not on blacklist
        require ((isBlacklisted(_nonOwnerEIN) == false), "EIN is blacklisted, remove EIN from blacklist first to proceed.");
        
        // Returns EIN or Throws Error if not set
        uint256 ein = ownerEIN(); 
        
        whitelist[ein][_nonOwnerEIN] = false;
        
        // Trigger Event
        emit RemovedFromWhitelist(ein, _nonOwnerEIN);
    }
    
    /**
    * @dev Remove a non-owner user to blacklist
    * @param _ein is the ein of the owner
    * @param _nonOwnerEIN is the ein of the recipient
    */
    function addToWhitelist(uint256 _nonOwnerEIN) public
    _onlyNonOwner(_nonOwnerEIN) _onlyValidEIN(_nonOwnerEIN) {
        
        //Check if user (EIN) is not on blacklist
        require ((isWhitelisted(_nonOwnerEIN) == false), "EIN is whitelisted, remove EIN from blacklist first to proceed.");
        
        // Returns EIN or Throws Error if not set
        uint256 ein = ownerEIN(); 
        
        whitelist[ein][_nonOwnerEIN] = true;
        
        // Trigger Event
        emit AddedToBlacklist(ein, _nonOwnerEIN);
    }
    
    /**
    * @dev Remove a non-owner user from blacklist
    * @param _ein is the ein of the owner
    * @param _nonOwnerEIN is the ein of the recipient
    */
    function RemovedFromBlacklist(uint256 _nonOwnerEIN) public
    _onlyNonOwner(_nonOwnerEIN) _onlyValidEIN(_nonOwnerEIN) {
        
        //Check if user (EIN) is not on blacklist
        require ((isWhitelisted(_nonOwnerEIN) == false), "EIN is whitelisted, remove EIN from blacklist first to proceed.");
        
        // Returns EIN or Throws Error if not set
        uint256 ein = ownerEIN(); 
        
        whitelist[ein][_nonOwnerEIN] = false;
        
        // Trigger Event
        emit RemovedFromBlacklist(ein, _nonOwnerEIN);
    }
}
