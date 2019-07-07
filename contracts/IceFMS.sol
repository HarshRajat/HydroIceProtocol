pragma solidity ^0.5.1;

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
    
    using IceSort for mapping (uint => IceSort.SortOrder);
    using IceSort for IceSort.SortOrder;
    
    using IceFMSAdv for mapping (uint => mapping(uint => IceGlobal.GlobalRecord));
    
    
    /* ***************
    * DEFINE STRUCTURES
    *************** */
    /* To define File structure of all stored files */
    struct File {
        // File Meta Data
        IceGlobal.GlobalRecord rec; // store the association in global record

        // File Properties
        uint8 protocol; // store protocol of the file stored | 0 is URL, 1 is IPFS
        uint8 transferCount; // To maintain the transfer count for mapping
        
        bytes protocolMeta; // store metadata of the protocol
        bytes32 name; // the name of the file
        bytes32 hash1; // Store the hash of the file for verification | 0x000 for deleted files
        bytes32 hash2; // IPFS hashes are more than 32 bytes
        uint32 timestamp; // to store the timestamp of the block when file is created

        // File Properties - Encryption Properties
        bool encrypted; // whether the file is encrypted
        bool markedForTransfer; // Mark the file as transferred
        mapping (address => string) encryptedHash; // Maps Individual address to the stored hash

        // File Other Properties
        uint associatedGroupIndex;
        uint associatedGroupFileIndex;
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
     */
    function getFileInfo(File storage self)
    external view
    returns (uint8, bytes memory, string memory, string memory, string memory, bool) {
        // Logic
        return (
            self.protocol,                       // Protocol
            self.protocolMeta,                   // Protocol meta
            IceUtil.bytes32ToString(self.name),  // File Name for byte32 to string
            IceUtil.bytes32ToString(self.hash1), // First hash of the file
            IceUtil.bytes32ToString(self.hash2), // Second hash of the file
            
            self.encrypted                      // Whether the file is encrypted or not
        );
    }
    
    /**
     * @dev Function to get file info of an EIN
     * @param self is the pointer to the File Struct (IceFMS Library) passed
     */
    function getFileOtherInfo(File storage self)
    external view
    returns (uint32, uint, uint) {
        // Logic
        return (
            self.timestamp,                      // Timestamp attached to the file
            
            self.associatedGroupIndex,           // The associated group index
            self.associatedGroupFileIndex        // The associated file index
        );
    }

    /**
     * @dev Function to get file tranfer info of an EIN
     * @param self is the pointer to the File Struct (IceFMS Library) passed
     */
    function getFileTransferInfo(File storage self)
    external view
    returns (uint, uint, uint, bool) {
        // Logic
        return (
            self.transferCount,                 // Transfer Count
            self.transferEIN,                   // Transferee EIN
            self.transferIndex,                 // Tranferee's Transfer mapping index
            self.markedForTransfer              // Whether file is marked for transfer or not 
        );
    }

    /**
     * @dev Function to get file tranfer owner info of an EIN
     * @param self is the pointer to the File Struct (IceFMS Library) passed
     * @param _transferIndex is index to poll
     */
    function getFileTransferOwners(File storage self, uint _transferIndex)
    external view
    returns (uint) {
        return self.transferHistory[_transferIndex];    // Return transfer history associated with a particular transfer index
    }
    
    function createFileObject(File storage self, IceGlobal.GlobalRecord memory _rec, 
    uint8 _protocol, bytes memory _protocolMeta, 
    bytes32 _name, bytes32 _hash1, bytes32 _hash2, 
    bool _encrypted, uint _groupIndex, uint _groupFilesCount)
    internal {
        self.rec = _rec;
        
        self.protocol = _protocol;
        self.transferCount = 1;
        
        self.protocolMeta = _protocolMeta;
        self.name = _name;
        self.hash1 = _hash1;
        self.hash2 = _hash2;
        
        self.timestamp = uint32(now);
        
        self.encrypted = _encrypted;
        
        self.associatedGroupIndex = _groupIndex;
        self.associatedGroupFileIndex = _groupFilesCount;
    }
    
    /**
     * @dev Function to write file to a user FMS
     * @param self is the pointer to the File Struct (IceFMS Library) passed
     */
    function writeFile(File storage self, Group storage group, uint _groupIndex, 
    mapping(uint => IceSort.SortOrder) storage fileOrder, uint fileCount, uint _nextIndex, uint _transferEin, string calldata _encryptedHash) 
    external 
    returns (uint newFileCount) {
        // Add file to group 
        (self.associatedGroupIndex, self.associatedGroupFileIndex) = addFileToGroup(group, _groupIndex, _nextIndex);
        group.groupFilesCount = self.associatedGroupFileIndex;
        
        // To map encrypted password
        self.encryptedHash[msg.sender] = _encryptedHash;

        // To map transfer history
        self.transferHistory[0] = _transferEin;

        // Add to Stitch Order & Increment index
        newFileCount = fileOrder.addToSortOrder(fileCount, 0);
    }
    
    /**
     * @dev Function to move file to another group
     * @param _newGroupIndex is the index of the new group where file has to be moved
     */
    function moveFileToGroup(
        File storage self, 
        mapping(uint => IceFMS.Group) storage _groups, 
        mapping(uint => IceSort.SortOrder) storage _groupOrder,
        uint _newGroupIndex,
        mapping (uint => mapping(uint => IceGlobal.Association)) storage _globalItems,
        IceGlobal.UserMeta storage usermeta
    )
    external 
    returns (uint GFIndex){
        // Check Restrictions
        _groupOrder[_newGroupIndex].condValidSortOrder(_newGroupIndex); // Check if the new group is valid
        self.rec.getGlobalItemViaRecord(_globalItems).condUnstampedItem(); // Check if the file is unstamped, can't move a stamped file
        _groups[self.associatedGroupIndex].rec.getGlobalItemViaRecord(_globalItems).condUnstampedItem(); // Check if the current group is unstamped, can't move a file from stamped group
        _groups[_newGroupIndex].rec.getGlobalItemViaRecord(_globalItems).condUnstampedItem(); // Check if the new group is unstamped, can't move a file from stamped group
        usermeta.condFilesOpFree(); // Check if the files operations are not locked for the user
        usermeta.condGroupsOpFree(); // Check if the groups operations are not locked for the user

        // Set Files & Group Atomicity
        usermeta.lockFiles = true;
        usermeta.lockGroups = true;

        GFIndex = remapFileToGroup(_groups[self.associatedGroupIndex], self.associatedGroupFileIndex, _newGroupIndex);

        // Reset Files & Group Atomicity
        usermeta.lockFiles = false;
        usermeta.lockGroups = false;
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
        // Check Restrictions
        self[_fileIndex].rec.getGlobalItemViaRecord(_globalItems).condUnstampedItem(); // Check if the file is unstamped, can't delete a stamped file

        // Set Files & Group Atomicity
        _usermeta[_ein].lockFiles = true;
        _usermeta[_ein].lockGroups = true;

        // Check Restrictions
        condValidItem(_fileIndex, _fileCount[_ein]);
        _groupOrder.condValidSortOrder(self[_fileIndex].associatedGroupIndex);

        // Get current Index, Stich check previous index so not required to recheck
        // uint currentIndex = _fileCount[_ein];
        
        // Delete File Shares and Global Mapping
        //_deleteFileInternalLogic(self[_ein].rec.getGlobalItemViaRecord(_globalItems), _ein, _shares, _shareOrder, _shareCount, _usermeta);
        
        // Delete File Actual
        _deleteFileActual(self, _ein, _fileIndex, _fileOrder, _fileCount, _group);
        
        // Delete the latest file now
        //delete (_fileCount[_ein]);

        // Reset Files & Group Atomicity
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
    function addFileToGroup(Group storage self, uint _groupIndex, uint _fileIndex)
    public
    returns (uint associatedGroupIndex, uint associatedGroupFileIndex) {
        // Add File to a group is just adding the index of that file
        uint currentIndex = self.groupFilesCount;
        self.groupFilesCount = self.groupFilesOrder.addToSortOrder(currentIndex, _fileIndex);

        // Map group index and group order index in file
        associatedGroupIndex = _groupIndex;
        associatedGroupFileIndex = self.groupFilesCount;
    }

    /**
     * @dev Function to remove file from a group
     * @param _groupFileOrderIndex is the index of the file order within that group
     */
    function removeFileFromGroup(Group storage self, uint _groupFileOrderIndex)
    public {
        uint maxIndex = self.groupFilesCount;
        uint pointerID = self.groupFilesOrder[maxIndex].pointerID;

        self.groupFilesCount = self.groupFilesOrder.stichSortOrder(_groupFileOrderIndex, maxIndex, pointerID);
    }

    /**
     * @dev Private Function to remap file from one group to another
     * @param _groupFileOrderIndex is the index of the file order within that group
     * @param _newGroupIndex is the index of the new group belonging to that user
     */
    function remapFileToGroup(Group storage self, uint _groupFileOrderIndex, uint _newGroupIndex)
    public
    returns (uint newGroupIndex) {
        // Get file index for the Association
        uint fileIndex = self.groupFilesOrder[_groupFileOrderIndex].pointerID;

        // Remove File from existing group
        removeFileFromGroup(self, _groupFileOrderIndex);

        // Add File to new group
        (, newGroupIndex) = addFileToGroup(self, _newGroupIndex, fileIndex);
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
    
    // 7. USER META FUNCTIONS
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
}