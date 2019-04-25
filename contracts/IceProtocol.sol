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
    * DEFINE ENUM
    *************** */
    enum NoticeType {info, warning, error}
    
    /* ***************
    * DEFINE VARIABLES
    *************** */
    /* for each file stored, ensure they can be retrieved publicly.
    * associationIndex starts at 0 and will always increment
    * given an associationIndex, any file can be retrieved.
    */
    mapping (uint256 => mapping(uint256 => Association)) private globalAssociation;
    mapping (uint256 => mapping(uint256 => uint256)) private globalAssociationOrder; // Store descending order of global association
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
    mapping (uint256 => mapping(uint256 => Group)) private groups;
    mapping (uint256 => mapping(uint256 => SortOrder)) private groupOrder; // Store descending order of group
    mapping (uint256 => uint256) private groupIndex; // store the maximum group index reached to provide looping functionality
    
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
    
    /* for referencing SnowFlake for Identity Registry (ERC-1484).
    */
    SnowflakeInterface public snowflake;
    IdentityRegistryInterface public identityRegistry;
   
    /* ***************
    * DEFINE STRUCTURES
    *************** */
    /* To define global file association with EIN
    * Combining EIN and fileRecord will give access to 
    * file data.
    */
    struct Association {
        uint256 ownerEIN; // the EIN of the owner
        uint256 fileRecord; // the key at which the file struct is stored 
    }

    /* To define File structure of all stored files
    */
    struct File {
        /* Define the protocol of the storage,
        * JS Library of ours reserves the following values
        * 0 - OnChain | 1 - IPFS
        */
        uint256 fileOwner;
        uint8 protocol;
        
        string name; // the name of the file
        string hash; // store the hash of the file for verification | 0x000 for deleted files
        string[] metadata; // store any metadata required as per protocol
        uint256 timestamp; // to store the timestamp of the block when file is created
        
        bool encrypted; // whether the file is encrypted
        mapping (address => string) encryptedHash; // Maps Individual address to the stored hash 
        
        mapping (uint256 => uint256) sharedTo; // list of people the file is shared to
        uint256 sharedIndex; // the index of sharing        
        
        uint256[] transferHistory; // To maintain histroy of transfer of all EIN
        uint256 transfereeEIN; // To record EIN of the user to whom trasnfer is inititated
        bool markedForTransfer; // Mark the file as transferred
        
        bool requiresStamping; // Whether the file requires stamping 
    }
    
    /* To define the order required to have double linked list
    */
    struct SortOrder {
        uint256 next; // the next ID of the order
        uint256 prev; // the prev ID of the order
        
        uint256 pointerID; // what it should point to in the mapping
        
        bool active; // whether the node is active or not
    }
    
    function initiateFileTransfer(uint256 _transfererEIN, uint256 _fileIndex, uint256 _transfereeEIN) 
    public 
    _isResolverFor() 
    _onlyValidEIN(_transfereeEIN)
    _onlyOwner(_transfererEIN) 
    _onlyUniqueEIN(_transfererEIN, _transfereeEIN)
    _onlyUnmarkedTransferFile(_fileIndex)
    _onlyUnmarkedStampingFile(_fileIndex) {
        // Check if the transfereeEIN has blacklisted current owner
        require ((isBlacklisted(_transfereeEIN, _transfererEIN) == true), "Can't initiate file transfer as the owner has blacklisted you.");
        
        // Check and change flow if white listed
        if (isWhitelisted(_transfereeEIN, _transfererEIN) == true) {
            // Directly transfer file
            _doFileTransfer(_transfererEIN, _fileIndex, _transfereeEIN);
        }
        else {
            // Map it to transferee mapping of transfers 
            // Mark the file for transfer
            files[_transfererEIN][_fileIndex].markedForTransfer = true;
            files[_transfererEIN][_fileIndex].transfereeEIN = _transfereeEIN;
            
            // Add to transfers of TransfereeEIN User
            uint256 currentTransferIndex = transferIndex[_transfereeEIN];
            transfers[_transfereeEIN][currentTransferIndex] = Association(
                _transfererEIN,
                _fileIndex
            );
            
            // Update index and order
            transferOrder[_transfereeEIN][currentTransferIndex] = currentTransferIndex;
            
            // Increment the transfer index and store that
            transferIndex[_transfereeEIN] = currentTransferIndex.add(1);
        
            // Trigger Event
            emit FileTransferInitiated(_transfererEIN, _transfereeEIN, _fileIndex);
        }
    }
    
    function acceptFileTransfer(uint256 _transfererEIN, uint256 _fileIndex, uint256 _transfereeEIN) 
    public 
    _isResolverFor() 
    _onlyNonOwner(_transfereeEIN)
    _onlyFileNonOwner(_transfererEIN, _fileIndex) 
    _onlyMarkedTransferFile(_transfererEIN, _fileIndex) 
    _onlyMarkedForTransferee(_transfererEIN, _fileIndex, _transfererEIN) {
        
        // Do file transfer
        _doFileTransfer(_transfererEIN, _fileIndex, _transfereeEIN);
    }
    
    function _doFileTransfer(uint256 _transfererEIN, uint256 _fileIndex, uint256 _transfereeEIN) 
    internal {
        // Get Indexes
        uint256 transfererIndex = fileIndex[_transfererEIN];
        uint256 transfereeIndex = fileIndex[_transfereeEIN];
        
        // Transfer the file to the transferee, update index and order
        files[_transfereeEIN][transfereeIndex] = files[_transfererEIN][_fileIndex];
        fileOrder[_transfereeEIN][transfereeIndex] = fileIndex[_transfereeEIN];
        fileIndex[_transfereeEIN] = transfereeIndex.add(1);
        
        // Remove the file from transferer
        files[_transfererEIN][_fileIndex] = files[_transfererEIN][transfererIndex];
        
    }
    
    /* To connect Files in linear grouping,
    * sort of like a folder, 0 or default grooupID is root
    */
    struct Group {
        string name; // the name of the Group
        
        mapping (uint256 => SortOrder) groupFilesOrder;
    }

    /* ***************
    * DEFINE EVENTS
    *************** */
    // When Group is created
    event GroupCreated(
        uint indexed EIN,
        uint256 indexed groupIndex
    );
    
    // When Group is renamed
    event GroupRenamed(
        uint indexed EIN,
        uint indexed groupIndex
    );
    
    // When Group Status is changed
    event GroupDeleted(
        uint indexed EIN,
        uint indexed groupIndex
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
    
    // Notice Events
    event Notice(
        uint indexed EIN,
        string indexed notice,
        uint indexed statusType
    );
    
    /* ***************
    * DEFINE CONSTRUCTORS AND RELATED FUNCTIONS
    *************** */
    // SNOWFLAKE CONSTRUCTOR / FUNCTIONS
    address snowflakeAddress = 0xB536a9b68e7c1D2Fd6b9851Af2F955099B3A59a9; // For local use
    constructor (/*address snowflakeAddress*/) public 
    SnowflakeResolver("Ice", "Document Management / Stamping on Snowflake", snowflakeAddress, false, false) {
        snowflake = SnowflakeInterface(snowflakeAddress);
        identityRegistry = IdentityRegistryInterface(snowflake.identityRegistryAddress());
    }
    
    function onAddition(uint /* ein */, uint /* allowance */, bytes memory /* extraData */) public senderIsSnowflake() returns (bool) {
        return true;
    }

    function onRemoval(uint /* ein */, bytes memory /* extraData */) public senderIsSnowflake() returns (bool) {
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
    
    /* ***************
    * DEFINE MODIFIERS
    *************** */
    /**
     * @dev Modifier to check that the EIN has set reslover or not
     */
    modifier _isResolverFor() {
        //require(identityRegistry.isResolverFor(identityRegistry.getEIN(msg.sender), address(this)),"The EIN has not set this resolver.");
        _;
    }
    
    /**
    * @dev Modifier to check that only owner can have access
    * @param _ein The EIN of the file Owner
    */
    modifier _onlyOwner(uint256 _ein) {  
        require ((identityRegistry.getEIN(msg.sender) == _ein), "Only the Owner of EIN can access this.");
         _;
    }
    
    /**
    * @dev Modifier to check that only non-owner can have access
    * @param _ein The EIN of the file Owner
    */
    modifier _onlyNonOwner(uint256 _ein) {  
        require ((identityRegistry.getEIN(msg.sender) != _ein), "Only the Non-Owner of EIN can access this.");
         _;
    }
    
    /**
    * @dev Modifier to check that only owner of EIN can access this
    * @param _ownerEIN The EIN of the file Owner
    * @param _fileIndex The index of the file
    */
    modifier _onlyFileOwner(uint256 _ownerEIN, uint256 _fileIndex) {
        require ((identityRegistry.getEIN(msg.sender) == files[_ownerEIN][_fileIndex].fileOwner), "Only the Owner of File can access this.");
         _;
    }
     
    /**
    * @dev Modifier to check that only non-owner of EIN can access this
    * @param _ownerEIN The EIN of the file Owner
    * @param _fileIndex The index of the file
    */
    modifier _onlyFileNonOwner(uint256 _ownerEIN, uint256 _fileIndex) { 
        require ((identityRegistry.getEIN(msg.sender) != files[_ownerEIN][_fileIndex].fileOwner), "Only Non-Owner of File can access this.");
         _;
    }
    
    /**
    * @dev Modifier to check that only valid EINs can have access
    * @param _ein The EIN of the Passer
    */
    modifier _onlyValidEIN(uint256 _ein) {
        require ((identityRegistry.identityExists(_ein) == true), "The EIN doesn't exists");
        _;
    }
    
    /**
    * @dev Modifier to check that only unique EINs can have access
    * @param _ein1 The First EIN
    * @param _ein2 The Second EIN
    */
    modifier _onlyUniqueEIN(uint256 _ein1, uint256 _ein2) {
        require ((_ein1 != _ein2), "Both EINs are the same.");
        _;
    }
    
    /**
    * @dev Modifier to check that a file exists for the current EIN
    * @param _fileIndex The index of the file
    */
    modifier _onlyFileExists(uint256 _fileIndex) {
        require ((_fileIndex <= fileIndex[identityRegistry.getEIN(msg.sender)]), "File doesn't exist for the User / EIN");
        _;
    }
    
    /**
    * @dev Modifier to check that a file has been marked for transfer
    * @param _fileOwnerEIN The EIN of the file owner
    * @param _fileIndex The index of the file
    */
    modifier _onlyMarkedTransferFile(uint256 _fileOwnerEIN, uint256 _fileIndex) {
        // Check if the group file exists or not
        require ((files[_fileOwnerEIN][_fileIndex].markedForTransfer == true), "Can't proceed, file is marked for Transfer.");
        _;
    }
    
    /**
    * @dev Modifier to check that a file hasn't been marked for transfer
    * @param _fileIndex The index of the file
    */
    modifier _onlyUnmarkedTransferFile(uint256 _fileIndex) {
        // Check if the group file exists or not
        require ((files[identityRegistry.getEIN(msg.sender)][_fileIndex].markedForTransfer == false), "Can't proceed, file is already marked for Transfer.");
        _;
    }
    
    /**
    * @dev Modifier to check that a file has been marked for transferee EIN
    * @param _fileIndex The index of the file
    */
    modifier _onlyMarkedForTransferee(uint256 _fileOwnerEIN, uint256 _fileIndex, uint256 _transfereeEIN) {
        // Check if the group file exists or not
        require ((files[_fileOwnerEIN][_fileIndex].transfereeEIN == _transfereeEIN), "Can't proceed, file is not marked for Transfer.");
        _;
    }
    
    /**
    * @dev Modifier to check that a file hasn't been marked for stamping
    * @param _fileIndex The index of the file
    */
    modifier _onlyUnmarkedStampingFile(uint256 _fileIndex) {
        // Check if the group file exists or not
        require ((files[identityRegistry.getEIN(msg.sender)][_fileIndex].requiresStamping == false), "Can't proceed, file(s) marked for stamping can't be Transferred.");
        _;
    }
    
    /**
     * @dev Modifier to check that Group Order is valid
     * @param _ein is the EIN of the target user
     * @param _groupOrderIndex The index of the group order
     */
    modifier _onlyValidGroupOrder(uint256 _ein, uint256 _groupOrderIndex) {
        require (
            (_groupOrderIndex == 0 || groupOrder[_ein][_groupOrderIndex].active == true), 
            "Group Order Index doesn't exists"
        );
        _;
    }
    
    /**
     * @dev Modifier to check that Group ID = 0 is not modified as this is root
     * @param _groupIndex The index of the group
     */
    modifier _onlyNonRootGroup(uint256 _groupIndex) {
        require (
            (_groupIndex > 0), 
            "Cannot modify root group."
        );
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
        uint256 ein = identityRegistry.getEIN(msg.sender);
    }
    
    /**
     * @dev Add File metadata to an existing Group
     * @param hash of the File
     * 
     */
    function addFileToGroup(string memory hash, uint8 protocol, uint8 status, uint8 groupIndex) public {
        uint256 ein = identityRegistry.getEIN(msg.sender);
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
        uint256 ein = identityRegistry.getEIN(msg.sender);
    }
    
    // 2. GROUP FUNCTIONS
    /**
     * @dev Function to check if group exists
     * @param _ein the EIN of the user
     * @param _groupIndex the index of the group
     */
    function _groupExists(uint256 _ein, uint256 _groupIndex) 
    internal view 
    returns (bool) {
        // Check if the group exists or not
        uint16 currentGroupIndex = uint16(groupIndex[_ein]);
        
        if (_groupIndex <= currentGroupIndex) {
            return true;
        }
        
        return false;
    }
    
    function getGroupIndex(uint256 _ein)
    public view
    _onlyValidEIN(_ein) 
    returns (uint256 currentIndexPosition) {
        currentIndexPosition = groupIndex[_ein];
    }
    
    function getGroupOrder(uint256 _ein, uint256 _seedPointer)
    public view
    _onlyValidGroupOrder(_ein, _seedPointer)
    returns (uint256 prev, uint256 next, uint256 pointerID, bool active) {
        prev = groupOrder[_ein][_seedPointer].prev;
        next = groupOrder[_ein][_seedPointer].next;
        pointerID = groupOrder[_ein][_seedPointer].pointerID;
        active = groupOrder[_ein][_seedPointer].active;
    }
    
    function getGroup(uint256 _ein, uint256 _groupIndex)
    public view
    returns (uint256 groupIndex, string memory groupName) {
        // Check if the group exists or not
        require ((_groupExists(_ein, _groupIndex) == true), "Group doesn't exist for the User / EIN");
        
        groupIndex = _groupIndex;
        groupName = groups[_ein][_groupIndex].name;
    }
    
    function getDescendingGroupsID(uint256 _ein, uint16 _limit, uint16 _seedPointer) 
    public view
    returns (uint256[20] memory groupIndexes, string memory groupNames) {
        
        uint256 next;
        uint256 prev;
        uint256 pointerID;
        bool active;
        
        // Get initial Group
        (prev, next, pointerID, active) = getGroupOrder(_ein, _seedPointer);
        
        // Get Previous Group | Round Robin Fashion
        (prev, next, pointerID, active) = getGroupOrder(_ein, prev);
       
        uint16 i = 0;
        
        if (_limit >= 20) {
            _limit = 20; // always account for root
        }
        
        while (_limit != 0) {
            
            if (active == false || pointerID == 0) {
                _limit = 0;
                
                if (pointerID == 0) {
                    //add root as Special case
                    groupIndexes[i] = 0;
                    groupNames = append(groupNames, "Root");
                }
            }
            else {
                uint256 groupIndex;
                string memory groupName;
            
                // Get Group
                (groupIndex, groupName) = getGroup(_ein, pointerID);
                
                // Add To Return Vars
                groupIndexes[i] = groupIndex;
                groupName = append(groupName, "|");
                groupNames = append(groupNames, groupName);
                
                // Get Previous Group | Round Robin Fashion
                (prev, next, pointerID, active) = getGroupOrder(_ein, prev);
                
                // Increment counter
                i++;
                
                // Decrease Limit        
                _limit--;
            }
            
        }
    }
    
    /**
     * @dev Create a new Group for the user
     * @param _groupName describes the name of the group
     */
    function createGroup(string memory _groupName) 
    public 
    _isResolverFor() {
        // Returns EIN or Throws Error if not set
        uint256 ein = identityRegistry.getEIN(msg.sender);
        
        // Check if this is unitialized, if so, initialize it, reserved value of 0 is skipped as that's root
        uint256 currentGroupIndex = groupIndex[ein];
        uint256 nextGroupIndex = currentGroupIndex + 1;
        require (nextGroupIndex >= groupIndex[ein], "Limit reached on number of groups, can't create more groups");
        
        // Assign it to User (EIN)
        groups[ein][nextGroupIndex] = Group(
            _groupName
        );
        
        // Add to Stitch Order
        _addToSortOrder(groupOrder[ein], currentGroupIndex, nextGroupIndex);
        
        // increment index
        groupIndex[ein] = nextGroupIndex;
        
        // Trigger Event
        emit GroupCreated(ein, nextGroupIndex);
    }
    
    /**
     * @dev Rename an existing Group for the user / ein
     * @param _groupIndex describes the associated index of the group for the user / ein
     * @param _groupName describes the new name of the group
     */
    function renameGroup(uint256 _groupIndex, string memory _groupName) 
    public 
    _isResolverFor() 
    _onlyNonRootGroup(_groupIndex) {
        
        // Returns EIN or Throws Error if not set
        uint256 ein = identityRegistry.getEIN(msg.sender);
        
        // Check if the group exists or not
        require ((_groupExists(ein, _groupIndex) == true), "Group doesn't exist for the User / EIN");
        
        // Replace the group name
        groups[ein][_groupIndex].name = _groupName;
        
        // Trigger Event
        emit GroupRenamed(ein, _groupIndex);
    }
    
    /**
     * @dev Delete an existing group for the user / ein
     * @param _groupIndex describes the associated index of the group for the user / ein
     */
    function deleteGroup(uint256 _groupIndex) public 
    _isResolverFor() 
    _onlyNonRootGroup(_groupIndex) {
        
        // Returns EIN
        uint256 ein = identityRegistry.getEIN(msg.sender);
         
        // Check if the group exists or not
        uint256 currentGroupIndex = groupIndex[ein];
        require ((_groupIndex <= currentGroupIndex), "Group doesn't exist for the User / EIN");
        
        // Swap Index mapping & remap the latest group ID if this is not the last group
        groups[ein][_groupIndex] = groups[ein][currentGroupIndex];
        
        // Stich sort order to match remap
        _stichSortOrder(groupOrder[ein], _groupIndex, currentGroupIndex);
        
        // Delete the latest group now
        delete (groups[ein][currentGroupIndex]);
        if (groupIndex[ein] != 0) {
            groupIndex[ein] = groupIndex[ein] - 1;
        }
        
        // Trigger Event
        emit GroupDeleted(ein, _groupIndex);
    }
    
    // 3. TRANSFER FILE FUNCTIONS
    
    // 5. WHITELIST / BLACKLIST FUNCTIONS
    /**
     * @dev Check if a user (EIN) is whitelisted for any other user (EIN)
     * @param _forEin is the ein for which the whitelist is targetted
     * @param _queryingEIN is the ein of the recipient which is checked
     */
    function isWhitelisted(uint256 _forEin, uint256 _queryingEIN) 
    public view
    _isResolverFor() 
    _onlyValidEIN(_forEin) 
    _onlyUniqueEIN(_forEin, _queryingEIN) 
    returns (bool) {
        return whitelist[_forEin][_queryingEIN];
    }
    
    /**
    * @dev Check if a user (EIN) is whitelisted for any other user (EIN)
    * @param _forEin is the ein for which the blacklist is targetted
    * @param _queryingEIN is the ein of the recipient which is checked
    */
    function isBlacklisted(uint256 _forEin, uint256 _queryingEIN) 
    public view 
    _isResolverFor() 
    _onlyValidEIN(_forEin) 
    _onlyValidEIN(_queryingEIN) 
    _onlyUniqueEIN(_forEin, _queryingEIN)
    returns (bool) {
        return whitelist[_forEin][_queryingEIN];
    }
    
    /**
    * @dev Add a non-owner user to whitelist
    * @param _nonOwnerEIN is the ein of the recipient
    */
    function addToWhitelist(uint256 _nonOwnerEIN) 
    public
    _isResolverFor() 
    _onlyNonOwner(_nonOwnerEIN) 
    _onlyValidEIN(_nonOwnerEIN) {
        // Returns EIN or Throws Error if not set
        uint256 ein = identityRegistry.getEIN(msg.sender);
        
        //Check if user (EIN) is not on blacklist
        require ((isBlacklisted(ein, _nonOwnerEIN) == false), "EIN is blacklisted, remove EIN from blacklist first to proceed.");
        
        whitelist[ein][_nonOwnerEIN] = true;
        
        // Trigger Event
        emit AddedToWhitelist(ein, _nonOwnerEIN);
    }
    
    /**
    * @dev Remove a non-owner user from whitelist
    * @param _nonOwnerEIN is the ein of the recipient
    */
    function removeFromWhitelist(uint256 _nonOwnerEIN) 
    public
    _isResolverFor() _onlyNonOwner(_nonOwnerEIN) _onlyValidEIN(_nonOwnerEIN) {
        
        // Returns EIN or Throws Error if not set
        uint256 ein = identityRegistry.getEIN(msg.sender);
        require (identityRegistry.isResolverFor(ein, address(this)), "EEIN has not been set this resolver");
        
        //Check if user (EIN) is not on blacklist
        require ((isBlacklisted(ein, _nonOwnerEIN) == false), "EIN is blacklisted, remove EIN from blacklist first to proceed.");
        
        whitelist[ein][_nonOwnerEIN] = false;
        
        // Trigger Event
        emit RemovedFromWhitelist(ein, _nonOwnerEIN);
    }
    
    /**
    * @dev Remove a non-owner user to blacklist
    * @param _nonOwnerEIN is the ein of the recipient
    */
    function addToBlacklist(uint256 _nonOwnerEIN) 
    public
    _onlyNonOwner(_nonOwnerEIN) 
    _onlyValidEIN(_nonOwnerEIN) {
        // Get EIN
        uint256 ein = identityRegistry.getEIN(msg.sender);
        
        //Check if user (EIN) is not on blacklist
        require ((isWhitelisted(ein, _nonOwnerEIN) == false), "EIN is whitelisted, remove EIN from whitelist first to proceed.");
        
        blacklist[ein][_nonOwnerEIN] = true;
        
        // Trigger Event
        emit AddedToBlacklist(ein, _nonOwnerEIN);
    }
    
    /**
    * @dev Remove a non-owner user from blacklist
    * @param _nonOwnerEIN is the ein of the recipient
    */
    function removeFromBlacklist(uint256 _nonOwnerEIN) 
    public
    _isResolverFor() 
    _onlyNonOwner(_nonOwnerEIN) 
    _onlyValidEIN(_nonOwnerEIN) {
        // Get EIN
        uint256 ein = identityRegistry.getEIN(msg.sender);
        
        //Check if user (EIN) is not on blacklist
        require ((isWhitelisted(ein, _nonOwnerEIN) == false), "EIN is whitelisted, remove EIN from blacklist first to proceed.");
        
        whitelist[ein][_nonOwnerEIN] = false;
        
        // Trigger Event
        emit RemovedFromBlacklist(ein, _nonOwnerEIN);
    }
    
    // *. DOUBLE LINKED LIST (ROUND ROBIN) FOR OPTIMIZATION / DELETE / ADD 
    /**
    * @dev Private function to facilitate adding of double linked list used to preserve order and form cicular linked list
    * @param _orderMapping is the relevant sort order of Files, Groups, Transfers, etc 
    * @param _currentIndex is the index which is currently the maximum
    * @param _nextIndex is the index which will next index used to store Files, Groups, Transfers, etc
    */
    function _addToSortOrder(mapping(uint256 => SortOrder) storage _orderMapping, uint256 _currentIndex, uint256 _nextIndex)  
    internal {
        // Assign current order to next pointer
        _orderMapping[_currentIndex].next = _nextIndex;
        _orderMapping[_currentIndex].active = true;
        
        // Special case of root of sort order 
        if (_currentIndex == 0) {
            _orderMapping[0].next = _nextIndex;
        }
        
        // Assign initial group prev order
        _orderMapping[0].prev = _nextIndex;
            
        // Assign next group order pointer and prev pointer
        _orderMapping[_nextIndex] = SortOrder(
            0, // next index
            _currentIndex, // prev index
            _nextIndex, // pointerID
            true // mark as active
        );
    }
    
    /**
    * @dev Private function to facilitate stiching of double linked list used to preserve order with delete
    * @param _orderMapping is the relevant sort order of Files, Groups, Transfer, etc 
    * @param _remappedIndex is the index which is swapped to from the latest index
    * @param _maxIndex is the index which will always be maximum
    */
    function _stichSortOrder(mapping(uint256 => SortOrder) storage _orderMapping, uint256 _remappedIndex, uint256 _maxIndex) 
    internal {
        
        // Stich Order
        uint256 prevGroupIndex = _orderMapping[_remappedIndex].prev;
        uint256 nextGroupIndex = _orderMapping[_remappedIndex].next;
        uint256 latestOrder = _orderMapping[0].prev;
        
        _orderMapping[prevGroupIndex].next = nextGroupIndex;
        _orderMapping[nextGroupIndex].prev = prevGroupIndex;
        
        // Check if this is not the top order number
        if (_remappedIndex != _maxIndex) {
            // Change order mapping and remap
            _orderMapping[_remappedIndex] = _orderMapping[_maxIndex];
            _orderMapping[_remappedIndex].pointerID = _remappedIndex;
            
            _orderMapping[_orderMapping[_remappedIndex].next].prev = _remappedIndex;
            _orderMapping[_orderMapping[_remappedIndex].prev].next = _remappedIndex;
        }
        
        // Turn off the non-stich group
        _orderMapping[_maxIndex].active = false;
    }
    
    // *. GENERAL CONTRACT HELPERS
    function append(string memory a, string memory b) internal pure returns (string memory) {
        return string(abi.encodePacked(a, b));
    }
    
    // *. FOR DEBUGGING CONTRACT
    // To Build Groups for users
    function debugBuildGroups() 
    public {
        createGroup("A");
        createGroup("B");
        createGroup("C");
        createGroup("D");
        createGroup("E");
        createGroup("F");
        createGroup("G");
        createGroup("H");
    }
}





