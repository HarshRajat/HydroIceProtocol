pragma solidity ^0.5.1;

import "./SnowflakeInterface.sol";
import "./IdentityRegistryInterface.sol";

import "./SafeMath.sol";

import "./IceGlobal.sol";
import "./IceSort.sol";

import "./IceFMSAdv.sol";

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
    using IceFMS for mapping (uint => mapping (uint => IceFMS.File));
    using IceFMS for IceFMS.Group;
    using IceFMS for mapping (uint => IceFMS.Group);
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
    /* for each item stored, ensure they can be retrieved publicly.
     * globalIndex1 and globalIndex2 starts at 0 and will always increment
     * given these indexes, any items can be retrieved.
     */
    mapping (uint => mapping(uint => IceGlobal.Association)) globalItems;
    uint public globalIndex1; // store the first index of association to retrieve files
    uint public globalIndex2; // store the second index of association to retrieve files

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
    mapping (uint => mapping(uint => IceGlobal.GlobalRecord)) public transfers;
    mapping (uint => mapping(uint => IceSort.SortOrder)) public transferOrder; // Store round robin order of transfers
    mapping (uint => uint) public transferCount; // store the maximum transfer request count reached to provide looping functionality

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
    // When Item is hidden 
    event ItemHidden(uint EIN, uint fileIndex, bool status);
    
    // When Item is Shared
    event ItemShareChange(uint EIN, uint fileIndex);
    
    // When File is created
    event FileCreated(uint EIN, uint fileIndex, string fileName);

    // When File is renamed
    event FileRenamed(uint EIN, uint fileIndex, string fileName);

    // When File is moved
    event FileMoved(uint EIN, uint fileIndex, uint groupIndex, uint groupFileIndex);

    // When File is deleted
    event FileDeleted(uint EIN, uint fileIndex);

    // When Group is created
    event GroupCreated(uint EIN, uint groupIndex, string groupName);

    // When Group is renamed
    event GroupRenamed(uint EIN, uint groupIndex, string groupName);

    // When Group Status is changed
    event GroupDeleted(uint EIN, uint groupIndex, uint groupReplacedIndex);

    // When Transfer is initiated from owner
    event FileTransferInitiated(uint indexed EIN, uint indexed transfereeEIN, uint indexed fileID);

    // When whitelist is updated
    event AddedToWhitelist(uint EIN, uint recipientEIN);
    event RemovedFromWhitelist(uint EIN, uint recipientEIN);

    // When blacklist is updated
    event AddedToBlacklist(uint EIN, uint recipientEIN);
    event RemovedFromBlacklist(uint EIN, uint recipientEIN);

    /* ***************
    * DEFINE CONSTRUCTORS AND RELATED FUNCTIONS
    *************** */
    // CONSTRUCTOR / FUNCTIONS
    address snowflakeAddress = 0xC155f98Fa02AeED743a2658a4B076701376a27ee; //0xcF1877AC788a303cAcbbfE21b4E8AD08139f54FA; // For local use
    //address snowflakeAddress = 0xB0D5a36733886a4c5597849a05B315626aF5222E; //0xB0D5a36733886a4c5597849a05B315626aF5222E; // For rinkeby
    
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
     * @return ownerEIN is the EIN of the user who owns the item
     * itemRecord is the record of that item in relation to the individual user
     * isFile indicates if the item is file or group
     * isHidden indicates if the item is hidder or visible
     * deleted indicates if the item is already deleted from the individual user perspective
     * sharedToCount is the count of sharing the item has
     * pendingStampingCount is the count of pending stamping requests
     */
    function getGlobalItems(
        uint _index1, 
        uint _index2
    )
    external view
    returns (
        uint ownerEIN, 
        uint itemRecord, 
        bool isFile, 
        bool isHidden, 
        bool deleted, 
        uint8 sharedToCount, 
        uint8 pendingStampingCount
    ) {
        ownerEIN = globalItems[_index1][_index2].ownerInfo.EIN;
        itemRecord = globalItems[_index1][_index2].ownerInfo.index;

        isFile = globalItems[_index1][_index2].isFile;
        isHidden = globalItems[_index1][_index2].isHidden;
        deleted = globalItems[_index1][_index2].deleted;

        sharedToCount = globalItems[_index1][_index2].sharedToCount;
        pendingStampingCount = globalItems[_index1][_index2].stampedToCount;
    }
    
    /**
     * @dev Function to get global items
     * @param _index1 is the first index of item
     * @param _index2 is the second index of item
     * @param _isHidden is the flag to hide that item or not 
     */
    function hideGlobalItem(
        uint _index1, 
        uint _index2, 
        bool _isHidden
    ) 
    external {
        // Get user EIN
        uint ein = identityRegistry.getEIN(msg.sender);
        
        // Check Restrictions
        globalItems[_index1][_index2].condItemOwner(ein);
        
        // Logic
        globalItems[_index1][_index2].isHidden = _isHidden;
        
        // Trigger Event
        emit ItemHidden(ein, globalItems[_index1][_index2].ownerInfo.EIN, _isHidden); 
    }

    /**
     * @dev Function to get info of mapping to user for a specific global item
     * @param _index1 is the first index of global item
     * @param _index2 is the second index of global item
     * @param _ofType indicates the type. 0 - shares, 1 - stampings
     * @param _mappedIndex is the index
     * @return mappedToEIN is the user (EIN)
     * @return atIndex is the specific index in question
     */
    function getGlobalItemsMapping(
        uint _index1, 
        uint _index2, 
        uint8 _ofType, 
        uint8 _mappedIndex
    )
    external view
    returns (
        uint mappedToEIN, 
        uint atIndex
    ) {
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
    
    // 2. FILE FUNCTIONS
    /**
     * @dev Function to get the desired amount of files indexes (max 20 at times) of an EIN, the 0 indicates 
     * @param _ein is the EIN of the user
     * @param _seedPointer is the seed of the order from which it should begin
     * @param _limit is the limit of file indexes requested
     * @param _asc is the order by which the files will be presented
     * @return fileIndexes is the array of file indexes for the specified users
     */
    function getFileIndexes(
        uint _ein, 
        uint _seedPointer,
        uint16 _limit, 
        bool _asc
    )
    external view
    returns (uint[20] memory fileIndexes) {
        fileIndexes = fileOrder[_ein].getIndexes(_seedPointer, _limit, _asc);
    }

    /**
     * @dev Function to get file info of an EIN
     * @param _ein is the owner EIN
     * @param _fileIndex is index of the file
     * @return protocol is the protocol used for storing that file (for example: 1 is IPFS, etc, etc). Used to fetch file from JS Library
     * @return protocolMeta contains the additional essential infomation about the protocol if any
     * @return name is the name of the file along with the extension
     * @return hash1 is the 
     * 
     */
    function getFileInfo(
        uint _ein, 
        uint _fileIndex
    )
    external view 
    returns (
        uint8 protocol, 
        bytes memory protocolMeta, 
        string memory fileName, 
        bytes32 fileHash, 
        bytes22 hashExtraInfo,
        uint8 hashFunction,
        uint8 hashSize,
        bool encryptedStatus
    ) {
        // Logic
        (protocol, protocolMeta, fileName, fileHash, hashExtraInfo, hashFunction, hashSize, encryptedStatus) = files[_ein][_fileIndex].getFileInfo();
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
     * @param _transferCount is index to poll
     */
    function getFileTransferOwners(uint _ein, uint _fileIndex, uint _transferCount)
    external view
    returns (uint recipientEIN) {
        recipientEIN = files[_ein][_fileIndex].getFileTransferOwners(_transferCount);
    }

    // /**
    //  * @dev Function to add File
    //  * @param _protocol is the protocol used
    //  * @param _protocolMeta is the metadata used by the protocol if any
    //  * @param _name is the name of the file
    //  * @param _hash1 is the first split hash of the stored file
    //  * @param _hash2 is the second split hash of the stored file
    //  * @param _encrypted defines if the file is encrypted or not
    //  * @param _encryptedHash defines the encrypted public key password for the sender address
    //  * @param _groupIndex defines the index of the group of file
    //  */
    function addFile(
        uint8 _op, 
        uint8 _protocol, 
        bytes memory _protocolMeta, 
        bytes32 _name, 
        bytes32 _hash,
        bytes22 _hashExtraInfo,
        uint8 _hashFunction,
        uint8 _hashSize,
        bool _encrypted, 
        bytes32 _encryptedHash, 
        uint _groupIndex
    )
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
        IceGlobal.GlobalRecord memory rec;
        
        // Create File
        uint nextIndex;
            
        // OP 0 - Normal | 1 - Avatar
        if (_op == 0) {
            // Reserve Global Index
            (globalIndex1, globalIndex2) = IceGlobal.reserveGlobalItemSlot(globalIndex1, globalIndex2);
        
            // Create the record
            rec = IceGlobal.GlobalRecord(globalIndex1, globalIndex2);
        
            // Create File Next Index
            nextIndex = fileCount[ein] + 1;
            
            // Add to globalItems
            globalItems.addItemToGlobalItems(rec.i1, rec.i2, ein, nextIndex, true, false, false);
        }
        
        // Finally create the file object (EIN)
        files[ein][nextIndex].createFileObject(
            _protocolMeta,
            
            _groupIndex, 
            groups[ein][_groupIndex].groupFilesCount
        );
        
        // Assign global item record 
        files[ein][nextIndex].rec = rec;
        
        // Also create meta object
        files[ein][nextIndex].createFileMetaObject(
            _protocol,
            _name,
            _hash,
            _hashExtraInfo,
            _hashFunction,
            _hashSize,
            _encrypted
        );
        
        // OP 0 - Normal | 1 - Avatar
        if (_op == 0) {
            fileCount[ein] = files[ein][nextIndex].writeFile(
                groups[ein][_groupIndex], 
                _groupIndex, 
                fileOrder[ein], 
                fileCount[ein], 
                nextIndex, 
                ein, 
                _encryptedHash
            );
        }
        else if (_op == 1) {
            usermeta[ein].hasAvatar = true;
        }
        
        // Trigger Event
        emit FileCreated(ein, nextIndex, IceFMS.bytes32ToString(_name));

        // Reset Files & Group Atomicity
        usermeta[ein].lockFiles = false;
        usermeta[ein].lockGroups = false;
    }

    // /**
    //  * @dev Function to change File Name
    //  * @param _fileIndex is the index where file is stored
    //  * @param _name is the name of stored file
    //  */
    function changeFileName(
        uint _fileIndex, 
        bytes32 _name
    )
    external {
        // Get user EIN
        uint ein = identityRegistry.getEIN(msg.sender);

        // Logic
        files[ein][_fileIndex].fileMeta.name = _name;

        // Trigger Event
        emit FileRenamed(ein, _fileIndex, IceFMS.bytes32ToString(_name));
    }

    // /**
    //  * @dev Function to move file to another group
    //  * @param _fileIndex is the index where file is stored
    //  * @param _newGroupIndex is the index of the new group where file has to be moved
    //  */
    function moveFileToGroup(
        uint _fileIndex, 
        uint _newGroupIndex
    )
    external {
        // Get user EIN
        uint ein = identityRegistry.getEIN(msg.sender);

        // Logic
        uint groupFileIndex = files[ein][_fileIndex].moveFileToGroup(_fileIndex, groups[ein], groupOrder[ein], _newGroupIndex, globalItems, usermeta[ein]);

        // Trigger Event
        emit FileMoved(ein, _fileIndex, _newGroupIndex, groupFileIndex);
    }

    // /**
    //  * @dev Function to delete file of the owner
    //  * @param _fileIndex is the index where file is stored
    //  */
    function deleteFile(uint _fileIndex)
    external {
        // Get user EIN
        uint ein = identityRegistry.getEIN(msg.sender);

        // Delegate the call
        _deleteFileAnyOwner(ein, _fileIndex);
        
        // Trigger Event
        emit FileDeleted(ein, _fileIndex);
    }

    // /**
    //  * @dev Function to delete file of any EIN
    //  * @param _ein is the owner EIN
    //  * @param _fileIndex is the index where file is stored
    //  */
    function _deleteFileAnyOwner(
        uint _ein, 
        uint _fileIndex
    )
    internal {
        // Logic
        files[_ein].deleteFile(
            _ein,
            _fileIndex,
            files[_ein][_fileIndex].rec.getGlobalItemViaRecord(globalItems),
            
            fileOrder[_ein],
            fileCount,
            groups[_ein][files[_ein][_fileIndex].associatedGroupIndex],
            groupOrder[_ein][files[_ein][_fileIndex].associatedGroupIndex],
            
            shares,
            shareOrder,
            shareCount,
            
            usermeta
        );
    }

    // 3. GROUP FILES FUNCTIONS
    /**
     * @dev Function to get all the files of an EIN associated with a group
     * @param _ein is the owner EIN
     * @param _groupIndex is the index where group is stored
     * @param _seedPointer is the seed of the order from which it should begin
     * @param _limit is the limit of file indexes requested
     * @param _asc is the order by which the files will be presented
     */
    function getGroupFileIndexes(
        uint _ein, 
        uint _groupIndex, 
        uint _seedPointer, 
        uint16 _limit, 
        bool _asc
    )
    external view
    returns (uint[20] memory groupFileIndexes) {
        return groups[_ein][_groupIndex].groupFilesOrder.getIndexes(_seedPointer, _limit, _asc);
    }

    // 4. GROUP FUNCTIONS
    /**
     * @dev Function to return group info for an EIN
     * @param _ein the EIN of the user
     * @param _groupIndex the index of the group
     * @return index is the index of the group
     * @return name is the name associated with the group
     */
    function getGroup(
        uint _ein, 
        uint _groupIndex
    )
    external view
    returns (
        uint index, 
        string memory name
    ) {
        // Logic
        (index, name) = groups[_ein][_groupIndex].getGroup(_groupIndex, groupCount[_ein]);
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
     * @dev Function to create a new Group for the user
     * @param _groupName describes the name of the group
     */
    function createGroup(string memory _groupName)
    public {
        // Get user EIN
        uint ein = identityRegistry.getEIN(msg.sender);
        
        // Logic
        uint nextGroupIndex;
        (globalIndex1, globalIndex2, nextGroupIndex) = groups[ein].createGroup(
            ein, 
            _groupName, 
            groupOrder[ein], 
            groupCount, 
            globalItems,
            globalIndex1,
            globalIndex2,
            usermeta[ein]
        );
        
        // Trigger Event
        emit GroupCreated(ein, nextGroupIndex, _groupName);
    }

    /**
     * @dev Function to rename an existing Group for the user / ein
     * @param _groupIndex describes the associated index of the group for the user / ein
     * @param _groupName describes the new name of the group
     */
    function renameGroup(
        uint _groupIndex, 
        string calldata _groupName
    )
    external  {
        // Get user EIN
        uint ein = identityRegistry.getEIN(msg.sender);

        // Logic
        groups[ein][_groupIndex].renameGroup(_groupIndex, groupCount[ein], _groupName);
        
        // Trigger Event
        emit GroupRenamed(ein, _groupIndex, _groupName);
    }

    /**
     * @dev Function to delete an existing group for the user / ein
     * @param _groupIndex describes the associated index of the group for the user / ein
     */
    function deleteGroup(uint _groupIndex)
    external {
        // Get user EIN
        uint ein = identityRegistry.getEIN(msg.sender);

        // Logic
        uint currentGroupIndex = groups[ein].deleteGroup(
            ein,
            
            _groupIndex,
            groupOrder[ein], 
            groupCount, 
            
            shares,
            shareOrder,
            shareCount,
            
            globalItems,
            usermeta
        );
        
        // Trigger Event
        emit GroupDeleted(ein, _groupIndex, currentGroupIndex);
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
    function removeShareFromEINs(
        uint[] memory _fromEINs, 
        uint _itemIndex, 
        bool _isFile
    )
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
            rec = groups[ein][_itemIndex].rec;
        }
        
        shares.removeShareFromEINs(
            ein, 
            _fromEINs,
            globalItems[rec.i1][rec.i2], 
            shareOrder, 
            shareCount, 
            usermeta
        );
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
        
        shares[shareeEIN].removeSharingItemBySharee( 
            shareeEIN,
            globalItem, 
            shareOrder[shareeEIN], 
            shareCount, 
            usermeta[shareeEIN]
        );
    }
    
    // 5. STAMPING FUNCTIONS
    //function initiateStampingOfItem
    
    // 6. TRANSFER FILE FUNCTIONS
    /**
     * @dev Function to intiate file transfer to another EIN(user)
     * @param _fileIndex is the index of file for the original user's EIN
     * @param _transfereeEIN is the recipient user's EIN
     */
    function initiateFileTransfer(
        uint _fileIndex, 
        uint _transfereeEIN
    )
    external {
        // Get user EIN
        uint transfererEIN = identityRegistry.getEIN(msg.sender);
        
        // Check Restrictions
        IceFMS.doInitiateFileTransferChecks(
            files,
            
            transfererEIN,
            _transfereeEIN,
            _fileIndex,
            
            fileCount,
            groups,
            blacklist,
            
            globalItems,
            usermeta,
            
            identityRegistry
        );
        
        // Set Transfers Atomiticy
        usermeta[transfererEIN].lockTransfers = true;
        usermeta[_transfereeEIN].lockTransfers = true;

        // Check and change flow if white listed
        if (whitelist[_transfereeEIN][transfererEIN] == true) {
            // Directly transfer file, 0 is always root group
            _doDirectFileTransfer(transfererEIN, _transfereeEIN, _fileIndex, 0);
        }
        else {
            // Request based file Transfers
            files[transfererEIN][_fileIndex].doPermissionedFileTransfer(
                _transfereeEIN,
                
                transfers[_transfereeEIN],
                transferOrder[_transfereeEIN],
                transferCount,
                
                globalItems
            );
            
            // Trigger Event
            emit FileTransferInitiated(transfererEIN, _transfereeEIN, _fileIndex);
        }

        // Reset Transfers Atomiticy
        usermeta[transfererEIN].lockTransfers = false;
        usermeta[_transfereeEIN].lockTransfers = false;
    }
    
    /**
     * @dev Private Function to do file transfer from previous (current) owner to new owner
     * @param _transfererEIN is the previous(current) owner EIN
     * @param _transfereeEIN is the EIN of the user to whom the file needs to be transferred
     * @param _fileIndex is the index where file is stored in the owner
     * @param _toRecipientGroup is the index of the group where the file is suppose to be for the recipient
     */
    function _doDirectFileTransfer(
        uint _transfererEIN, 
        uint _transfereeEIN, 
        uint _fileIndex, 
        uint _toRecipientGroup
    )
    internal {
         // Set Transfers Atomiticy
        usermeta[_transfererEIN].lockTransfers = true;
        usermeta[_transfereeEIN].lockTransfers = true;

        // Logic
        uint nextTransfereeIndex = files.doFileTransferPart1 (
            _transfererEIN,
            _transfereeEIN,
            _fileIndex,
            
            fileOrder,
            fileCount
        );
        
        files.doFileTransferPart2 (
            _transfereeEIN, 
            _fileIndex, 
            _toRecipientGroup,
            groupCount[_transfereeEIN],
            nextTransfereeIndex,
            
            groups,
            globalItems
        );

        // Delete File
        _deleteFileAnyOwner(_transfererEIN, _fileIndex);

        // Reset Transfers Atomiticy
        usermeta[_transfererEIN].lockTransfers = false;
        usermeta[_transfereeEIN].lockTransfers = false;
    }
    
    /**
     * @dev Function to accept file transfer from a user
     * @param _atRecipientTransferIndex is the file mapping stored no the recipient transfers mapping
     * @param _toRecipientGroup is the index of the group where the file is suppose to be for the recipient
     */
    function acceptFileTransfer(
        uint _atRecipientTransferIndex,
        uint _toRecipientGroup
    )
    external {
        // Get user EIN | Transferee initiates this
        uint transfereeEIN = identityRegistry.getEIN(msg.sender);
        
        // Get owner info
        IceGlobal.ItemOwner memory ownerInfo = transfers[transfereeEIN][_atRecipientTransferIndex].getGlobalItemViaRecord(globalItems).ownerInfo;
        
        uint transfererEIN = ownerInfo.EIN;
        uint fileIndex = ownerInfo.index;
        
        // Accept File Transfer Part 1
        files.acceptFileTransferPart1(
            transfererEIN, 
            transfereeEIN,
            fileIndex,
            
            usermeta
        );
        
        // Do file transfer
        _doDirectFileTransfer(transfererEIN, transfereeEIN, fileIndex, _toRecipientGroup);
        
        // Accept File Transfer Part 2
        files.acceptFileTransferPart2(
            transfererEIN, 
            transfereeEIN,
            
            _atRecipientTransferIndex,
        
            transfers[transfereeEIN],
            transferOrder[transfereeEIN],
            transferCount,
            
            globalItems,
            usermeta
        );
    }

    /**
     * @dev Function to revoke file transfer inititated by the current owner of that file
     * @param _transfereeEIN is the EIN of the user to whom the file needs to be transferred
     * @param _fileIndex is the index where file is stored
     */
    function revokeFileTransfer(
        uint _transfereeEIN,
        uint _fileIndex
    )
    external {
        // Get user EIN | Transferer initiates this
        uint transfererEIN = identityRegistry.getEIN(msg.sender);

        // Logic
        files.cancelFileTransfer(
            transfererEIN,
            _transfereeEIN,
            _fileIndex,
            
            transfers[_transfereeEIN],
            transferOrder[_transfereeEIN],
            transferCount,
            
            globalItems,
            
            usermeta[transfererEIN],
            usermeta[transfererEIN]
        );
    }
    
    /**
     * @dev Function to revoke file transfer inititated by the current owner of that file
     * @param _atRecipientTransferIndex is the file mapping stored no the recipient transfers mapping
     */
    function rejectFileTransfer(
        uint _atRecipientTransferIndex
    )
    external 
    returns (
        uint, uint
    ){
        // Get user EIN | Transferee initiates this
        uint transfereeEIN = identityRegistry.getEIN(msg.sender);
        
        // Get owner info
        IceGlobal.ItemOwner memory ownerInfo = transfers[transfereeEIN][_atRecipientTransferIndex].getGlobalItemViaRecord(globalItems).ownerInfo;
        
        uint transfererEIN = ownerInfo.EIN;
        uint fileIndex = ownerInfo.index;
        
        // Logic
        files.cancelFileTransfer(
            transfererEIN,
            transfereeEIN,
            fileIndex,
            
            transfers[transfereeEIN],
            transferOrder[transfereeEIN],
            transferCount,
            
            globalItems,
            
            usermeta[transfererEIN],
            usermeta[transfererEIN]
        );
    }
    
    // 7. WHITELIST / BLACKLIST FUNCTIONS
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

    // *. FOR DEBUGGING CONTRACT
    // To Build Groups & File System for users
    function debugBuildFS()
    public {
        createGroup("A.Images");
        createGroup("B.Movies");
        createGroup("C.Crypto");
        createGroup("D.Others");
        createGroup("E.AdobeContract");

        // Create Files
        // addFile(_op, _protocol, _protocolMeta, _name, _hash, _hashExtraInfo, _hashFunction, _hashSize, _encrypted, _encryptedHash, _groupIndex)
        addFile(0, 1, bytes("0x00"), IceFMS.stringToBytes32("index.jpg"), IceFMS.stringToBytes32("QmTecWfmvvsPdZXuYrLgCTqRj9YgBiAU332s"), bytes22("0x00"), 2, 3, false, "", 0);
        addFile(0, 1, bytes("0x00"), IceFMS.stringToBytes32("family.pdf"), IceFMS.stringToBytes32("QmTecWfmvvsPdZXuYrLgCTqRj9YgBiAU332sL4ZCr9iwDnp9q7"), bytes22("0x00"), 2, 3, false, "", 0);
        addFile(0, 1, bytes("0x00"), IceFMS.stringToBytes32("myportrait.jpg"), IceFMS.stringToBytes32("L4ZCr9iwDnp9q7QmTecWfmvvsPdZXuYrLgCTqRj9YgBiAU332s"), bytes22("0x00"), 2, 3, false, "", 0);
        addFile(0, 1, bytes("0x00"), IceFMS.stringToBytes32("index.html"), IceFMS.stringToBytes32("9iwDnp9q7QmTecWfmvvsPdZXuYrLgCTqRj9YgBiAU332sL4ZCr"), bytes22("0x00"), 2, 3, false, "", 1);
        addFile(0, 1, bytes("0x00"), IceFMS.stringToBytes32("skills.txt"), IceFMS.stringToBytes32("qRj9YgBiAU332sQmTecWfmvvsPdZXuYrLgCT"), bytes22("0x00"), 2, 3, false, "", 2);
  }

    // Get Indexes with Names for EIN
    // _for = 1 is Files, 2 is GroupFiles, 3 is Groups, 4 is shares
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
                name = IceFMS.bytes32ToString(files[_ein][_indexes[i]].fileMeta.name);
            }
            else if (_for == 3) {
                name = groups[_ein][_indexes[i]].name;
            }
            else if (_for == 4) {
                IceGlobal.GlobalRecord memory record = shares[_ein][_indexes[i]];
                IceGlobal.ItemOwner memory owner = globalItems[record.i1][record.i2].ownerInfo;
                
                if (globalItems[record.i1][record.i2].isFile == true) {
                    name = IceFMS.bytes32ToString(files[owner.EIN][owner.index].fileMeta.name);
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
