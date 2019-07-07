pragma solidity ^0.5.1;

import "./interfaces/SnowflakeInterface.sol";
import "./interfaces/IdentityRegistryInterface.sol";

import "./IceFMS.sol";

/**
 * @title Ice Protocol
 * @author Harsh Rajat
 * @notice Create Protocol Less File Storage, Grouping, Hassle free Encryption / Decryption and Stamping using Snowflake
 * @dev This Contract forms File Storage / Stamping / Encryption part of Hydro Protocols
 */
contract Ice {
    using SafeMath for uint;
    
    using IceGlobal for IceGlobal.GlobalRecord;
    using IceGlobal for IceGlobal.ItemOwner;
    using IceGlobal for IceGlobal.Association;
    using IceGlobal for IceGlobal.UserMeta;
    using IceGlobal for mapping (uint => bool);
    using IceGlobal for mapping (uint8 => IceGlobal.ItemOwner);
    using IceGlobal for mapping (uint => mapping (uint => IceGlobal.Association));
    
    using IceSort for mapping(uint => IceSort.SortOrder);
    using IceSort for IceSort.SortOrder;
    
    using IceFMS for IceFMS.File;
    using IceFMS for mapping (uint => IceFMS.File);
    using IceFMS for IceFMS.Group;
    using IceFMS for uint;
    
    using IceFMSAdv for mapping (uint => IceGlobal.GlobalRecord);
    using IceFMSAdv for mapping (uint => mapping(uint => IceGlobal.GlobalRecord));
    
    /* ***************
    * DEFINE ENUM
    *************** */
    enum NoticeType {info, warning, error}
    
    /* ***************
    * DEFINE STRUCTURES
    *************** */
    // Done in Libraries
     
    /* ***************
    * DEFINE VARIABLES
    *************** */
    /* for each file stored, ensure they can be retrieved publicly.
     * associationIndex starts at 0 and will always increment
     * given an associationIndex, any file can be retrieved.
     */
    mapping (uint => mapping(uint => IceGlobal.Association)) globalItems;
    uint public globalIndex1; // store the first index of association to retrieve files
    uint public globalIndex2; // store the first index of association to retrieve files

    /* for each user (EIN), look up the Transitioon State they have
     * stored on a given index.
     */
    mapping (uint => IceGlobal.UserMeta) public usermeta;

    /* for each user (EIN), look up the file they have
     * stored on a given index.
     */
    mapping (uint => mapping(uint => IceFMS.File)) files;
    mapping (uint => mapping(uint => IceSort.SortOrder)) public fileOrder; // Store round robin order of files
    mapping (uint => uint) public fileCount; // store the maximum file count reached to provide looping functionality

    /* for each user (EIN), look up the group they have
     * stored on a given index. Default group 0 indicates
     * root folder
     */
    mapping (uint => mapping(uint => IceFMS.Group)) groups;
    mapping (uint => mapping(uint => IceSort.SortOrder)) public groupOrder; // Store round robin order of group
    mapping (uint => uint) public groupCount; // store the maximum group count reached to provide looping functionality

    /* for each user (EIN), look up the incoming transfer request
     * stored on a given index.
     */
    mapping (uint => mapping(uint => IceGlobal.Association)) transfers;
    mapping (uint => mapping(uint => IceSort.SortOrder)) public transferOrder; // Store round robin order of transfers
    mapping (uint => uint) public transferIndex; // store the maximum transfer request count reached to provide looping functionality

    /* for each user (EIN), look up the incoming sharing files
     * stored on a given index.
     */
    mapping (uint => mapping(uint => IceGlobal.GlobalRecord)) public shares;
    mapping (uint => mapping(uint => IceSort.SortOrder)) public shareOrder; // Store round robin order of sharing
    mapping (uint => uint) public shareCount; // store the maximum shared items count reached to provide looping functionality

    /* for each user (EIN), look up the incoming sharing files
     * stored on a given index.
     */
    mapping (uint => mapping(uint => IceGlobal.GlobalRecord)) public stampings;
    mapping (uint => mapping(uint => IceSort.SortOrder)) public stampingOrder; // Store round robin order of stamping
    mapping (uint => uint) public stampingCount; // store the maximum file index reached to provide looping functionality

    /* for each user (EIN), look up the incoming sharing files
     * stored on a given index.
     */
    mapping (uint => mapping(uint => IceGlobal.GlobalRecord)) public stampingsRequest;
    mapping (uint => mapping(uint => IceSort.SortOrder)) public stampingsRequestOrder; // Store round robin order of stamping requests
    mapping (uint => uint) public stampingsRequestCount; // store the maximum file index reached to provide looping functionality

    /* for each user (EIN), have a whitelist and blacklist
     * association which can handle certain functions automatically.
     */
    mapping (uint => mapping(uint => bool)) public whitelist;
    mapping (uint => mapping(uint => bool)) public blacklist;

    /* for referencing SnowFlake for Identity Registry (ERC-1484).
     */
    SnowflakeInterface public snowflake;
    IdentityRegistryInterface public identityRegistry;

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
    // CONSTRUCTOR / FUNCTIONS
    address snowflakeAddress = 0xcF1877AC788a303cAcbbfE21b4E8AD08139f54FA; //0xB536a9b68e7c1D2Fd6b9851Af2F955099B3A59a9; // For local use
    constructor (/*address snowflakeAddress*/) public {
        snowflake = SnowflakeInterface(snowflakeAddress);
        identityRegistry = IdentityRegistryInterface(snowflake.identityRegistryAddress());
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
    function getGlobalItems(uint _index1, uint _index2)
    external view
    returns (uint ownerEIN, uint itemRecord, bool isFile, bool isHidden, bool deleted, uint sharedToCount, uint stampingReqsCount) {
        ownerEIN = globalItems[_index1][_index2].ownerInfo.EIN;
        itemRecord = globalItems[_index1][_index2].ownerInfo.index;

        isFile = globalItems[_index1][_index2].isFile;
        isHidden = globalItems[_index1][_index2].isHidden;
        deleted = globalItems[_index1][_index2].deleted;

        sharedToCount = globalItems[_index1][_index2].sharedToCount;
        stampingReqsCount = globalItems[_index1][_index2].stampedToCount;
        
        //getGlobalItems
    }
    
    /**
     * @dev Function to get global items
     * @param _index1 is the first index of item
     * @param _index2 is the second index of item
     * @param _isHidden is the flag to hide that item or not 
     */
    function hideGlobalItem(uint _index1, uint _index2, bool _isHidden) 
    external {
        // Get user EIN
        uint ein = identityRegistry.getEIN(msg.sender);
        
        // Check Restrictions
        globalItems[_index1][_index2].condItemOwner(ein);
        
        // Logic
        globalItems[_index1][_index2].isHidden = _isHidden;
    }

    /**
     * @dev Function to get info of mapping to user for a specific global item
     * @param _index1 is the first index of global item
     * @param _index2 is the second index of global item
     * @param _ofType indicates the type. 0 - shares, 1 - transferReqs
     * @param _mappedIndex is the index
     * @return mappedToEIN is the user (EIN)
     * @return atIndex is the specific index in question
     */
    function getGlobalItemsMapping(uint _index1, uint _index2, uint8 _ofType, uint8 _mappedIndex)
    external view
    returns (uint mappedToEIN, uint atIndex) {
        IceGlobal.ItemOwner memory _mappedItem;

        // Allocalte based on type.
        if (_ofType == uint8(IceGlobal.AsscProp.sharedTo)) {
            _mappedItem = globalItems[_index1][_index2].sharedTo[_mappedIndex];
        }
        else if (_ofType == uint8(IceGlobal.AsscProp.stampedTo)) {
            _mappedItem = globalItems[_index1][_index2].stampedTo[_mappedIndex];
        }

        mappedToEIN = _mappedItem.EIN;
        atIndex = _mappedItem.index;
    }
    
    /**
     * @dev Private Function to reserve global item slot
     * @return i1 The reserved first index of global item
     * @return i2 The reserved second index of global item
     */
    function _reserveGlobalItemSlot() 
    internal 
    returns (uint i1, uint i2){
        // Increment global Item (0, 0 is always reserved | Is User Avatar)
        i1 = globalIndex1;
        i2 = globalIndex2;
        
        if ((i2 + 1) == 0) {
            // This is loopback, Increment newIndex1
            globalIndex1 = globalIndex1.add(1);
            globalIndex2 = 0;
        }
        else {
             globalIndex2 = globalIndex2 + 1;
        }
        
        i1 = globalIndex1;
        i2 = globalIndex2;
    }

    // 2. FILE FUNCTIONS
    /**
     * @dev Function to get all the files of an EIN
     * @param _ein is the owner EIN
     * @param _seedPointer is the seed of the order from which it should begin
     * @param _limit is the limit of file indexes requested
     * @param _asc is the order by which the files will be presented
     */
    function getFileIndexes(uint _ein, uint _seedPointer, uint16 _limit, bool _asc)
    external view
    returns (uint[20] memory fileIndexes) {
        fileIndexes = fileOrder[_ein].getIndexes(_seedPointer, _limit, _asc);
    }

    /**
     * @dev Function to get file info of an EIN
     * @param _ein is the owner EIN
     * @param _fileIndex is index of the file
     */
    function getFileInfo(uint _ein, uint _fileIndex)
    external view
    returns (uint8 protocol, bytes memory protocolMeta, string memory name, string memory hash1, string memory hash2, bool encrypted) {
        // Logic
        (protocol, protocolMeta, name, hash1, hash2, encrypted) = files[_ein][_fileIndex].getFileInfo();
    }
    
    /**
     * @dev Function to get file info of an EIN
     * @param _ein is the owner EIN
     * @param _fileIndex is index of the file
     */
    function getFileOtherInfo(uint _ein, uint _fileIndex)
    external view
    returns (uint32 timestamp, uint associatedGroupIndex, uint associatedGroupFileIndex) {
        // Logic
        (timestamp, associatedGroupIndex, associatedGroupFileIndex) = files[_ein][_fileIndex].getFileOtherInfo();
    }

    /**
     * @dev Function to get file tranfer info of an EIN
     * @param _ein is the owner EIN
     * @param _fileIndex is index of the file
     */
    function getFileTransferInfo(uint _ein, uint _fileIndex)
    external view
    returns (uint transCount, uint transEIN, uint transIndex, bool forTrans) {
        // Logic
        (transCount, transEIN, transIndex, forTrans) = files[_ein][_fileIndex].getFileTransferInfo();
    }

    /**
     * @dev Function to get file tranfer owner info of an EIN
     * @param _ein is the owner EIN
     * @param _fileIndex is index of the file
     * @param _transferIndex is index to poll
     */
    function getFileTransferOwners(uint _ein, uint _fileIndex, uint _transferIndex)
    external view
    returns (uint recipientEIN) {
        recipientEIN = files[_ein][_fileIndex].getFileTransferOwners(_transferIndex);
    }

    /**
     * @dev Function to add File
     * @param _protocol is the protocol used
     * @param _protocolMeta is the metadata used by the protocol if any
     * @param _name is the name of the file
     * @param _hash1 is the first split hash of the stored file
     * @param _hash2 is the second split hash of the stored file
     * @param _encrypted defines if the file is encrypted or not
     * @param _encryptedHash defines the encrypted public key password for the sender address
     * @param _groupIndex defines the index of the group of file
     */
    function addFile(uint8 _op, uint8 _protocol, bytes memory _protocolMeta, 
    bytes32 _name, bytes32 _hash1, bytes32 _hash2, 
    bool _encrypted, string memory _encryptedHash, uint _groupIndex)
    public {
        // Get user EIN
        uint ein = identityRegistry.getEIN(msg.sender);

        // Check constraints
        _groupIndex.condValidItem(groupCount[ein]);
        usermeta[ein].condFilesOpFree();
        usermeta[ein].condGroupsOpFree();
        
        // Set File & Group Atomicity
        usermeta[ein].lockFiles = true;
        usermeta[ein].lockGroups = true;

        // To fill with global index if need be
        uint i1;
        uint i2;
        
        // Create File
        uint nextIndex;
            
        // OP 0 - Normal | 1 - Avatar
        if (_op == 0) {
            // Reserve Global Index
            (i1, i2) = _reserveGlobalItemSlot();
        
            // Create File Next Index
            nextIndex = fileCount[ein] + 1;
        
            globalItems.addItemToGlobalItems(i1, i2, ein, nextIndex, true, false, false);
        }
        
        // Finally create the file it to User (EIN)
        files[ein][nextIndex].createFileObject(IceGlobal.GlobalRecord(i1, i2), _protocol, _protocolMeta, _name, _hash1, _hash2, _encrypted, _groupIndex, groups[ein][_groupIndex].groupFilesCount);
        
        // OP 0 - Normal | 1 - Avatar
        if (_op == 0) {
            fileCount[ein] = files[ein][nextIndex].writeFile(groups[ein][_groupIndex], _groupIndex, fileOrder[ein], fileCount[ein], nextIndex, ein, _encryptedHash);
        }
        else if (_op == 1) {
            usermeta[ein].hasAvatar = true;
        }
        
        // Trigger Event
        emit FileCreated(ein, (fileCount[ein] + 1), IceUtil.bytes32ToString(_name));

        // Reset Files & Group Atomicity
        usermeta[ein].lockFiles = false;
        usermeta[ein].lockGroups = false;
    }

    /**
     * @dev Function to change File Name
     * @param _fileIndex is the index where file is stored
     * @param _name is the name of stored file
     */
    function changeFileName(uint _fileIndex, bytes32 _name)
    external {
        // Get user EIN
        uint ein = identityRegistry.getEIN(msg.sender);

        // Logic
        files[ein][_fileIndex].name = _name;

        // Trigger Event
        emit FileRenamed(ein, _fileIndex, IceUtil.bytes32ToString(_name));
    }

    /**
     * @dev Function to move file to another group
     * @param _fileIndex is the index where file is stored
     * @param _newGroupIndex is the index of the new group where file has to be moved
     */
    function moveFileToGroup(uint _fileIndex, uint _newGroupIndex)
    external {
        // Get user EIN
        uint ein = identityRegistry.getEIN(msg.sender);

        // Logic
        uint GFIndex = files[ein][_fileIndex].moveFileToGroup(groups[ein], groupOrder[ein], _newGroupIndex, globalItems, usermeta[ein]);

        // Trigger Event
        emit FileMoved(ein, _fileIndex, _newGroupIndex, GFIndex);
    }

    /**
     * @dev Function to delete file of the owner
     * @param _fileIndex is the index where file is stored
     */
    function deleteFile(uint _fileIndex)
    external {
        // Get user EIN
        uint ein = identityRegistry.getEIN(msg.sender);

        // Delegate the call
        _deleteFileAnyOwner(ein, _fileIndex);
    }

    /**
     * @dev Function to delete file of any EIN
     * @param _ein is the owner EIN
     * @param _fileIndex is the index where file is stored
     */
    function _deleteFileAnyOwner(uint _ein, uint _fileIndex)
    internal {
        // Logic
        files[_ein].deleteFile(
            _ein, 
            _fileIndex, 
            fileOrder[_ein], 
            fileCount, 
            groups[_ein][files[_ein][_fileIndex].associatedGroupIndex], 
            groupOrder[_ein][files[_ein][_fileIndex].associatedGroupIndex],
            shares,
            shareOrder,
            shareCount,
            usermeta,
            globalItems
        );
        
        // Trigger Event
        emit FileDeleted(_ein, _fileIndex);
    }

    // 4. GROUP FILES FUNCTIONS
    /**
     * @dev Function to get all the files of an EIN associated with a group
     * @param _ein is the owner EIN
     * @param _groupIndex is the index where group is stored
     * @param _seedPointer is the seed of the order from which it should begin
     * @param _limit is the limit of file indexes requested
     * @param _asc is the order by which the files will be presented
     */
    function getGroupFileIndexes(uint _ein, uint _groupIndex, uint _seedPointer, uint16 _limit, bool _asc)
    external view
    returns (uint[20] memory groupFileIndexes) {
        return groups[_ein][_groupIndex].groupFilesOrder.getIndexes(_seedPointer, _limit, _asc);
    }

    // 3. GROUP FUNCTIONS
    /**
     * @dev Function to return group info for an EIN
     * @param _ein the EIN of the user
     * @param _groupIndex the index of the group
     * @return index is the index of the group
     * @return name is the name associated with the group
     */
    function getGroup(uint _ein, uint _groupIndex)
    external view
    returns (uint index, string memory name) {
        // Check constraints
        _groupIndex.condValidItem(groupCount[_ein]);

        // Logic flow
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
     * @param _seedPointer is the pointer (index) of the order mapping
     * @param _limit is the number of indexes to return, capped at 20
     * @param _asc is the order of group indexes in Ascending or Descending order
     * @return groupIndexes the indexes of the groups associated with the ein in the preferred order
     */
    function getGroupIndexes(uint _ein, uint _seedPointer, uint16 _limit, bool _asc)
    external view
    returns (uint[20] memory groupIndexes) {
        groupIndexes = groupOrder[_ein].getIndexes(_seedPointer, _limit, _asc);
    }

    /**
     * @dev Create a new Group for the user
     * @param _groupName describes the name of the group
     */
    function createGroup(string memory _groupName)
    public {
        // Get user EIN
        uint ein = identityRegistry.getEIN(msg.sender);
        
        // Check Restrictions
        usermeta[ein].condGroupsOpFree();

        // Set Group Atomicity
        usermeta[ein].lockGroups = true;

        // Reserve Global Index
        uint i1;
        uint i2;
        (i1, i2) = _reserveGlobalItemSlot();

        // Check if this is unitialized, if so, initialize it, reserved value of 0 is skipped as that's root
        uint currentGroupIndex = groupCount[ein];
        uint nextGroupIndex = currentGroupIndex + 1;
        
        // Add to Global Items as well
        globalItems.addItemToGlobalItems(i1, i2, ein, nextGroupIndex, false, false, false);
        
        // Assign it to User (EIN)
        groups[ein][nextGroupIndex] = IceFMS.Group(
            IceGlobal.GlobalRecord( // Add Record to struct
                i1,
                i2
            ),

            _groupName, //name of Group
            0 // The group file count
        );

        // Add to Stitch Order & Increment index
        groupCount[ein] = groupOrder[ein].addToSortOrder(currentGroupIndex, 0);

        // Trigger Event
        emit GroupCreated(ein, nextGroupIndex, _groupName);

        // Reset Group Atomicity
        usermeta[ein].lockGroups = false;
    }

    /**
     * @dev Rename an existing Group for the user / ein
     * @param _groupIndex describes the associated index of the group for the user / ein
     * @param _groupName describes the new name of the group
     */
    function renameGroup(uint _groupIndex, string calldata _groupName)
    external  {
        // Get user EIN
        uint ein = identityRegistry.getEIN(msg.sender);

        // Check Restrictions
        _isNonReservedItem(_groupIndex);
        _groupIndex.condValidItem(groupCount[ein]);

        // Replace the group name
        groups[ein][_groupIndex].name = _groupName;

        // Trigger Event
        emit GroupRenamed(ein, _groupIndex, _groupName);
    }

    /**
     * @dev Delete an existing group for the user / ein
     * @param _groupIndex describes the associated index of the group for the user / ein
     */
    function deleteGroup(uint _groupIndex)
    external {
        // Get user EIN
        uint ein = identityRegistry.getEIN(msg.sender);

        // Check Restrictions
        _isGroupFileFree(ein, _groupIndex); // Check that Group contains no Files
        _isNonReservedItem(_groupIndex);
        _groupIndex.condValidItem(groupCount[ein]);
        usermeta[ein].condGroupsOpFree();

        // Set Group Atomicity
        usermeta[ein].lockGroups = true;

        // Check if the group exists or not
        uint currentGroupIndex = groupCount[ein];

        // Remove item from sharing of other users
        IceGlobal.Association storage globalItem = groups[ein][_groupIndex].rec.getGlobalItemViaRecord(globalItems);
        shares.removeAllShares(globalItem, shareOrder, shareCount, usermeta, ein);
        
        // Deactivate from global record
        globalItem.deleteGlobalRecord();

        // Swap Index mapping & remap the latest group ID if this is not the last group
        groups[ein][_groupIndex] = groups[ein][currentGroupIndex];
        groupCount[ein] = groupOrder[ein].stichSortOrder(_groupIndex, currentGroupIndex, 0);

        // Delete the latest group now
        delete (groups[ein][currentGroupIndex]);

        // Trigger Event
        emit GroupDeleted(ein, _groupIndex, currentGroupIndex);

        // Reset Group Atomicity
        usermeta[ein].lockGroups = false;
    }

    // 4. SHARING FUNCTIONS
    /**
     * @dev Function to share an item to other users, always called by owner of the Item
     * @param _toEINs are the array of EINs which the item should be shared to
     * @param _itemIndex is the index of the item to be shared to
     * @param _isFile indicates if the item is file or group
     */
    function shareItemToEINs(uint[] calldata _toEINs, uint _itemIndex, bool _isFile)
    external {
        // Get user EIN
        uint ein = identityRegistry.getEIN(msg.sender);
        
        // Check if item is file or group and accordingly check if Item is valid & Logic
        if (_isFile == true) { 
            _itemIndex.condValidItem(fileCount[ein]);
            shares.shareItemToEINs(globalItems, shareOrder, shareCount, usermeta, blacklist, files[ein][_itemIndex].rec, ein, _toEINs);
        }
        else {
            _itemIndex.condValidItem(groupCount[ein]);
            shares.shareItemToEINs(globalItems, shareOrder, shareCount, usermeta, blacklist, groups[ein][_itemIndex].rec, ein, _toEINs);
        }
    }

    /**
     * @dev Function to remove a shared item from the multiple user's mapping, always called by owner of the Item
     * @param _fromEINs are the EINs to which the item should be removed from sharing
     * @param _itemIndex is the index of the item on the owner's mapping
     * @param _isFile indicates if the item is file or group 
     */
    function removeShareFromEINs(uint[32] memory _fromEINs, uint _itemIndex, bool _isFile)
    public {
        // Get user EIN
        uint ein = identityRegistry.getEIN(msg.sender);

        // Check if item is file or group and accordingly check if Item is valid & Logic
        IceGlobal.GlobalRecord memory rec;
        if (_isFile == true) { 
            _itemIndex.condValidItem(fileCount[ein]);
            rec = files[ein][_itemIndex].rec;
        }
        else {
            _itemIndex.condValidItem(groupCount[ein]);
            rec = files[ein][_itemIndex].rec;
        }
        
        shares.removeShareFromEINs(globalItems[rec.i1][rec.i2], shareOrder, shareCount, usermeta, ein, _fromEINs);
    }
    
    
    /**
     * @dev Function to remove shared item by the user to whom the item is shared
     * @param _itemIndex is the index of the item in shares
     */
    function removeSharingItemBySharee(uint _itemIndex) 
    external {
        // Logic
        uint shareeEIN = identityRegistry.getEIN(msg.sender);
        IceGlobal.Association storage globalItem = shares[shareeEIN][_itemIndex].getGlobalItemViaRecord(globalItems);
        
        shares[shareeEIN].removeSharingItemBySharee(globalItem, shareOrder[shareeEIN], shareCount, usermeta[shareeEIN], shareeEIN);
    }
    
    // 5. STAMPING FUNCTIONS
    
    // 6. TRANSFER FILE FUNCTIONS
    /**
     * @dev Function to intiate file transfer to another EIN(user)
     * @param _fileIndex is the index of file for the original user's EIN
     * @param _transfereeEIN is the recipient user's EIN
     */
    // function initiateFileTransfer(uint _fileIndex, uint _transfereeEIN)
    // external {
    //     // Get user EIN
    //     uint ein = identityRegistry.getEIN(msg.sender);

    //     // Check Restrictions
    //     _isValidEIN(_transfereeEIN); // Check Valid EIN
    //     _isUnqEIN(ein, _transfereeEIN); // Check EINs and Unique
    //     _isUnstampedItem(files[ein][_fileIndex].rec); // Check if the File is not stamped
    //     _isUnstampedItem(groups[ein][files[ein][_fileIndex].associatedGroupIndex].rec); // Check if the Group is not stamped
    //     blacklist[_transfereeEIN].condNotInList(ein); // Check if The transfee hasn't blacklisted the file owner
    //     usermeta[ein].condTransfersOpFree(); // Check if Transfers are not locked for current user
    //     usermeta[_transfereeEIN].condTransfersOpFree(); // Check if the transfers are not locked for recipient user

    //     // Set Transfers Atomiticy
    //     usermeta[ein].lockTransfers = true;
    //     usermeta[_transfereeEIN].lockTransfers = true;

    //     // Check and change flow if white listed
    //     if (whitelist[_transfereeEIN][ein] == true) {
    //         // Directly transfer file, 0 is always root group
    //         _doFileTransfer(ein, _fileIndex, _transfereeEIN, 0);
    //     }
    //     else {
    //       // Request based file Transfers
    //       _initiateRequestedFileTransfer(ein, _fileIndex, _transfereeEIN);
    //     }

    //     // Reset Transfers Atomiticy
    //     usermeta[ein].lockTransfers = false;
    //     usermeta[_transfereeEIN].lockTransfers = false;
    // }

    // /**
    //  * @dev Function to accept file transfer from a user
    //  * @param _transfererEIN is the previous(current) owner EIN
    //  * @param _fileIndex is the index where file is stored
    //  * @param _transferSpecificIndex is the file mapping stored no the recipient transfers mapping
    //  * @param _groupIndex is the index of the group where the file is suppose to be for the recipient
    //  */
    // function acceptFileTransfer(uint _transfererEIN, uint _fileIndex, uint _transferSpecificIndex, uint _groupIndex)
    // external {
    //     // Get user EIN | Transferee initiates this
    //     uint ein = identityRegistry.getEIN(msg.sender);

    //     // Check Restrictions
    //     _isMarkedForTransferee(_transfererEIN, _fileIndex, ein); // Check if the file is marked for transfer to the recipient
    //     usermeta[_transfererEIN].condTransfersOpFree(); // Check that the transfers are not locked for the sender of the file
    //     usermeta[ein].condTransfersOpFree(); // Check that the transfers are not locked for the recipient of the file

    //     // Set Transfers Atomiticy
    //     usermeta[_transfererEIN].lockTransfers = true;
    //     usermeta[ein].lockTransfers = true;

    //     // Check if the item is marked for transfer
    //     require (
    //         (files[_transfererEIN][_fileIndex].markedForTransfer == true),
    //         "Can't proceed, item is not marked for Transfer."
    //     );

    //     // Do file transfer
    //     _doFileTransfer(_transfererEIN, _fileIndex, ein, _groupIndex);

    //     // Finally remove the file from Tranferee Mapping
    //     _removeFileFromTransfereeMapping(ein, _transferSpecificIndex);

    //     // Reset Transfers Atomiticy
    //     usermeta[_transfererEIN].lockTransfers = false;
    //     usermeta[ein].lockTransfers = false;
    // }

    // /**
    //  * @dev Function to cancel file transfer inititated by the current owner
    //  * @param _fileIndex is the index where file is stored
    //  * @param _transfereeEIN is the EIN of the user to whom the file needs to be transferred
    //  */
    // function cancelFileTransfer(uint _fileIndex, uint _transfereeEIN)
    // external {
    //     // Get user EIN | Transferee initiates this
    //     uint ein = identityRegistry.getEIN(msg.sender);

    //     // Check Restrictions
    //     usermeta[_transfereeEIN].condTransfersOpFree(); 
    //     usermeta[ein].condTransfersOpFree();

    //     // Set Transfers Atomiticy
    //     usermeta[ein].lockTransfers = true;
    //     usermeta[_transfereeEIN].lockTransfers = true;

    //     // Check if the item is marked for transfer
    //     require (
    //         (files[ein][_fileIndex].markedForTransfer == true),
    //         "Transfer Prohibited"
    //     );

    //     // Cancel file transfer
    //     files[ein][_fileIndex].markedForTransfer = false;

    //     // Remove file from  transferee
    //     uint transferSpecificIndex = files[ein][_fileIndex].transferIndex;
    //     _removeFileFromTransfereeMapping(_transfereeEIN, transferSpecificIndex);

    //     // Reset Transfers Atomiticy
    //     usermeta[ein].lockTransfers = false;
    //     usermeta[_transfereeEIN].lockTransfers = false;
    // }
    
    // /**
    //  * @dev Private Function to initiate requested file transfer
    //  * @param _transfererEIN is the owner EIN
    //  * @param _fileIndex is the index where file is stored
    //  * @param _transfereeEIN is the EIN of the user to whom the file needs to be transferred
    //  */
    // function _initiateRequestedFileTransfer(uint _transfererEIN, uint _fileIndex, uint _transfereeEIN)
    // internal {
    //      // Map it to transferee mapping of transfers
    //     // Add to transfers of TransfereeEIN User, 0 is always reserved
    //     uint currentTransferIndex = transferIndex[_transfereeEIN];
    //     uint nextTransferIndex = currentTransferIndex + 1;

    //     require (
    //         (nextTransferIndex > currentTransferIndex),
    //         "Limit reached on number of transfers, can't transfer more files to that EIN (User) till they clear it up."
    //     );

    //     // Mark the file for transfer
    //     files[_transfererEIN][_fileIndex].markedForTransfer = true;
    //     files[_transfererEIN][_fileIndex].transferEIN = _transfereeEIN;
    //     files[_transfereeEIN][_fileIndex].transferIndex = nextTransferIndex;

    //     // Get Item Association Index
    //     uint index1;
    //     uint index2;
    //     (index1, index2) = files[_transfererEIN][_fileIndex].rec.getGlobalItemViaRecord();

    //     // Check Item is file
    //     require (
    //         (globalItems[index1][index2].isFile == true),
    //         "Non-Transferable"
    //     );

    //     // Create New Transfer
    //     transfers[_transfereeEIN][nextTransferIndex] = globalItems[index1][index2];

    //     // Update sort order and index
    //     transferIndex[_transfereeEIN] = transferOrder[_transfererEIN].addToSortOrder(currentTransferIndex, 0);

    //     // Trigger Event
    //     emit FileTransferInitiated(_transfererEIN, _transfereeEIN, _fileIndex);
    // }
    
    // /**
    //  * @dev Private Function to do file transfer from previous (current) owner to new owner
    //  * @param _transfererEIN is the previous(current) owner EIN
    //  * @param _fileIndex is the index where file is stored
    //  * @param _transfereeEIN is the EIN of the user to whom the file needs to be transferred
    //  * @param _groupIndex is the index of the group where the file is suppose to be for the recipient
    //  */
    // function _doFileTransfer(uint _transfererEIN, uint _fileIndex, uint _transfereeEIN, uint _groupIndex)
    // internal {
    //     // Get Indexes
    //     uint currentTransfererIndex = fileCount[_transfererEIN];
    //     uint currentTransfereeIndex = fileCount[_transfereeEIN];

    //     uint prevTransfererIndex = currentTransfererIndex - 1;
    //     require (
    //         (prevTransfererIndex >= 0),
    //         "No file found in the transferer db"
    //     );

    //     uint nextTransfereeIndex =  currentTransfereeIndex + 1;
    //     require (
    //         (nextTransfereeIndex > currentTransfereeIndex),
    //         "Trasnferee User has run out of transfer slots."
    //     );

    //     // Transfer the file to the transferee & Delete it for transferer
    //     files[_transfereeEIN][nextTransfereeIndex] = files[_transfererEIN][_fileIndex];
    //     _deleteFileAnyOwner(_transfererEIN, _fileIndex);

    //     // Change file properties and transfer history
    //     uint8 tc = files[_transfereeEIN][nextTransfereeIndex].transferCount;
    //     tc = tc + 1;
    //     require (
    //         (tc > 0),
    //         "Transfers Full"
    //     );

    //     files[_transfereeEIN][nextTransfereeIndex].transferHistory[tc] = _transfereeEIN;
    //     files[_transfereeEIN][nextTransfereeIndex].markedForTransfer = false;
    //     files[_transfereeEIN][nextTransfereeIndex].transferCount = tc;

    //     // add to transferee sort order & Increment index
    //     fileCount[_transfereeEIN] = fileOrder[_transfereeEIN].addToSortOrder(currentTransfereeIndex, 0);

    //     // Add File to transferee group
    //     groups[_transfereeEIN][_groupIndex].addFileToGroup(_groupIndex, fileCount[_transfereeEIN]);

    //     // Get global association
    //     uint index1;
    //     uint index2;
    //     (index1, index2) = files[_transfereeEIN][_fileIndex].rec.getGlobalItemViaRecord();

    //     // Update global file association
    //     globalItems[index1][index2].ownerInfo.EIN = _transfereeEIN;
    //     globalItems[index1][index2].ownerInfo.index = nextTransfereeIndex;
    // }

    // /**
    //  * @dev Private Function to remove file from Transfers mapping of Transferee after file is transferred to them
    //  * @param _transfereeEIN is the new owner EIN
    //  * @param _transferSpecificIndex is the index of the association mapping of transfers
    //  */
    // function _removeFileFromTransfereeMapping(uint _transfereeEIN, uint _transferSpecificIndex)
    // internal {
    //     // Get Cureent Transfer Index
    //     uint currentTransferIndex = transferIndex[_transfereeEIN];

    //     require (
    //         (currentTransferIndex > 0),
    //         "Index Not Found"
    //     );

    //     // Remove the file from transferer, ie swap mapping and stich sort order
    //     transfers[_transfereeEIN][_transferSpecificIndex] = transfers[_transfereeEIN][currentTransferIndex];
    //     transferIndex[_transfereeEIN] = transferOrder[_transfereeEIN].stichSortOrder(_transferSpecificIndex, currentTransferIndex, 0);

    //     // Retrive the swapped item record and change the transferIndex to remap correctly
    //     IceGlobal.Association memory item = transfers[_transfereeEIN][_transferSpecificIndex];

    //     if (item.isFile == true) {
    //         //Only File is supported
    //         files[item.ownerInfo.EIN][item.ownerInfo.index].transferIndex = _transferSpecificIndex;
    //     }
    // }

    // // 7. WHITELIST / BLACKLIST FUNCTIONS
    /**
     * @dev Add a non-owner user to whitelist
     * @param _nonOwnerEIN is the ein of the recipient
     */
    function addToWhitelist(uint _nonOwnerEIN)
    external {
        // Logic
        uint ein = identityRegistry.getEIN(msg.sender);
        whitelist[ein].addToWhitelist(_nonOwnerEIN, blacklist[ein]);

        // Trigger Event
        emit AddedToWhitelist(ein, _nonOwnerEIN);
    }

    /**
     * @dev Remove a non-owner user from whitelist
     * @param _nonOwnerEIN is the ein of the recipient
     */
    function removeFromWhitelist(uint _nonOwnerEIN)
    external {
        // Logic
        uint ein = identityRegistry.getEIN(msg.sender);
        whitelist[ein].removeFromWhitelist(_nonOwnerEIN, blacklist[ein]);

        // Trigger Event
        emit RemovedFromWhitelist(ein, _nonOwnerEIN);
    }

    /**
     * @dev Remove a non-owner user to blacklist
     * @param _nonOwnerEIN is the ein of the recipient
     */
    function addToBlacklist(uint _nonOwnerEIN)
    external {
        // Logic
        uint ein = identityRegistry.getEIN(msg.sender);
        blacklist[ein].addToBlacklist(_nonOwnerEIN, whitelist[ein]);

        // Trigger Event
        emit AddedToBlacklist(ein, _nonOwnerEIN);
    }

    /**
     * @dev Remove a non-owner user from blacklist
     * @param _nonOwnerEIN is the ein of the recipient
     */
    function removeFromBlacklist(uint _nonOwnerEIN)
    external {
        // Logic
        uint ein = identityRegistry.getEIN(msg.sender);
        blacklist[ein].removeFromBlacklist(_nonOwnerEIN, whitelist[ein]);

        // Trigger Event
        emit RemovedFromBlacklist(ein, _nonOwnerEIN);
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
    * DEFINE MODIFIERS AS INTERNAL VIEW FUNTIONS
    *************** */
    /**
     * @dev Private Function to check that only owner can have access
     * @param _ein The EIN of the file Owner
     */
    function _isOwner(uint _ein)
    internal view {
        require (
            (identityRegistry.getEIN(msg.sender) == _ein),
            "Only Owner"
        );
    }

    /**
     * @dev Private Function to check that only non-owner can have access
     * @param _ein The EIN of the file Owner
     */
    function _isNonOwner(uint _ein)
    internal view {
        require (
            (identityRegistry.getEIN(msg.sender) != _ein),
            "Only Non-Owner"
        );
    }

    /**
     * @dev Private Function to check that only valid EINs can have access
     * @param _ein The EIN of the Passer
     */
    function _isValidEIN(uint _ein)
    internal view {
        require (
            (identityRegistry.identityExists(_ein) == true),
            "EIN not Found"
        );
    }

    /**
     * @dev Private Function to check that only unique EINs can have access
     * @param _ein1 The First EIN
     * @param _ein2 The Second EIN
     */
    function _isUnqEIN(uint _ein1, uint _ein2)
    internal pure {
        require (
            (_ein1 != _ein2),
            "Same EINs"
        );
    }
    
    /**
     * @dev Private Function to check that a file has been marked for transferee EIN
     * @param _fileIndex The index of the file
     */
    function _isMarkedForTransferee(uint _fileOwnerEIN, uint _fileIndex, uint _transfereeEIN)
    internal view {
        // Check if the group file exists or not
        require (
            (files[_fileOwnerEIN][_fileIndex].transferEIN == _transfereeEIN),
            "File not marked for Transfers"
        );
    }

    /**
     * @dev Private Function to check that Rooot ID = 0 is not modified as this is root
     * @param _index The index to check
     */
    function _isNonReservedItem(uint _index)
    internal pure {
        require (
            (_index > 0),
            "Reserved Item"
        );
    }

    /**
     * @dev Private Function to check that Group Order is valid
     * @param _ein is the EIN of the target user
     * @param _groupIndex The index of the group order
     */
    function _isGroupFileFree(uint _ein, uint _groupIndex)
    internal view {
        require (
            (groups[_ein][_groupIndex].groupFilesCount == 0),
            "Group has Files"
        );
    }

    // *. FOR DEBUGGING CONTRACT
    // To Build Groups & File System for users
    function debugBuildFS()
    public {
        // createGroup("A.Images");
        // createGroup("B.Movies");
        // createGroup("C.Crypto");
        // createGroup("D.Others");
        // createGroup("E.AdobeContract");

        // // Create Files
        // // addFile(_op, _protocol, _protocolMeta, _name,  _hash1, _hash2, _encrypted, _encryptedHash, _groupIndex)
        // addFile(0, 1, bytes("0x00"), IceUtil.stringToBytes32("index"), IceUtil.stringToBytes32("QmTecWfmvvsPdZXuYrLgCTqRj9YgBiAU"), IceUtil.stringToBytes32("L4ZCr9iwDnp9q7"), false, "", 0);
        // addFile(0, 1, bytes("0x00"), IceUtil.stringToBytes32("family"), IceUtil.stringToBytes32("QmTecWfmvvsPdZXuYrLgCTqRj9YgBiAU"), IceUtil.stringToBytes32("L4ZCr9iwDnp9q7"), false, "", 0);
        // addFile(0, 1, bytes("0x00"), IceUtil.stringToBytes32("myportrait"), IceUtil.stringToBytes32("QmTecWfmvvsPdZXuYrLgCTqRj9YgBiAU"), IceUtil.stringToBytes32("L4ZCr9iwDnp9q7"), false, "", 0);
        // addFile(0, 1, bytes("0x00"), IceUtil.stringToBytes32("cutepic"), IceUtil.stringToBytes32("QmTecWfmvvsPdZXuYrLgCTqRj9YgBiAU"), IceUtil.stringToBytes32("L4ZCr9iwDnp9q7"), false, "", 0);
        // addFile(0, 1, bytes("0x00"), IceUtil.stringToBytes32("awesome"), IceUtil.stringToBytes32("QmTecWfmvvsPdZXuYrLgCTqRj9YgBiAU"), IceUtil.stringToBytes32("L4ZCr9iwDnp9q7"), false, "", 0);
    }

    // Get Indexes with Names for EIN
    // _for = 1 is Files, 2 is GroupFiles, 3 is Groups
    function debugIndexesWithNames(uint _ein, uint _groupIndex, uint _seedPointer, uint16 _limit, bool _asc, uint8 _for)
    external view
    returns (uint[20] memory _indexes, string memory _names) {

        if (_for == 1) {
            _indexes = fileOrder[_ein].getIndexes(_seedPointer, _limit, _asc);
        }
        else if (_for == 2) {
            _indexes = groups[_ein][_groupIndex].groupFilesOrder.getIndexes(_seedPointer, _limit, _asc);
        }
        else if (_for == 3) {
            _indexes = groupOrder[_ein].getIndexes(_seedPointer, _limit, _asc);
        }
        else if (_for == 4) {
            _indexes = shareOrder[_ein].getIndexes(_seedPointer, _limit, _asc);
        }

        uint16 i = 0;
        bool completed = false;

        while (completed == false) {
            string memory name;

            // Get Name
            if (_for == 1 || _for == 2) {
                name = IceUtil.bytes32ToString(files[_ein][_indexes[i]].name);
            }
            else if (_for == 3) {
                name = groups[_ein][_indexes[i]].name;
            }
            else if (_for == 4) {
                IceGlobal.GlobalRecord memory record = shares[_ein][_indexes[i]];
                IceGlobal.ItemOwner memory owner = globalItems[record.i1][record.i2].ownerInfo;
                
                if (globalItems[record.i1][record.i2].isFile == true) {
                    name = IceUtil.bytes32ToString(files[owner.EIN][owner.index].name);
                } 
                else {
                    name = groups[owner.EIN][owner.index].name;
                }
            }

            // Add To Return Vars
            name = _append(name, "|");
            _names = _append(_names, name);

            i++;

            // check status
            if (i == _limit || (_indexes[i-1] == _indexes[i])) {
                completed = true;
            }
        }
    }
}
