pragma solidity ^0.5.1;

import "./SafeMath.sol";

import "./IceGlobal.sol";
import "./IceSort.sol";

import "./IceFMSAdv.sol";

/**
 * @title Ice Protocol Files / Groups / Users Meta Management System Libray
 * @author Harsh Rajat
 * @notice Create sorting order for maximizing space utilization
 * @dev This Library is part of many that Ice uses form a robust File Management System
 */
library IceFMS {
    using SafeMath for uint;
    
    using IceGlobal for IceGlobal.GlobalRecord;
    using IceGlobal for IceGlobal.Association;
    using IceGlobal for IceGlobal.UserMeta;
    using IceGlobal for mapping (uint8 => IceGlobal.ItemOwner);
    using IceGlobal for mapping (uint => mapping (uint => IceGlobal.Association));
    
    using IceSort for mapping (uint => IceSort.SortOrder);
    using IceSort for IceSort.SortOrder;
    
    using IceFMSAdv for mapping (uint => mapping(uint => IceGlobal.GlobalRecord));
    
    
    /* ***************
    * DEFINE STRUCTURES
    *************** */
    /* To define the multihash function for storing of hash */
    struct FileMeta {
        bytes32 name; // to store the name of the file
        
        bytes32 hash; // to store the hash of file
        bytes22 hashExtraInfo; // to store any extra info if required
        
        bool encrypted; // whether the file is encrypted
        bool markedForTransfer; // Mark the file as transferred
        
        uint8 protocol; // store protocol of the file stored | 0 is URL, 1 is IPFS
        uint8 transferCount; // To maintain the transfer count for mapping
        
        uint8 hashFunction; // Store the hash of the file for verification | 0x000 for deleted files
        uint8 hashSize; // Store the length of the digest
        
        uint32 timestamp;  // to store the timestamp of the block when file is created
    }
    
    /* To define File structure of all stored files */
    struct File {
        // File Meta Data
        IceGlobal.GlobalRecord rec; // store the association in global record

        // File Properties
        bytes protocolMeta; // store metadata of the protocol
        FileMeta fileMeta; // store metadata associated with file

        // File Properties - Encryption Properties
        mapping (address => bytes32) encryptedHash; // Maps Individual address to the stored hash

        // File Other Properties
        uint associatedGroupIndex; // to store the group index of the group that holds the file
        uint associatedGroupFileIndex; // to store the mapping of file in the specific group order
        uint transferEIN; // To record EIN of the user to whom trasnfer is inititated
        uint transferIndex; // To record the transfer specific index of the transferee

        // File Transfer Properties
        mapping (uint => uint) transferHistory; // To maintain histroy of transfer of all EIN
    }

    /* To connect Files in linear grouping,
     * sort of like a folder, 0 or default grooupID is root
     */
    struct Group {
        IceGlobal.GlobalRecord rec; // store the association in global record

        string name; // the name of the Group

        mapping (uint => IceSort.SortOrder) groupFilesOrder; // the order of files in the current group
        uint groupFilesCount; // To keep the count of group files
    }
     
    /* ***************
    * DEFINE FUNCTIONS
    *************** */
    // 1. FILE FUNCTIONS
    /**
     * @dev Function to get file info of an EIN
     * @param self is the pointer to the File Struct (IceFMS Library) passed
     * @return protocol returns the protocol used for storage of the file (0 - URL, 1 - IPFS)
     * @return protocolMeta returns the meta info associated with a protocol
     * @return fileName is the name of the file
     * @return fileHash is the Hash of the file
     * @return hashExtraInfo is extra info stored as part of the protocol used 
     * @return hashFunction is the function used to store that hash
     * @return hashSize is the size of the digest
     * @return encryptedStatus indicates if the file is encrypted or not 
     */
    function getFileInfo(File storage self)
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
        protocol = self.fileMeta.protocol; // Protocol
        protocolMeta = self.protocolMeta; // Protocol meta
        
        fileName = bytes32ToString(self.fileMeta.name); // File Name, convert from byte32 to string
        
        fileHash = self.fileMeta.hash; // hash of the file
        hashExtraInfo = self.fileMeta.hashExtraInfo; // extra info of hash of the file (to utilize 22 bytes of wasted space)
        hashFunction = self.fileMeta.hashFunction; // the hash function used to store the file
        hashSize = self.fileMeta.hashSize; // The length of the digest
        
        encryptedStatus = self.fileMeta.encrypted; // Whether the file is encrypted or not
    }
    
    /**
     * @dev Function to get file info of an EIN
     * @param self is the pointer to the File Struct (IceFMS Library) passed
     * @return timestamp indicates the timestamp of the file
     * @return associatedGroupIndex indicates the group which the file is associated to in the user's FMS
     * @return associatedGroupFileIndex indicates the file index within the group of the user's FMS
     */
    function getFileOtherInfo(File storage self)
    external view
    returns (
        uint32 timestamp, 
        uint associatedGroupIndex, 
        uint associatedGroupFileIndex
    ) {
        // Logic
        timestamp = self.fileMeta.timestamp;
        associatedGroupIndex = self.associatedGroupIndex;
        associatedGroupFileIndex = self.associatedGroupFileIndex;
    }

    /**
     * @dev Function to get file tranfer info of an EIN
     * @param self is the pointer to the File Struct (IceFMS Library) passed
     * @return transferCount indicates the number of times the file has been transferred
     * @return transferEIN indicates the EIN of the user to which the file is currently scheduled for transfer
     * @return transferIndex indicates the transfer index of the target EIN where the file is currently mapped to
     * @return markedForTransfer indicates if the file is marked for transfer or not
     */
    function getFileTransferInfo(File storage self)
    external view
    returns (
        uint transferCount, 
        uint transferEIN, 
        uint transferIndex, 
        bool markedForTransfer
    ) {
        // Logic
        transferCount = self.fileMeta.transferCount; 
        transferEIN = self.transferEIN; 
        transferIndex = self.transferIndex; 
        markedForTransfer = self.fileMeta.markedForTransfer;
    }

    /**
     * @dev Function to get file tranfer owner info of an EIN
     * @param self is the pointer to the File Struct (IceFMS Library) passed
     * @param _transferIndex is index to poll which is useful to get the history of transfers and to what EIN the file previously belonged to
     * @return previousOwnerEIN is the EIN of the user who had originally owned that file
     */
    function getFileTransferOwners(
        File storage self, 
        uint _transferIndex
    )
    external view
    returns (uint previousOwnerEIN) {
        previousOwnerEIN = self.transferHistory[_transferIndex];    // Return transfer history associated with a particular transfer index
    }
    
    /**
     * @dev Function to create a basic File Object for a given file
     * @param self is the pointer to the File Struct (IceFMS Library) passed
     * @param _protocolMeta is the meta info which is stored for a certain protocol
     * @return _groupIndex is the index of the group where the file is stored
     * @return _groupFilesCount is the number of files stored in that group 
     */
    function createFileObject(
        File storage self,
        bytes calldata _protocolMeta,
        uint _groupIndex, 
        uint _groupFilesCount
    )
    external {
        // Set other File info
        self.protocolMeta = _protocolMeta;
        
        self.associatedGroupIndex = _groupIndex;
        self.associatedGroupFileIndex = _groupFilesCount;
    }
    
    /**
     * @dev Function to create a File Meta Object and attach it to File Struct (IceFMS Library)
     * @param self is the pointer to the File Struct (IceFMS Library) passed
     * @param _protocol is type of protocol used to store that file (0 - URL, 1- IPFS)
     * @param _name is the name of the file with the extension
     * @param _hash is the hash of the file (useful for IPFS and to verify authenticity)
     * @param _hashExtraInfo is the extra info which can be stored in a 22 byte format (if required)
     * @param _hashFunction is the function used to generate the hash
     * @param _hashSize is the size of the digest
     * @param _encrypted indicates if the file is encrypted or not  
     */
    function createFileMetaObject(
        File storage self,
        uint8 _protocol,
        bytes32 _name, 
        bytes32 _hash,
        bytes22 _hashExtraInfo,
        uint8 _hashFunction,
        uint8 _hashSize,
        bool _encrypted
    )
    external {
        //set file meta
        self.fileMeta = FileMeta(
            _name,                  // to store the name of the file
            
            _hash,                  // to store the hash of file
            _hashExtraInfo,         // to store any extra info if required
            
            _encrypted,             // whether the file is encrypted
            false,                  // Mark the file as transferred, defaults to false
                
            _protocol,              // store protocol of the file stored | 0 is URL, 1 is IPFS
            1,                      // Default transfer count is 1
            
            _hashFunction,          // Store the hash of the file for verification | 0x000 for deleted files
            _hashSize,              // Store the length of the digest
            
            uint32(now)             // to store the timestamp of the block when file is created
        );
    }
    
    /**
     * @dev Function to write file to a user FMS
     * @param self is the pointer to the File Struct (IceFMS Library) passed
     * @param group is the pointer to the group where the file is going to be stored for the primary user (EIN)
     * @param _groupIndex indicates the index of the group for the EIN's FMS
     * @param _userFileOrderMapping is the mapping of the user's file order using SortOrder Struct (IceSort Library)
     * @param _maxFileIndex indicates the maximum index of the files stored for the primary user (EIN)
     * @param _nextIndex indicates the next index which will store the particular file in question
     * @param _transferEin is the EIN of the user for which the file is getting written to, defaults to primary user
     * @param _encryptedHash is the encrypted hash stored incase the file is encrypted
     */
    function writeFile(
        File storage self, 
        Group storage group, 
        uint _groupIndex, 
        mapping(uint => IceSort.SortOrder) storage _userFileOrderMapping, 
        uint _maxFileIndex, 
        uint _nextIndex, 
        uint _transferEin, 
        bytes32 _encryptedHash
    ) 
    internal 
    returns (uint newFileCount) {
        // Add file to group 
        (self.associatedGroupIndex, self.associatedGroupFileIndex) = addFileToGroup(group, _groupIndex, _nextIndex);
        
        // To map encrypted password
        self.encryptedHash[msg.sender] = _encryptedHash;

        // To map transfer history
        self.transferHistory[0] = _transferEin;

        // Add to Stitch Order & Increment index
        newFileCount = _userFileOrderMapping.addToSortOrder(_userFileOrderMapping[0].prev, _maxFileIndex, 0);
    }
    
    /**
     * @dev Function to move file to another group
     * @param _newGroupIndex is the index of the new group where file has to be moved
     */
    function moveFileToGroup(
        File storage self, 
        uint _fileIndex,
        mapping(uint => IceFMS.Group) storage _groupMapping, 
        mapping(uint => IceSort.SortOrder) storage _groupOrderMapping,
        uint _newGroupIndex,
        mapping (uint => mapping(uint => IceGlobal.Association)) storage _globalItems,
        IceGlobal.UserMeta storage _specificUserMeta
    )
    external 
    returns (uint groupFileIndex){
        // Check Restrictions
        _groupOrderMapping[_newGroupIndex].condValidSortOrder(_newGroupIndex); // Check if the new group is valid
        self.rec.getGlobalItemViaRecord(_globalItems).condUnstampedItem(); // Check if the file is unstamped, can't move a stamped file
        
        // Check if the current group is unstamped, can't move a file from stamped group
        _groupMapping[self.associatedGroupIndex].rec.getGlobalItemViaRecord(_globalItems).condUnstampedItem(); 
        
        // Check if the new group is unstamped, can't move a file from stamped group
        _groupMapping[_newGroupIndex].rec.getGlobalItemViaRecord(_globalItems).condUnstampedItem(); 
        
        _specificUserMeta.condFilesOpFree(); // Check if the files operations are not locked for the user
        _specificUserMeta.condGroupsOpFree(); // Check if the groups operations are not locked for the user

        // Set Files & Group Atomicity
        _specificUserMeta.lockFiles = true;
        _specificUserMeta.lockGroups = true;

        // get file existing index in the user FMS Mapping
        //uint fileIndex = self.rec.getGlobalItemViaRecord(_globalItems).ownerInfo.index;
        
        // remap the file
        groupFileIndex = remapFileToGroup(
            self, 
            _fileIndex,
            _groupMapping[self.associatedGroupIndex], 
            _groupMapping[_newGroupIndex], 
            _newGroupIndex
        );

        // Reset Files & Group Atomicity
        _specificUserMeta.lockFiles = false;
        _specificUserMeta.lockGroups = false;
    }

    /**
     * @dev Function to delete file of the owner
     * @param _fileIndex is the index where file is stored
     */
    function deleteFile(
        mapping (uint => File) storage self,
        uint _ein,
        uint _fileIndex,
        mapping (uint => IceSort.SortOrder) storage _fileOrder,
        mapping (uint => uint) storage _fileCount,
        Group storage _group,
        IceSort.SortOrder storage _groupOrder,
        mapping (uint => mapping(uint => IceGlobal.GlobalRecord)) storage _shares,
        mapping (uint => mapping(uint => IceSort.SortOrder)) storage _shareOrder, 
        mapping (uint => uint) storage _shareCount,
        mapping (uint => IceGlobal.UserMeta) storage _usermeta,
        mapping (uint => mapping(uint => IceGlobal.Association)) storage _globalItems
    )
    external {
        // // Check Restrictions
        self[_fileIndex].rec.getGlobalItemViaRecord(_globalItems).condUnstampedItem(); // Check if the file is unstamped, can't delete a stamped file

        // // Set Files & Group Atomicity
        _usermeta[_ein].lockFiles = true;
        _usermeta[_ein].lockGroups = true;

        // // Check Restrictions
        condValidItem(_fileIndex, _fileCount[_ein]);
        _groupOrder.condValidSortOrder(self[_fileIndex].associatedGroupIndex);

        // // Delete File Shares and Global Mapping
        _deleteFileInternalLogic(self[_ein].rec.getGlobalItemViaRecord(_globalItems), _ein, _shares, _shareOrder, _shareCount, _usermeta);
        
        // // Delete File Actual
        _deleteFileActual(self, _ein, _fileIndex, _fileOrder, _fileCount, _group);
        
        // Delete the latest file now
        delete (_fileCount[_ein]);

        // // Reset Files & Group Atomicity
        _usermeta[_ein].lockFiles = false;
        _usermeta[_ein].lockGroups = false;
    }
    
    function _deleteFileInternalLogic(
        IceGlobal.Association storage _globalItem,
        uint _ein,
        mapping (uint => mapping(uint => IceGlobal.GlobalRecord)) storage _shares,
        mapping (uint => mapping(uint => IceSort.SortOrder)) storage _shareOrder, 
        mapping (uint => uint) storage _shareCount,
        mapping (uint => IceGlobal.UserMeta) storage _usermeta
    ) 
    internal {
        // Remove item from sharing of other users
        _shares.removeAllShares(_globalItem, _shareOrder, _shareCount, _usermeta, _ein);
        
        // Remove from global Record
        _globalItem.deleteGlobalRecord();
    }
    
    function _deleteFileActual(
        mapping (uint => File) storage _files,
        uint _ein,
        uint _fileIndex,
        mapping (uint => IceSort.SortOrder) storage _fileOrder,
        mapping (uint => uint) storage _fileCount,
        Group storage _group
    )
    internal {
        // Remove from Group which holds the File
        removeFileFromGroup(_group, _files[_fileIndex].associatedGroupFileIndex);

        // Swap File
        _files[_fileIndex] = _files[_fileCount[_ein]];
        _fileCount[_ein] = _fileOrder.stichSortOrder(_fileIndex, _fileCount[_ein], 0);
    }

    // 2. FILE TO GROUP FUNCTIONS 
    /**
     * @dev Private Function to add file to a group
     * @param _groupIndex is the index of the group belonging to that user, 0 is reserved for root
     * @param _fileIndex is the index of the file belonging to that user
     */
    function addFileToGroup(
        Group storage self, 
        uint _groupIndex, 
        uint _fileIndex
    )
    public
    returns (
        uint associatedGroupIndex, 
        uint associatedGroupFileIndex
    ) {
        // Add File to a group is just adding the index of that file
        uint currentIndex = self.groupFilesCount;
        self.groupFilesCount = self.groupFilesOrder.addToSortOrder(self.groupFilesOrder[0].prev, currentIndex, _fileIndex);

        // Map group index and group order index in file
        associatedGroupIndex = _groupIndex;
        associatedGroupFileIndex = self.groupFilesCount;
    }

    /**
     * @dev Function to remove file from a group
     * @param _groupFileOrderIndex is the index of the file order within that group
     */
    function removeFileFromGroup(
        Group storage self, 
        uint _groupFileOrderIndex
    )
    public {
        uint maxIndex = self.groupFilesCount;
        uint pointerID = self.groupFilesOrder[maxIndex].pointerID;

        self.groupFilesCount = self.groupFilesOrder.stichSortOrder(_groupFileOrderIndex, maxIndex, pointerID);
    }

    /**
     * @dev Private Function to remap file from one group to another
     * @param _newGroupIndex is the index of the new group belonging to that user
     */
    function remapFileToGroup(
        File storage self,
        uint _existingFileIndex,
        Group storage _oldGroup,
        Group storage _newGroup, 
        uint _newGroupIndex
    )
    public
    returns (uint newGroupIndex) {
        // Remove File from existing group
        removeFileFromGroup(_oldGroup, self.associatedGroupFileIndex);

        // Add File to new group
        (self.associatedGroupIndex, self.associatedGroupFileIndex) = addFileToGroup(_newGroup, _newGroupIndex, _existingFileIndex);
        
        // The file added hass the asssociated group file index now
        newGroupIndex = self.associatedGroupFileIndex;
    }
    
    /**
     * @dev Function to check if an item exists
     * @param _itemIndex the index of the item
     * @param _itemCount is the count of that mapping
     */
    function condValidItem(uint _itemIndex, uint _itemCount)
    public pure {
        require (
            (_itemIndex <= _itemCount),
            "Item Not Found"
        );
    }
    
    /**
     * @dev Function to check that a file has been marked for transferee EIN
     * @param _transfereeEIN is the intended EIN for file transfer
     */
    function condMarkedForTransferee(File storage self, uint _transfereeEIN)
    public view {
        // Check if the group file exists or not
        require (
            (self.transferEIN == _transfereeEIN),
            "File not marked for Transfers"
        );
    }

    /**
     * @dev Function to check that ID = 0 is not modified as it's reserved item
     * @param _index The index to check
     */
    function condNonReservedItem(uint _index)
    public pure {
        require (
            (_index > 0),
            "Reserved Item"
        );
    }
    
    // 3. GROUP FUNCTIONS
    /**
     * @dev Function to check that Group Order is valid
     * @param self is the particular group in question
     */
    function condGroupEmpty(Group storage self)
    public view {
        require (
            (self.groupFilesCount == 0),
            "Group has Files"
        );
    }
    
    // 4. USER META FUNCTIONS
    /**
     * @dev Function to check that a file exists for the current EIN
     */
    function condDoesFileExists(uint _fileCount, uint _fileIndex)
    public pure {
        require (
            (_fileIndex <= _fileCount),
            "File not Found"
        );
    }
    
    // 5. STRING / BYTE CONVERSION
    function stringToBytes32(string memory source) 
    public pure 
    returns (bytes32 result) {
        bytes memory tempEmptyStringTest = bytes(source);
        string memory tempSource = source;
        
        if (tempEmptyStringTest.length == 0) {
            return 0x0;
        }
    
        assembly {
            result := mload(add(tempSource, 32))
        }
    }
    
    function bytes32ToString(bytes32 x) 
    public pure 
    returns (string memory) {
        bytes memory bytesString = new bytes(32);
        uint charCount = 0;
        for (uint j = 0; j < 32; j++) {
            byte char = byte(bytes32(uint(x) * 2 ** (8 * j)));
            if (char != 0) {
                bytesString[charCount] = char;
                charCount++;
            }
        }
        bytes memory bytesStringTrimmed = new bytes(charCount);
        for (uint j = 0; j < charCount; j++) {
            bytesStringTrimmed[j] = bytesString[j];
        }
        return string(bytesStringTrimmed);
    }
}