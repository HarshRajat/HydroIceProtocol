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
contract Ice is SnowflakeResolver {   
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
    mapping (uint256 => mapping(uint256 => Association)) globalItems;
    uint256 public globalItemsIndex1; // store the first index of association to retrieve files
    uint256 public globalItemsIndex2; // store the first index of association to retrieve files
    
    /* for each user (EIN), look up the Transitioon State they have
     * stored on a given index.
     */
    mapping (uint256 => AtomicityState) public userAtomicity;
     
    /* for each user (EIN), look up the file they have
     * stored on a given index.
     */ 
    mapping (uint256 => mapping(uint256 => File)) private files;
    mapping (uint256 => mapping(uint256 => SortOrder)) public fileOrder; // Store round robin order of files
    mapping (uint256 => uint256) public fileCount; // store the maximum file count reached to provide looping functionality
    
    /* for each user (EIN), look up the group they have
     * stored on a given index. Default group 0 indicates
     * root folder
     */ 
    mapping (uint256 => mapping(uint256 => Group)) private groups;
    mapping (uint256 => mapping(uint256 => SortOrder)) public groupOrder; // Store round robin order of group
    mapping (uint256 => uint256) public groupCount; // store the maximum group count reached to provide looping functionality
    
    /* for each user (EIN), look up the incoming transfer request
     * stored on a given index.
     */ 
    mapping (uint256 => mapping(uint256 => Association)) transfers;
    mapping (uint256 => mapping(uint256 => SortOrder)) public transferOrder; // Store round robin order of transfers
    mapping (uint256 => uint256) public transferIndex; // store the maximum transfer request count reached to provide looping functionality
    
    /* for each user (EIN), look up the incoming sharing files
     * stored on a given index.
     */ 
    mapping (uint256 => mapping(uint256 => Association)) sharings;
    mapping (uint256 => mapping(uint256 => SortOrder)) public sharingOrder; // Store round robin order of sharing
    mapping (uint256 => uint256) public shareCount; // store the maximum shared items count reached to provide looping functionality
    
    /* for each user (EIN), look up the incoming sharing files
     * stored on a given index.
     */ 
    mapping (uint256 => mapping(uint256 => Association)) stampings;
    mapping (uint256 => mapping(uint256 => SortOrder)) public stampingOrder; // Store round robin order of stamping
    mapping (uint256 => uint256) public stampingCount; // store the maximum file index reached to provide looping functionality
    
    /* for each user (EIN), look up the incoming sharing files
     * stored on a given index.
     */ 
    mapping (uint256 => mapping(uint256 => Association))  stampingsRequest;
    mapping (uint256 => mapping(uint256 => SortOrder)) public stampingsRequestOrder; // Store round robin order of stamping requests
    mapping (uint256 => uint256) public stampingsRequestCount; // store the maximum file index reached to provide looping functionality
    
    /* for each user (EIN), have a whitelist and blacklist
     * association which can handle certain functions automatically.
     */
    mapping (uint256 => mapping(uint256 => bool)) public whitelist;
    mapping (uint256 => mapping(uint256 => bool)) public blacklist;
    
    /* for referencing SnowFlake for Identity Registry (ERC-1484).
     */
    SnowflakeInterface public snowflake;
    IdentityRegistryInterface public identityRegistry;
   
    /* ***************
    * DEFINE STRUCTURES
    *************** */
    /* To define ownership info of a given Item.
     */
    struct ItemOwner {
        uint256 ownerEIN; // the EIN of the owner
        uint256 itemIndex; // the key at which the item is stored
    }
     
    /* To define global file association with EIN
     * Combining EIN and itemIndex and properties will give access to
     * item data.
     */
    struct Association {
        ItemOwner ownerInfo; // To Store Iteminfo
        
        bool isFile; // whether the Item is File or Group
        bool isLocked; // Whether the item requires stamping 
        bool deleted; // whether the association is deleted 
        
        // Item Sharing Properties        
        mapping (uint256 => ItemOwner) sharedTo; // 0 - Contains User EIN, 1 Contains specific index
        uint256 sharedToCount; // the count of sharing        
        
        // Item Stamping Properties
        mapping (uint256 => ItemOwner) stampingReqs; // to have stamping reqs count 
        uint256 stampingReqsCount; // the count of stamping
    }
    
    struct GlobalRecord {
        uint256 index1; // store associated global index 1 for access
        uint256 index2; // store associated global index 2 for access
    }

    /* To define File structure of all stored files
     */
    struct File {
        // File Meta Data
        GlobalRecord record; // store the association in global record
        uint256 fileOwner; // store file owner EIN
        
        // File Properties
        uint8 protocol; // store protocol of the file stored | 0 is URL, 1 is IPFS
        string name; // the name of the file
        string hash; // store the hash of the file for verification | 0x000 for deleted files
        mapping(uint8 => string) metadata; // store any metadata required as per protocol
        uint256 timestamp; // to store the timestamp of the block when file is created
        
        // File Properties - Encryption Properties
        bool encrypted; // whether the file is encrypted
        mapping (address => string) encryptedHash; // Maps Individual address to the stored hash
        
        // File Group Properties 
        uint256 associatedGroupIndex;
        uint256 associatedGroupFileIndex;
    
        // File Transfer Properties
        mapping (uint256 => uint256) transferHistory; // To maintain histroy of transfer of all EIN
        uint256 transferCount; // To maintain the transfer count for mapping
        uint256 transferEIN; // To record EIN of the user to whom trasnfer is inititated
        uint256 transferIndex; // To record the transfer specific index of the transferee
        bool markedForTransfer; // Mark the file as transferred
    }
    
    /* To connect Files in linear grouping,
     * sort of like a folder, 0 or default grooupID is root
     */
    struct Group {
        GlobalRecord record; // store the association in global record
        
        string name; // the name of the Group
        
        mapping (uint256 => SortOrder) groupFilesOrder; // the order of files in the current group
        uint256 groupFilesCount; // To keep the count of group files
    }
    
    /* To define the order required to have double linked list
     */
    struct SortOrder {
        uint256 next; // the next ID of the order
        uint256 prev; // the prev ID of the order
        
        uint256 pointerID; // what it should point to in the mapping
        
        bool active; // whether the node is active or not
    }

    /* To define state and flags for Individual things,
     * used in cases where state change should be atomic
     */
    struct AtomicityState {
        bool lockFiles;
        bool lockGroups;
        bool lockTransfers;
        bool lockSharings;
    }
    
    /* ***************
    * DEFINE EVENTS
    *************** */
    // When File is created
    event FileCreated(
        uint EIN,
        uint fileIndex,
        string fileName
    );
    
    // When File is renamed
    event FileRenamed(
        uint EIN,
        uint fileIndex,
        string fileName
    );
    
    // When File is moved
    event FileMoved(
        uint EIN,
        uint fileIndex,
        uint groupIndex,
        uint groupFileIndex
    );
    
    // When File is deleted
    event FileDeleted(
        uint EIN,
        uint fileIndex
    );
    
    // When Group is created
    event GroupCreated(
        uint EIN,
        uint groupIndex,
        string groupName
    );
    
    // When Group is renamed
    event GroupRenamed(
        uint EIN,
        uint groupIndex,
        string groupName
    );
    
    // When Group Status is changed
    event GroupDeleted(
        uint EIN,
        uint groupIndex,
        uint groupReplacedIndex
    );
    
    // When Transfer is initiated from owner
    event FileTransferInitiated(
        uint indexed EIN,
        uint indexed transfereeEIN,
        uint indexed fileID
    );
    
    // When whitelist is updated
    event AddedToWhitelist(
        uint EIN,
        uint recipientEIN
    );
    
    event RemovedFromWhitelist(
        uint EIN,
        uint recipientEIN
    );
    
    // When blacklist is updated
    event AddedToBlacklist(
        uint EIN,
        uint recipientEIN
    );
    
    event RemovedFromBlacklist(
        uint EIN,
        uint recipientEIN
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
    
    /* ***************
    * DEFINE CONTRACT FUNCTIONS
    *************** */
    // 1. GLOBAL ITEMS FUNCTIONS
    /**
     * @dev Function to get global items 
     * @param _index1 is the first index of item
     * @param _index2 is the second index of item
     */
    function getGlobalItems(uint256 _index1, uint256 _index2) 
    public view
    returns (uint256 ownerEIN, uint256 itemRecord, bool isFile, bool isLocked, bool deleted, uint256 sharedToCount, uint256 stampingReqsCount) {
        ownerEIN = globalItems[_index1][_index2].ownerInfo.ownerEIN;
        itemRecord = globalItems[_index1][_index2].ownerInfo.itemIndex;
        
        isFile = globalItems[_index1][_index2].isFile;
        isLocked = globalItems[_index1][_index2].isLocked;
        deleted = globalItems[_index1][_index2].deleted;
    
        sharedToCount = globalItems[_index1][_index2].sharedToCount;
        stampingReqsCount = globalItems[_index1][_index2].stampingReqsCount;
    }
    
    
    /**
     * @dev Private Function to add item to global items
     * @param _ownerEIN is the EIN of global items
     * @param _itemIndex is the index at which the item exists on the user mapping 
     * @param _isFile indicates if the item is file or group
     * @param _isLocked indicates if the item has is Locked or not
     */
    function _addItemToGlobalItems(uint256 _ownerEIN, uint256 _itemIndex, bool _isFile, bool _isLocked) 
    private 
    returns (uint256 globalIndex1, uint256 globalIndex2){
        // Increment global Item (0, 0 is always reserved | Is User Avatar)
        globalItemsIndex1 = globalItemsIndex1;
        globalItemsIndex2 = globalItemsIndex2 + 1;
        
        if (globalItemsIndex2 == 0) {
            // This is loopback, Increment newIndex1
            globalItemsIndex1 = globalItemsIndex1 + 1;
            
            require (
                globalItemsIndex1 > 0,
                "Storage Full"
            );
        }
        
        ItemOwner memory owner = ItemOwner (
            _ownerEIN, // Owner EIN 
            _itemIndex // Item stored at what index for that EIN
        );
        
        // Add item to global item, no stiching it 
        globalItems[globalItemsIndex1][globalItemsIndex2] = Association (
            owner, // Item Owner Info
            
            _isFile, // Item is file or group
            _isLocked, // whether stamping is initiated or not
            true, // Item is deleted or still exists
            
            0, // the count of shared EINs 
            0 // the count of stamping requests
        );
        
        globalIndex1 = globalItemsIndex1;
        globalIndex2 = globalItemsIndex2;
    }
    
    /**
     * @dev Private Function to delete a global items 
     * @param _record is the GlobalRecord Struct
     */
    function _deleteGlobalRecord(GlobalRecord memory _record) 
    internal {
        globalItems[_record.index1][_record.index2].deleted = true;
    }
    
    // 2. FILE FUNCTIONS
    /**
     * @dev Function to get Meta Data of File
     * @param _ein is the EIN of the user
     * @param _fileIndex is the index of the file
     */
    function getFileMetaData(uint256 _ein, uint256 _fileIndex) 
    public view 
    returns (uint256 fileOwner, uint256 globalIndex1, uint256 globalIndex2) {
        fileOwner = files[_ein][_fileIndex].fileOwner;
        
        globalIndex1 = files[_ein][_fileIndex].record.index1;
        globalIndex2 = files[_ein][_fileIndex].record.index2;
    }
    
    /**
     * @dev Function to add File
     * @param _protocol is the protocol used
     * @param _name is the name of the file 
     * @param _hash is the hash of the stored file
     * @param _metadata is the data stored for protocol usage 
     * @param _encrypted defines if the file is encrypted or not
     * @param _encryptedHash defines the encrypted public key password for the sender address
     * @param _groupIndex defines the index of the group of file
     */
    function addFile(uint8 _protocol, string memory _name, string memory _hash, string memory _metadata, bool _encrypted, string memory _encryptedHash, uint256 _groupIndex) 
    public {
        uint256 ein = identityRegistry.getEIN(msg.sender);
        
        require (
          (userAtomicity[ein].lockFiles == false),
          "Can't proceed, Files are locked for other operation."
        );
        
        require (
          (userAtomicity[ein].lockGroups == false),
          "Can't proceed, Groups are locked for other operation."
        );
        
        require (
            (_groupExists(ein, _groupIndex) == true), 
            "Group doesn't exist for the User."
        );
        
        // Set File & Group Atomicity
        userAtomicity[ein].lockFiles = true;
        userAtomicity[ein].lockGroups = true;
        
        uint256 currentFileIndex = fileCount[ein];
        uint256 nextFileIndex = currentFileIndex + 1;
        
        // Add to Global Items 
        uint256 index1;
        uint256 index2;
        (index1, index2) = _addItemToGlobalItems(ein, nextFileIndex, false, false);
    
        // Finally create the file it to User (EIN)
        files[ein][nextFileIndex] = File (
            GlobalRecord(
                index1, // Global Index 1 
                index2 // Global Index 2
            ),
            
            ein, // File Owner
            _protocol, // Protocol For Interpretation
            _name, // Name of File
            _hash, // Hash of File
            now, // Timestamp of File
            
            _encrypted, // File Encyption
            
            _groupIndex, // Store the group index
            _addFileToGroup(ein, _groupIndex, nextFileIndex), // Add File to Group and store the group file order index
            
            1, // Transfer Count, treat creation as a transfer count 
            0, // Transfer EIN
            0, // Transfer Index for Transferee 
            
            false // File is not flagged for Transfer
        );
        
        // Recreate Meta Data | 0 is Extension | Find a workaround for this
        files[ein][nextFileIndex].metadata[0] = _metadata;
        
        // To map encrypted password
        files[ein][nextFileIndex].encryptedHash[msg.sender] = _encryptedHash;
        
        // To map transfer history 
        files[ein][nextFileIndex].transferHistory[0] = ein;
        
        // Add to Stitch Order & Increment index
        fileCount[ein] = _addToSortOrder(fileOrder[ein], currentFileIndex, 0);
        
        // Add file pointer to group
        groups[ein][_groupIndex].groupFilesCount = _addToSortOrder(groups[ein][_groupIndex].groupFilesOrder, groups[ein][_groupIndex].groupFilesCount, 0);

        // Trigger Event
        emit FileCreated(ein, nextFileIndex, _name);
        
        // Reset Files & Group Atomicity
        userAtomicity[ein].lockFiles = false;
        userAtomicity[ein].lockGroups = false;
    }
    
    /**
     * @dev Function to change File Name
     * @param _ein is the owner EIN
     * @param _fileIndex is the index where file is stored
     * @param _name is the name of stored file
     */
    function changeFileName(uint256 _ein, uint256 _fileIndex, string memory _name) 
    public 
    _onlyOwner(_ein) {
        files[_ein][_fileIndex].name = _name;
        
        // Trigger Event
        emit FileRenamed(_ein, _fileIndex, _name);
    }
    
    /**
     * @dev Function to move file to another group
     * @param _ein is the owner EIN
     * @param _fileIndex is the index where file is stored
     * @param _newGroupIndex is the index of the new group where file has to be moved
     */
    function moveFileToGroup(uint256 _ein, uint256 _fileIndex, uint256 _newGroupIndex) 
    public 
    _onlyOwner(_ein) 
    _onlyUnlockedItem(_ein, _fileIndex) 
    _onlyEnforcedAtomityFiles(_ein) 
    _onlyEnforcedAtomityGroups(_ein) {
        // Set Files & Group Atomicity
        userAtomicity[_ein].lockFiles = true;
        userAtomicity[_ein].lockGroups = true;
        
        require (
            (_groupExists(_ein, _newGroupIndex) == true), 
            "Group doesn't exist for the User."
        );
        
        uint256 newGroupFileIndex = _remapFileToGroup(_ein, files[_ein][_fileIndex].associatedGroupIndex, files[_ein][_fileIndex].associatedGroupFileIndex, _newGroupIndex);
        
        // Trigger Event
        emit FileMoved(_ein, _fileIndex, _newGroupIndex, newGroupFileIndex);
        
        // Reset Files & Group Atomicity
        userAtomicity[_ein].lockFiles = false;
        userAtomicity[_ein].lockGroups = false;
    }
    
    /**
     * @dev Function to delete file
     * @param _ein is the owner EIN
     * @param _fileIndex is the index where file is stored
     */
    function deleteFile(uint256 _ein, uint256 _fileIndex) 
    public 
    _onlyOwner(_ein) 
    _onlyUnlockedItem(_ein, _fileIndex) {
        // Set Files & Group Atomicity
        userAtomicity[_ein].lockFiles = true;
        userAtomicity[_ein].lockGroups = true;
        
        // Get current Index, Stich check previous index so not required to recheck 
        uint256 currentIndex = fileCount[_ein];
        
        // Deactivate From Global Items 
        _deleteGlobalRecord(files[_ein][_fileIndex].record);
        
        // Remove from Group which holds the File
        _removeFileFromGroup(_ein, files[_ein][_fileIndex].associatedGroupIndex, files[_ein][_fileIndex].associatedGroupFileIndex);
        
        // Swap File
        files[_ein][_fileIndex] = files[_ein][currentIndex];
        fileCount[_ein] = _stichSortOrder(fileOrder[_ein], _fileIndex, currentIndex, 0);
        
        // Trigger Event
        emit FileDeleted(_ein, _fileIndex);
        
        // Reset Files & Group Atomicity
        userAtomicity[_ein].lockFiles = false;
        userAtomicity[_ein].lockGroups = false;
    }
    
    /**
     * @dev Private Function to add file to a group
     * @param _ein is the EIN of the intended user
     * @param _groupIndex is the index of the group belonging to that user, 0 is reserved for root
     * @param _fileIndex is the index of the file belonging to that user
     */
    function _addFileToGroup(uint256 _ein, uint256 _groupIndex, uint256 _fileIndex) 
    internal
    returns (uint256) {
        // Add File to a group is just adding the index of that file
        uint256 currentIndex = groups[_ein][_groupIndex].groupFilesCount;
        groups[_ein][_groupIndex].groupFilesCount = _addToSortOrder(groups[_ein][_groupIndex].groupFilesOrder, currentIndex, _fileIndex);
        
        // Map group index and group order index in file 
        files[_ein][_fileIndex].associatedGroupIndex = _groupIndex;
        files[_ein][_fileIndex].associatedGroupFileIndex = groups[_ein][_groupIndex].groupFilesCount;
        
        return groups[_ein][_groupIndex].groupFilesCount;
    }
    
    /**
     * @dev Private Function to remove file from a group
     * @param _ein is the EIN of the intended user
     * @param _groupIndex is the index of the group belonging to that user
     * @param _groupFileOrderIndex is the index of the file order within that group
     */
    function _removeFileFromGroup(uint256 _ein, uint256 _groupIndex, uint256 _groupFileOrderIndex) 
    internal 
    _onlyValidGroupOrder(_ein, _groupFileOrderIndex) {
        uint256 maxIndex = groups[_ein][_groupIndex].groupFilesCount;
        uint256 pointerID = groups[_ein][_groupIndex].groupFilesOrder[maxIndex].pointerID;
        
        groups[_ein][_groupIndex].groupFilesCount = _stichSortOrder(groups[_ein][_groupIndex].groupFilesOrder, _groupFileOrderIndex, maxIndex, pointerID);
    }
    
    /**
     * @dev Private Function to remap file from one group to another
     * @param _ein is the EIN of the intended user
     * @param _groupIndex is the index of the group belonging to that user, 0 is reserved for root
     * @param _groupFileOrderIndex is the index of the file order within that group
     * @param _newGroupIndex is the index of the new group belonging to that user
     */
    function _remapFileToGroup(uint256 _ein, uint256 _groupIndex, uint256 _groupFileOrderIndex, uint256 _newGroupIndex) 
    internal 
    _onlyValidGroupOrder(_ein, _groupFileOrderIndex) 
    returns (uint256) {
        // Get file index for the Association
        uint256 fileIndex = groups[_ein][_groupIndex].groupFilesOrder[_groupFileOrderIndex].pointerID;
        
        // Remove File from existing group
        _removeFileFromGroup(_ein, _groupIndex, _groupFileOrderIndex);
        
        // Add File to new group 
        return _addFileToGroup(_ein, _newGroupIndex, fileIndex);
    }
    
    // 3. GROUP FUNCTIONS
    /**
     * @dev Private Function to check if group exists
     * @param _ein the EIN of the user
     * @param _groupIndex the index of the group
     */
    function _groupExists(uint256 _ein, uint256 _groupIndex) 
    internal view 
    returns (bool) {
        // Check if the group exists or not
        uint256 currentGroupIndex = groupCount[_ein];
        
        if (_groupIndex <= currentGroupIndex) {
            return true;
        }
        
        return false;
    }
    
    /**
     * @dev Function to return group info for an EIN
     * @param _ein the EIN of the user
     * @param _groupIndex the index of the group
     */
    function getGroup(uint256 _ein, uint256 _groupIndex)
    public view
    _onlyOwner(_ein)
    returns (uint256 index, string memory name) {
        
        // Check if the group exists or not
        require (
            (_groupExists(_ein, _groupIndex) == true), 
            "Group doesn't exist for the User / EIN"
        );
        
        index = _groupIndex;
        
        if (_groupIndex == 0) {
            name = "Root";
        }
        else {
            name = groups[_ein][_groupIndex].name;
        }
    }
    
    /**
     * @dev Function to return group indexes used to retrieve info about group
     * @param _ein the EIN of the user
     */
    function getGroupIndexes(uint256 _ein, uint256 _seedPointer, uint16 _limit, bool _asc) 
    public view 
    returns (uint256[20] memory groupIndexes) { 
        groupIndexes = _getIndexes(groupOrder[_ein], _seedPointer, _limit, _asc);
    }
    
    /**
     * @dev Create a new Group for the user
     * @param _ein should be the EIN of the user
     * @param _groupName describes the name of the group
     */
    function createGroup(uint256 _ein, string memory _groupName) 
    public 
    _onlyOwner(_ein)
    _onlyEnforcedAtomityGroups(_ein) {
        // Set Group Atomicity
        userAtomicity[_ein].lockGroups = true;
        
        // Check if this is unitialized, if so, initialize it, reserved value of 0 is skipped as that's root
        uint256 currentGroupIndex = groupCount[_ein];
        uint256 nextGroupIndex = currentGroupIndex + 1;
        require (
            nextGroupIndex > currentGroupIndex, 
            "Limit reached on number of groups, can't create more groups"
        );
        
        // Add to Global Items 
        uint256 index1;
        uint256 index2;
        (index1, index2) = _addItemToGlobalItems(_ein, nextGroupIndex, false, false);

        // Assign it to User (EIN)
        groups[_ein][nextGroupIndex] = Group(
            GlobalRecord(
                index1, // Global Index 1 
                index2 // Global Index 2
            ),
            
            _groupName, //name of Group
            0 // The group file count
        );
        
        // Add to Stitch Order & Increment index
        groupCount[_ein] = _addToSortOrder(groupOrder[_ein], currentGroupIndex, 0);

        // Trigger Event
        emit GroupCreated(_ein, nextGroupIndex, _groupName);
        
        // Reset Group Atomicity
        userAtomicity[_ein].lockGroups = false;
    }
    
    /**
     * @dev Rename an existing Group for the user / ein
     * @param _ein should be the EIN of the user
     * @param _groupIndex describes the associated index of the group for the user / ein
     * @param _groupName describes the new name of the group
     */
    function renameGroup(uint256 _ein, uint256 _groupIndex, string memory _groupName) 
    public 
    _onlyOwner(_ein)
    _onlyNonReservedItem(_groupIndex) {
        // Check if the group exists or not
        require (
            (_groupExists(_ein, _groupIndex) == true), 
            "Group doesn't exist for the User."
        );
        
        // Replace the group name
        groups[_ein][_groupIndex].name = _groupName;
        
        // Trigger Event
        emit GroupRenamed(_ein, _groupIndex, _groupName);
    }
    
    /**
     * @dev Delete an existing group for the user / ein
     * @param _ein should be the EIN of the user
     * @param _groupIndex describes the associated index of the group for the user / ein
     */
    function deleteGroup(uint256 _ein, uint256 _groupIndex) public 
    _onlyOwner(_ein)
    _onlyZeroFilesGroup(_ein, _groupIndex)
    _onlyNonReservedItem(_groupIndex) 
    _onlyEnforcedAtomityGroups(_ein) {
        // Set Group Atomicity
        userAtomicity[_ein].lockGroups = true;
         
        // Check if the group exists or not
        uint256 currentGroupIndex = groupCount[_ein];
        require ((_groupIndex <= currentGroupIndex), "Group doesn't exist for the User / EIN");
        
        // Mark the item as deleted in global items
        _deleteGlobalRecord(groups[_ein][_groupIndex].record);
        
        // Swap Index mapping & remap the latest group ID if this is not the last group
        groups[_ein][_groupIndex] = groups[_ein][currentGroupIndex];
        groupCount[_ein] = _stichSortOrder(groupOrder[_ein], _groupIndex, currentGroupIndex, 0);
        
        // Delete the latest group now
        delete (groups[_ein][currentGroupIndex]);
        
        // Trigger Event
        emit GroupDeleted(_ein, _groupIndex, currentGroupIndex);
        
        // Reset Group Atomicity
        userAtomicity[_ein].lockGroups = false;
    }
    
    // 4. SHARING FUNCTIONS
    
    // 5. STAMPING FUNCTIONS
    
    // 6. TRANSFER FILE FUNCTIONS
    /**
     * @dev Function to intiate file transfer to another EIN(user)
     * @param _transfererEIN is the original user's EIN 
     * @param _fileIndex is the index of file for the original user's EIN
     * @param _transfereeEIN is the recipient user's EIN
     */
    function initiateFileTransfer(uint256 _transfererEIN, uint256 _fileIndex, uint256 _transfereeEIN) 
    public 
    _onlyValidEIN(_transfereeEIN)
    _onlyOwner(_transfererEIN) 
    _onlyUniqueEIN(_transfererEIN, _transfereeEIN)
    _onlyEnforcedAtomityTransfers(_transfererEIN)
    _onlyEnforcedAtomityTransfers(_transfereeEIN)
    _onlyUnlockedItem(_transfererEIN, _fileIndex) {
        // Set Transfers Atomiticy
        userAtomicity[_transfererEIN].lockTransfers = true;
        userAtomicity[_transfereeEIN].lockTransfers = true;
        
        // Check if the file is not markedForTransfer
        require (
            (files[_transfererEIN][_fileIndex].markedForTransfer == false), 
            "Can't proceed, file is already marked for Transfer."
        );
        
        // Check if the transfereeEIN has blacklisted current owner
        require (
            (blacklist[_transfereeEIN][_transfererEIN] == true), 
            "Can't initiate file transfer as the owner has blacklisted you."
        );
        // Check and change flow if white listed
        if (whitelist[_transfereeEIN][_transfererEIN] == true) {
            // Directly transfer file, 0 is always root group
            _doFileTransfer(_transfererEIN, _fileIndex, _transfereeEIN, 0);
        }
        else {
           // Request based file Transfers
           _initiateRequestedFileTransfer(_transfererEIN, _fileIndex, _transfereeEIN);
        }
        
        // Reset Transfers Atomiticy
        userAtomicity[_transfererEIN].lockTransfers = false;
        userAtomicity[_transfereeEIN].lockTransfers = false;
    }
    
    /**
     * @dev Private Function to initiate requested file transfer
     * @param _transfererEIN is the owner EIN
     * @param _fileIndex is the index where file is stored
     * @param _transfereeEIN is the EIN of the user to whom the file needs to be transferred
     */
    function _initiateRequestedFileTransfer(uint256 _transfererEIN, uint256 _fileIndex, uint256 _transfereeEIN) 
    internal {
         // Map it to transferee mapping of transfers 
        // Add to transfers of TransfereeEIN User, 0 is always reserved
        uint256 currentTransferIndex = transferIndex[_transfereeEIN];
        uint256 nextTransferIndex = currentTransferIndex + 1;
        
        require (
            (nextTransferIndex > currentTransferIndex), 
            "Limit reached on number of transfers, can't transfer more files to that EIN (User) till they clear it up."
        );
    
        // Mark the file for transfer
        files[_transfererEIN][_fileIndex].markedForTransfer = true;
        files[_transfererEIN][_fileIndex].transferEIN = _transfereeEIN;
        files[_transfereeEIN][_fileIndex].transferIndex = nextTransferIndex;
    
        // Get Item Association Index
        uint256 globalIndex1;
        uint256 globalIndex2;
        (, globalIndex1, globalIndex2) = getFileMetaData(_transfererEIN, _fileIndex);
        
        // Check Item is file
        require (
            (globalItems[globalIndex1][globalIndex2].isFile == true),
            "Non-Transferable"
        );
        
        // Create New Transfer
        transfers[_transfereeEIN][nextTransferIndex] = globalItems[globalIndex1][globalIndex2];
        
        // Update sort order and index
        transferIndex[_transfereeEIN] = _addToSortOrder(transferOrder[_transfererEIN], currentTransferIndex, 0);
        
        // Trigger Event
        emit FileTransferInitiated(_transfererEIN, _transfereeEIN, _fileIndex);
    }
    
    /**
     * @dev Function to accept file transfer from a user
     * @param _transfererEIN is the previous(current) owner EIN
     * @param _fileIndex is the index where file is stored
     * @param _transfereeEIN is the EIN of the user to whom the file needs to be transferred
     * @param _transferSpecificIndex is the file mapping stored no the recipient transfers mapping 
     * @param _groupIndex is the index of the group where the file is suppose to be for the recipient
     */
    function acceptFileTransfer(uint256 _transfererEIN, uint256 _fileIndex, uint256 _transfereeEIN, uint256 _transferSpecificIndex, uint256 _groupIndex) 
    public 
    _onlyOwner(_transfereeEIN)
    _onlyEnforcedAtomityTransfers(_transfererEIN)
    _onlyEnforcedAtomityTransfers(_transfereeEIN)
    _onlyFileNonOwner(_transfererEIN, _fileIndex) 
    _onlyMarkedForTransferee(_transfererEIN, _fileIndex, _transfererEIN) {
        // Set Transfers Atomiticy
        userAtomicity[_transfererEIN].lockTransfers = true;
        userAtomicity[_transfereeEIN].lockTransfers = true;
        
        // Check if the item is marked for transfer 
        require (
            (files[_transfererEIN][_fileIndex].markedForTransfer == true), 
            "Can't proceed, item is not marked for Transfer."
        );
        
        // Do file transfer
        _doFileTransfer(_transfererEIN, _fileIndex, _transfereeEIN, _groupIndex);
        
        // Finally remove the file from Tranferee Mapping 
        _removeFileFromTransfereeMapping(_transfereeEIN, _transferSpecificIndex);
        
        // Reset Transfers Atomiticy
        userAtomicity[_transfererEIN].lockTransfers = false;
        userAtomicity[_transfereeEIN].lockTransfers = false;
    }
    
    /**
     * @dev Private Function to do file transfer from previous (current) owner to new owner
     * @param _transfererEIN is the previous(current) owner EIN
     * @param _fileIndex is the index where file is stored
     * @param _transfereeEIN is the EIN of the user to whom the file needs to be transferred
     * @param _groupIndex is the index of the group where the file is suppose to be for the recipient
     */
    function _doFileTransfer(uint256 _transfererEIN, uint256 _fileIndex, uint256 _transfereeEIN, uint256 _groupIndex) 
    internal {
        // Get Indexes
        uint256 currentTransfererIndex = fileCount[_transfererEIN];
        uint256 currentTransfereeIndex = fileCount[_transfereeEIN];
        
        uint256 prevTransfererIndex = currentTransfererIndex - 1;
        require (
            (prevTransfererIndex >= 0),
            "No file found in the transferer db"
        );
        
        uint256 nextTransfereeIndex =  currentTransfereeIndex + 1;
        require (
            (nextTransfereeIndex > currentTransfereeIndex),
            "Trasnferee User has run out of transfer slots."
        );
        
        // Transfer the file to the transferee
        files[_transfereeEIN][nextTransfereeIndex] = files[_transfererEIN][_fileIndex];
        
        // Change file properties and transfer history
        uint256 tc = files[_transfereeEIN][nextTransfereeIndex].transferCount;
        tc = tc + 1;
        require (
            (tc > 0),
            "Transfers Full"
        );
        
        files[_transfereeEIN][nextTransfereeIndex].fileOwner = _transfereeEIN;
        files[_transfereeEIN][nextTransfereeIndex].transferHistory[tc] = _transfereeEIN;
        files[_transfereeEIN][nextTransfereeIndex].markedForTransfer = false;
        files[_transfereeEIN][nextTransfereeIndex].transferCount = tc;
        
        // add to transferee sort order & Increment index
        fileCount[_transfereeEIN] = _addToSortOrder(fileOrder[_transfereeEIN], currentTransfereeIndex, 0);
        
        // Remove the file from transferer group
        _removeFileFromGroup(_transfererEIN, files[_transfererEIN][currentTransfererIndex].associatedGroupIndex, files[_transfererEIN][currentTransfererIndex].associatedGroupFileIndex);
        
        // Remove the file from transferer, ie swap mapping and stich sort order
        files[_transfererEIN][_fileIndex] = files[_transfererEIN][currentTransfererIndex];
        fileCount[_transfererEIN] = _stichSortOrder(fileOrder[_transfererEIN], _fileIndex, currentTransfererIndex, 0);
        
        // Add File to transferee group 
        _addFileToGroup(_transfereeEIN, _groupIndex, fileCount[_transfereeEIN]);
        
        // Get global association
        uint256 globalIndex1;
        uint256 globalIndex2;
        (, globalIndex1, globalIndex2) = getFileMetaData(_transfereeEIN, _fileIndex);
        
        // Update global file association
        globalItems[globalIndex1][globalIndex2].ownerInfo.ownerEIN = _transfereeEIN;
        globalItems[globalIndex1][globalIndex2].ownerInfo.itemIndex = nextTransfereeIndex;
    }
    
    /**
     * @dev Private Function to remove file from Transfers mapping of Transferee after file is transferred to them
     * @param _transfereeEIN is the new owner EIN
     * @param _transferSpecificIndex is the index of the association mapping of transfers
     */
    function _removeFileFromTransfereeMapping(uint256 _transfereeEIN, uint256 _transferSpecificIndex) 
    internal {
        // Get Cureent Transfer Index
        uint256 currentTransferIndex = transferIndex[_transfereeEIN];

        require (
            (currentTransferIndex > 0),
            "Index Not Found"
        );
        
        // Remove the file from transferer, ie swap mapping and stich sort order
        transfers[_transfereeEIN][_transferSpecificIndex] = transfers[_transfereeEIN][currentTransferIndex];
        transferIndex[_transfereeEIN] = _stichSortOrder(transferOrder[_transfereeEIN], _transferSpecificIndex, currentTransferIndex, 0);
        
        // Retrive the swapped item record and change the transferIndex to remap correctly
        Association memory item = transfers[_transfereeEIN][_transferSpecificIndex];
        
        if (item.isFile == true) {
            //Only File is supported  
            files[item.ownerInfo.ownerEIN][item.ownerInfo.itemIndex].transferIndex = _transferSpecificIndex;
        }
    }
    
    /**
     * @dev Function to cancel file transfer inititated by the current owner
     * @param _transfererEIN is the previous(current) owner EIN
     * @param _fileIndex is the index where file is stored
     * @param _transfereeEIN is the EIN of the user to whom the file needs to be transferred
     */
    function cancelFileTransfer(uint256 _transfererEIN, uint256 _fileIndex, uint256 _transfereeEIN) 
    public 
    _onlyOwner(_transfererEIN)
    _onlyEnforcedAtomityTransfers(_transfererEIN)
    _onlyEnforcedAtomityTransfers(_transfereeEIN) {
        // Set Transfers Atomiticy
        userAtomicity[_transfererEIN].lockTransfers = true;
        userAtomicity[_transfereeEIN].lockTransfers = true;
        
        // Check if the item is marked for transfer 
        require (
            (files[_transfererEIN][_fileIndex].markedForTransfer == true), 
            "Transfer Prohibited"
        );
        
        // Cancel file transfer
        files[_transfererEIN][_fileIndex].markedForTransfer = false;
        
        // Remove file from  transferee
        uint256 transferSpecificIndex = files[_transfererEIN][_fileIndex].transferIndex;
        _removeFileFromTransfereeMapping(_transfereeEIN, transferSpecificIndex);
        
        // Reset Transfers Atomiticy
        userAtomicity[_transfererEIN].lockTransfers = false;
        userAtomicity[_transfereeEIN].lockTransfers = false;
    }
    
    // 6. WHITELIST / BLACKLIST FUNCTIONS
    /**
     * @dev Add a non-owner user to whitelist
     * @param _nonOwnerEIN is the ein of the recipient
     */
    function addToWhitelist(uint256 _nonOwnerEIN) 
    public
    _onlyNonOwner(_nonOwnerEIN) 
    _onlyValidEIN(_nonOwnerEIN) {
        // Returns EIN or Throws Error if not set
        uint256 ein = identityRegistry.getEIN(msg.sender);
        
        //Check if user (EIN) is not on blacklist
        require (
            (blacklist[ein][_nonOwnerEIN] == false), 
            "EIN Blacklisted"
        );
        
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
    _onlyNonOwner(_nonOwnerEIN) 
    _onlyValidEIN(_nonOwnerEIN) {
        
        // Returns EIN or Throws Error if not set
        uint256 ein = identityRegistry.getEIN(msg.sender);
       
        //Check if user (EIN) is not on blacklist
        require (
            (blacklist[ein][_nonOwnerEIN] == false), 
            "EIN blacklisted"
        );
        
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
        require (
            (whitelist[ein][_nonOwnerEIN] == false), 
            "EIN whitelisted"
        );
        
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
    _onlyNonOwner(_nonOwnerEIN) 
    _onlyValidEIN(_nonOwnerEIN) {
        // Get EIN
        uint256 ein = identityRegistry.getEIN(msg.sender);
        
        //Check if user (EIN) is not on blacklist
        require (
            (whitelist[ein][_nonOwnerEIN] == false), 
            "EIN whitelisted"
        );
        
        whitelist[ein][_nonOwnerEIN] = false;
        
        // Trigger Event
        emit RemovedFromBlacklist(ein, _nonOwnerEIN);
    }
    
    // *. REFERENTIAL INDEXES FUNCTIONS
    /**
     * @dev Private Function to return maximum 20 Indexes of Files, Groups, Transfers, 
     * etc based on their SortOrder. 0 is always reserved but will point to Root in Group & Avatar in Files
     * @param _orderMapping is the relevant sort order of Files, Groups, Transfers, etc 
     * @param _seedPointer is the pointer (index) of the order mapping
     * @param _limit is the number of files requested | Maximum of 20 can be retrieved
     * @param _asc is the order, i.e. Ascending or Descending
     */
    function _getIndexes(mapping(uint256 => SortOrder) storage _orderMapping, uint256 _seedPointer, uint16 _limit, bool _asc)
    internal view 
    returns (uint256[20] memory sortedIndexes) {
        uint256 next;
        uint256 prev;
        uint256 pointerID;
        bool active;
        
        // Get initial Order
        (prev, next, pointerID, active) = _getOrder(_orderMapping, _seedPointer);
        
        // Get Previous or Next Order | Round Robin Fashion
        if (_asc == true) {
            // Ascending Order
            (prev, next, pointerID, active) = _getOrder(_orderMapping, next);
        }
        else {
            // Descending Order
            (prev, next, pointerID, active) = _getOrder(_orderMapping, prev);
        }
        
        uint16 i = 0;
        
        if (_limit >= 20) {
            _limit = 20; // always account for root
        }
        
        while (_limit != 0) {
            
            if (active == false || pointerID == 0) {
                _limit = 0;
                
                if (pointerID == 0) {
                    //add root as Special case
                    sortedIndexes[i] = 0;
                }
            }
            else {
                // Get PointerID
                sortedIndexes[i] = pointerID;
                
                // Get Previous or Next Order | Round Robin Fashion
                if (_asc == true) {
                    // Ascending Order
                    (prev, next, pointerID, active) = _getOrder(_orderMapping, next);
                }
                else {
                    // Descending Order
                    (prev, next, pointerID, active) = _getOrder(_orderMapping, prev);
                }
                
                // Increment counter
                i++;
                
                // Decrease Limit        
                _limit--;
            }
        }
    }
    
    // *. DOUBLE LINKED LIST (ROUND ROBIN) FOR OPTIMIZATION FUNCTIONS / DELETE / ADD / ETC
    /**
     * @dev Private Function to facilitate returning of double linked list used
     * @param _orderMapping is the relevant sort order of Files, Groups, Transfers, etc 
     * @param _seedPointer is the pointer (index) of the order mapping
     */
    function _getOrder(mapping(uint256 => SortOrder) storage _orderMapping, uint256 _seedPointer) 
    internal view 
    returns (uint256 prev, uint256 next, uint256 pointerID, bool active) {
        prev = _orderMapping[_seedPointer].prev;
        next = _orderMapping[_seedPointer].next;
        pointerID = _orderMapping[_seedPointer].pointerID;
        active = _orderMapping[_seedPointer].active;
    }
    
    /**
     * @dev Private Function to facilitate adding of double linked list used to preserve order and form cicular linked list
     * @param _orderMapping is the relevant sort order of Files, Groups, Transfers, etc 
     * @param _currentIndex is the index which will be maximum
     * @param _pointerID is the ID to which it should point to, pass 0 to calculate on existing logic flow
     */
    function _addToSortOrder(mapping(uint256 => SortOrder) storage _orderMapping, uint256 _currentIndex, uint256 _pointerID)  
    internal 
    returns (uint256) {
        // Next Index is always +1 
        uint256 nextIndex = _currentIndex + 1;
        
        require (
            (nextIndex > _currentIndex || _pointerID != 0),
            "Slots Full"
        );
        
        // Assign current order to next pointer
        _orderMapping[_currentIndex].next = nextIndex;
        _orderMapping[_currentIndex].active = true;
        
        // Special case of root of sort order 
        if (_currentIndex == 0) {
            _orderMapping[0].next = nextIndex;
        }
        
        // Assign initial group prev order
        _orderMapping[0].prev = nextIndex;
        
        // Whether This is assigned or calculated
        uint256 pointerID;
        if (_pointerID == 0) {
            pointerID = nextIndex;
        }
        else {
            pointerID = _pointerID;
        }
            
        // Assign next group order pointer and prev pointer
        _orderMapping[nextIndex] = SortOrder(
            0, // next index
            _currentIndex, // prev index
            pointerID, // pointerID
            true // mark as active
        );
        
        return nextIndex;
    }
    
    /**
     * @dev Private Function to facilitate stiching of double linked list used to preserve order with delete
     * @param _orderMapping is the relevant sort order of Files, Groups, Transfer, etc 
     * @param _remappedIndex is the index which is swapped to from the latest index
     * @param _maxIndex is the index which will always be maximum
     * @param _pointerID is the ID to which it should point to, pass 0 to calculate on existing logic flow
     */
    function _stichSortOrder(mapping(uint256 => SortOrder) storage _orderMapping, uint256 _remappedIndex, uint256 _maxIndex, uint256 _pointerID) 
    internal 
    returns (uint256){
        
        // Stich Order
        uint256 prevGroupIndex = _orderMapping[_remappedIndex].prev;
        uint256 nextGroupIndex = _orderMapping[_remappedIndex].next;
        
        _orderMapping[prevGroupIndex].next = nextGroupIndex;
        _orderMapping[nextGroupIndex].prev = prevGroupIndex;
        
        // Check if this is not the top order number
        if (_remappedIndex != _maxIndex) {
            // Change order mapping and remap
            _orderMapping[_remappedIndex] = _orderMapping[_maxIndex];
            if (_pointerID == 0) {
                _orderMapping[_remappedIndex].pointerID = _remappedIndex;
            }
            else {
                _orderMapping[_remappedIndex].pointerID = _pointerID;
            }
            _orderMapping[_orderMapping[_remappedIndex].next].prev = _remappedIndex;
            _orderMapping[_orderMapping[_remappedIndex].prev].next = _remappedIndex;
        }
        
        // Turn off the non-stich group
        _orderMapping[_maxIndex].active = false;
        
        // Decrement count index if it's non-zero
        require (
            (_maxIndex > 0),
            "Item Not Found"
        );
        
        // return new index
        return _maxIndex - 1;
    }
    
    // *. GENERAL CONTRACT HELPERS
    /** @dev Private Function to append two strings together
     * @param a the first string 
     * @param b the second string 
     */
    function _append(string memory a, string memory b) 
    internal pure 
    returns (string memory) {
        return string(abi.encodePacked(a, b));
    }
    
    /* ***************
    * DEFINE MODIFIERS
    *************** */
    /**
     * @dev Modifier to check that only owner can have access
     * @param _ein The EIN of the file Owner
     */
    modifier _onlyOwner(uint256 _ein) {  
        require (
            (identityRegistry.getEIN(msg.sender) == _ein), 
            "Only Owner"
        );
        _;
    }
    
    /**
     * @dev Modifier to check that only non-owner can have access
     * @param _ein The EIN of the file Owner
     */
    modifier _onlyNonOwner(uint256 _ein) {  
        require (
            (identityRegistry.getEIN(msg.sender) != _ein), 
            "Only Non-Owner"
        );
         _;
    }
    
    /**
     * @dev Modifier to check that only owner of EIN can access this
     * @param _ownerEIN The EIN of the file Owner
     * @param _fileIndex The index of the file
     */
    modifier _onlyFileOwner(uint256 _ownerEIN, uint256 _fileIndex) {
        require (
            (identityRegistry.getEIN(msg.sender) == files[_ownerEIN][_fileIndex].fileOwner), 
            "Only File Owner"
        );
         _;
    }
     
    /**
     * @dev Modifier to check that only non-owner of EIN can access this
     * @param _ownerEIN The EIN of the file Owner
     * @param _fileIndex The index of the file
     */
    modifier _onlyFileNonOwner(uint256 _ownerEIN, uint256 _fileIndex) { 
        require (
            (identityRegistry.getEIN(msg.sender) != files[_ownerEIN][_fileIndex].fileOwner), 
            "Only File Non-Owner"
        );
         _;
    }
    
    /**
     * @dev Modifier to check that only valid EINs can have access
     * @param _ein The EIN of the Passer
     */
    modifier _onlyValidEIN(uint256 _ein) {
        require (
            (identityRegistry.identityExists(_ein) == true), 
            "EIN not Found"
        );
        _;
    }
    
    /**
     * @dev Modifier to check that only unique EINs can have access
     * @param _ein1 The First EIN
     * @param _ein2 The Second EIN
     */
    modifier _onlyUniqueEIN(uint256 _ein1, uint256 _ein2) {
        require (
            (_ein1 != _ein2), 
            "Same EINs"
        );
        _;
    }
    
    /**
     * @dev Modifier to check that a file exists for the current EIN
     * @param _fileIndex The index of the file
     */
    modifier _onlyFileExists(uint256 _fileIndex) {
        require (
            (_fileIndex <= fileCount[identityRegistry.getEIN(msg.sender)]), 
            "File not Found"
        );
        _;
    }
    
    /**
     * @dev Modifier to check that a file has been marked for transferee EIN
     * @param _fileIndex The index of the file
     */
    modifier _onlyMarkedForTransferee(uint256 _fileOwnerEIN, uint256 _fileIndex, uint256 _transfereeEIN) {
        // Check if the group file exists or not
        require (
            (files[_fileOwnerEIN][_fileIndex].transferEIN == _transfereeEIN), 
            "File not marked for Transfers"
        );
        _;
    }
    
    /**
     * @dev Modifier to check that a file hasn't been marked for stamping
     * @param _fileIndex The index of the file
     */
    modifier _onlyUnlockedItem(uint256 _ein, uint256 _fileIndex) {
        // Get Item Association Index
        uint256 index1;
        uint256 index2;
        (, index1, index2) = getFileMetaData(_ein, _fileIndex);
        
        // Check if the group file exists or not
        require (
            (globalItems[index1][index2].isLocked == false), 
            "Item Locked"
        );
        _;
    }
    
    /**
     * @dev Modifier to check that Rooot ID = 0 is not modified as this is root
     * @param _index The index to check
     */
    modifier _onlyNonReservedItem(uint256 _index) {
        require (
            (_index > 0), 
            "Reserved Item"
        );
        _;
    }
    
    /**
     * @dev Modifier to check that Group Order is valid
     * @param _ein is the EIN of the target user
     * @param _groupIndex The index of the group order
     */
    modifier _onlyZeroFilesGroup(uint256 _ein, uint256 _groupIndex) {
        require (
            (groups[_ein][_groupIndex].groupFilesCount == 0),
            "Group has Files"
        );
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
            "Group Order Index not Found"
        );
        _;
    }
    
    /**
     * @dev Modifier to check that operation of Files is currently locked or not
     * @param _ein is the EIN of the target user
     */
    modifier _onlyEnforcedAtomityFiles(uint256 _ein) {
        require (
          (userAtomicity[_ein].lockFiles == false),
          "Files Locked"
        );
        _;
    }
    
    /**
     * @dev Modifier to check that operation of Groups is currently locked or not
     * @param _ein is the EIN of the target user
     */
    modifier _onlyEnforcedAtomityGroups(uint256 _ein) {
        require (
          (userAtomicity[_ein].lockGroups == false),
          "Groups Locked"
        );
        _;
    }
    
    /**
     * @dev Modifier to check that operation of Sharings is currently locked or not
     * @param _ein is the EIN of the target user
     */
    modifier _onlyEnforcedAtomitySharings(uint256 _ein) {
        require (
          (userAtomicity[_ein].lockSharings == false),
          "Sharing Locked"
        );
        _;
    }
    
    /**
     * @dev Modifier to check that operation of Transfers is currently locked or not
     * @param _ein is the EIN of the target user
     */
    modifier _onlyEnforcedAtomityTransfers(uint256 _ein) {
        require (
          (userAtomicity[_ein].lockTransfers == false),
          "Transfers Locked"
        );
        _;
    }
    
    // *. FOR DEBUGGING CONTRACT
    // To Build Groups for users
    function debugBuildGroups() 
    public {
        uint256 ein = identityRegistry.getEIN(msg.sender);
        
        createGroup(ein, "A");
        createGroup(ein, "B");
        createGroup(ein, "C");
        createGroup(ein, "D");
        createGroup(ein, "E");
        createGroup(ein, "F");
        createGroup(ein, "G");
        createGroup(ein, "H");
    }
    
    // Get Group Indexes with names for EIN
    function debugGetGroupIndexesWithNames(uint256 _ein, uint256 _seedPointer, uint16 _limit, bool _asc) 
    public view 
    returns (uint256[20] memory groupIndexes, string memory groupNames) {
        
        groupIndexes = _getIndexes(groupOrder[_ein], _seedPointer, _limit, _asc);
        
        uint16 i = 0;
        bool completed = false;
        
        while (completed == false) {
            string memory groupName;
            
            // Get Group
            (, groupName) = getGroup(_ein, groupIndexes[i]);
            
            // Add To Return Vars
            groupName = _append(groupName, "|");
            groupNames = _append(groupNames, groupName);
            
            i++;
            
            // check status
            if (i == _limit || (groupIndexes[i-1] == groupIndexes[i])) {
                completed = true;
            }
        }
    }
}





