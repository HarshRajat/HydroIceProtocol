pragma solidity ^0.5.1;

import "./SafeMath.sol";
import "./SafeMath8.sol";

/**
 * @title Ice Protocol Global Items Libray
 * @author Harsh Rajat
 * @notice Create and handle critical File Management functions
 * @dev This Library is part of many that Ice uses form a robust File Management System
 */
library IceGlobal {
    using SafeMath for uint;
    using SafeMath8 for uint8;

    /* ***************
    * DEFINE ENUM
    *************** */
    enum AsscProp {sharedTo, stampedTo}
    
    /* ***************
    * DEFINE STRUCTURES
    *************** */
    /* To define Global Record for a given Item */
    struct GlobalRecord {
        uint i1; // store associated global index 1 for access
        uint i2; // store associated global index 2 for access
    }
    
    /* To define ownership info of a given Item. */
    struct ItemOwner {
        uint EIN; // the EIN of the owner
        uint index; // the key at which the item is stored
    }

    /* To define global file association with EIN
     * Combining EIN and itemIndex and properties will give access to
     * item data.
     */
    struct Association {
        ItemOwner ownerInfo; // To Store Iteminfo

        bool isFile; // whether the Item is File or Group
        bool isHidden; // Whether the item is hidden or not
        bool isStamped; // Whether the item is stamped atleast once
        bool deleted; // whether the association is deleted

        uint8 sharedToCount; // the count of sharing
        uint8 stampedToCount; // the count of stamping

        mapping (uint8 => ItemOwner) sharedTo; // to contain share to
        mapping (uint8 => ItemOwner) stampedTo; // to have stamping reqs
    }
    
    /* To define state and flags for Individual things,
     * used in cases where state change should be atomic
     */
     struct UserMeta {
        bool lockFiles;
        bool lockGroups;
        bool lockTransfers;
        bool lockSharings;
        
        bool hasAvatar;
     }
    
    /* ***************
    * DEFINE FUNCTIONS
    *************** */
    // 1. GLOBAL ITEMS
    function getGlobalItems(Association storage self)
    external view
    returns (uint ownerEIN, uint itemRecord, bool isFile, bool isHidden, bool deleted, uint sharedToCount, uint stampingReqsCount) {
        ownerEIN = self.ownerInfo.EIN;
        itemRecord = self.ownerInfo.index;

        isFile = self.isFile;
        isHidden = self.isHidden;
        deleted = self.deleted;

        sharedToCount = self.sharedToCount;
        stampingReqsCount = self.stampedToCount;
    }
    
    /**
     * @dev Function to get global item via the record struct
     */
    function getGlobalItemViaRecord(GlobalRecord storage self, mapping (uint => mapping(uint => IceGlobal.Association)) storage _globalItems)
    internal view
    returns (Association storage association) {
        association = _globalItems[self.i1][self.i2];
    }
    
    /**
     * @dev Function to get global indexes via the record struct
     */
    function getGlobalIndexesViaRecord(GlobalRecord storage self)
    external view
    returns (uint i1, uint i2) {
        i1 = self.i1;
        i2 = self.i2;
    }

    /**
     * @dev Function to add item to global items
     * @param _ownerEIN is the EIN of global items
     * @param _itemIndex is the index at which the item exists on the user mapping
     * @param _isFile indicates if the item is file or group
     * @param _isHidden indicates if the item has is hiddden or not
     */
    function addItemToGlobalItems(mapping (uint => mapping(uint => Association)) storage self, uint _index1, uint _index2, uint _ownerEIN, uint _itemIndex, bool _isFile, bool _isHidden, bool _isStamped)
    external {
        // Add item to global item, no stiching it
        self[_index1][_index2] = Association (
            ItemOwner (
                _ownerEIN, // Owner EIN
                _itemIndex // Item stored at what index for that EIN
            ),

            _isFile, // Item is file or group
            _isHidden, // whether stamping is initiated or not
            _isStamped, // whether file is stamped or not
            false, // Item is deleted or still exists

            0, // the count of shared EINs
            0 // the count of stamping requests
        );
    }

    /**
     * @dev Function to delete a global items
     */
    function deleteGlobalRecord(Association storage self)
    external {
        self.deleted = true;
    }
    
    function getEINsForGlobalItemsMapping(mapping (uint8 => ItemOwner) storage self, uint8 _count) 
    external view 
    returns (uint[32] memory EINs){
        uint8 i = 0;
        while (_count != 0) {
            EINs[i] = self[_count].EIN;
            
            _count.sub(1);
        }
    }
    
    /**
     * @dev Function to find the relevant mapping index of item mapped in non owner
     * @param _count is the count of relative mapping of global item Association
     * @param _searchForEIN is the non-owner EIN to search
     * @return mappedIndex is the index which is where the relative mapping points to for those items
     */
    function findGlobalItemsMapping(mapping (uint8 => ItemOwner) storage self, uint8 _count, uint256 _searchForEIN) 
    external view 
    returns (uint8 mappedIndex) {
        // Logic
        mappedIndex = 0;
        uint8 count = _count;
        
        while (count != 0) {
            if (self[count].EIN == _searchForEIN) {
                mappedIndex = count;
                
                count = 1;
            }
            
            count.sub(1);
        }
    }
    
    /**
     * @dev Private Function to add to global items mapping
     * @param _ofType is the type of global item properties 
     * @param _toEIN is the non-owner id 
     * @param _itemIndex is the index of the item for the non-owner id
     */
    function addToGlobalItemsMapping(Association storage self, uint8 _ofType, uint _toEIN, uint _itemIndex)
    external
    returns (uint8 newCount) {
        // Logic
        uint8 currentCount;
        
        // Allocalte based on type.
        if (_ofType == uint8(AsscProp.sharedTo)) {
            currentCount = self.sharedToCount;
        }
        else if (_ofType == uint8(AsscProp.stampedTo)) {
            currentCount = self.sharedToCount;
        }
        
        newCount = currentCount.add(1);
        ItemOwner memory mappedItem = ItemOwner (
            _toEIN,
            _itemIndex
        );
            
        if (_ofType == uint8(AsscProp.sharedTo)) {
            self.sharedTo[newCount] = mappedItem;
            self.sharedToCount = newCount;
        }
        else if (_ofType == uint8(AsscProp.stampedTo)) {
            self.stampedTo[newCount] = mappedItem;
            self.stampedToCount = newCount;
        }
    }

    /**
     * @dev Private Function to remove from global items mapping
     * @param _mappedIndex is the non-owner mapping of stored item 
     */
    function removeFromGlobalItemsMapping(Association storage self, uint8 _ofType, uint8 _mappedIndex)
    external
    returns (uint8 newCount) {
        // Logic
        
        // Just swap and deduct
        if (_ofType == uint8(AsscProp.sharedTo)) {
            newCount = self.sharedToCount.sub(1);
            self.sharedTo[_mappedIndex] = self.sharedTo[self.sharedToCount];
            self.sharedToCount = newCount;
        }
        else if (_ofType == uint8(AsscProp.stampedTo)) {
            newCount = self.sharedToCount.sub(1);
            self.sharedTo[_mappedIndex] = self.stampedTo[self.stampedToCount];
            self.stampedToCount = newCount;
        }
    }
    
    /**
     * @dev Function to check that only owner of EIN can access this
     * @param _ein is the EIN of the item owner
     */
    function condItemOwner(Association storage self, uint _ein)
    public view {
        require (
            (self.ownerInfo.EIN == _ein),
            "Only File Owner"
        );
    }
    
    /**
     * @dev Function to check that a file hasn't been marked for stamping
     */
    function condUnstampedItem(Association storage self)
    public view {
        // Check if the group file exists or not
        require (
            (self.isStamped == false),
            "Item Stamped"
        );
    }
    
    // 2. WHITE / BLACK LIST
    /**
     * @dev Check if user is in a particular list (blacklist / whitelist)
     * @param _nonOwnerEIN is the ein of the recipient
     */
    function isUserInList(mapping(uint => bool) storage self, uint _nonOwnerEIN) 
    external view 
    returns (bool) {
        return self[_nonOwnerEIN];
    }
    
    /**
     * @dev Add a non-owner user to whitelist
     * @param _nonOwnerEIN is the ein of the recipient
     * @param _blacklist is the blacklist associated to that user
     */
    function addToWhitelist(mapping(uint => bool) storage self, uint _nonOwnerEIN, mapping(uint => bool) storage _blacklist)
    external {
        // Check Restrictions
        condNotInList(_blacklist, _nonOwnerEIN);

        // Logic
        self[_nonOwnerEIN] = true;
    }

    /**
     * @dev Remove a non-owner user from whitelist
     * @param _nonOwnerEIN is the ein of the recipient
     * @param _blacklist is the blacklist associated to that user
     */
    function removeFromWhitelist(mapping(uint => bool) storage self, uint _nonOwnerEIN, mapping(uint => bool) storage _blacklist)
    external {
        // Check Restrictions
        condNotInList(_blacklist, _nonOwnerEIN);

        // Logic
        self[_nonOwnerEIN] = false;
    }

    /**
     * @dev Remove a non-owner user to blacklist
     * @param _nonOwnerEIN is the ein of the recipient
     * @param _whitelist is the blacklist associated to that user
     */
    function addToBlacklist(mapping(uint => bool) storage self, uint _nonOwnerEIN, mapping(uint => bool) storage _whitelist)
    external {
        // Check Restrictions
        condNotInList(_whitelist, _nonOwnerEIN);

        // Logic
        self[_nonOwnerEIN] = true;
    }

    /**
     * @dev Remove a non-owner user from blacklist
     * @param _nonOwnerEIN is the ein of the recipient
     * @param _whitelist is the blacklist associated to that user
     */
    function removeFromBlacklist(mapping(uint => bool) storage self, uint _nonOwnerEIN, mapping(uint => bool) storage _whitelist)
    external {
        // Check Restrictions
        condNotInList(_whitelist, _nonOwnerEIN);

        // Logic
        self[_nonOwnerEIN] = false;
    }
    
    /**
     * @dev Function to check if the user is not in a list (blacklist or whitelist) by the specific user
     * @param _otherEIN is the EIN of the target user
     */
    function condNotInList(mapping(uint => bool) storage self, uint _otherEIN)
    public view {
        require (
            (self[_otherEIN] == false),
            "EIN in blacklist / whitelist"
        );
    }
    
    // 3. USERMETA
    /**
     * @dev Function to check that operation of Files is currently locked or not
     */
    function condFilesOpFree(UserMeta storage self)
    public view {
        require (
          (self.lockFiles == false),
          "Files Locked"
        );
    }

    /**
     * @dev Function to check that operation of Groups is currently locked or not
     */
    function condGroupsOpFree(UserMeta storage self)
    public view {
        require (
          (self.lockGroups == false),
          "Groups Locked"
        );
    }

    /**
     * @dev Function to check that operation of Sharings is currently locked or not
     */
    function condSharingsOpFree(UserMeta storage self)
    public view {
        require (
          (self.lockSharings == false),
          "Sharing Locked"
        );
    }

    /**
     * @dev Function to check that operation of Transfers is currently locked or not
     */
    function condTransfersOpFree(UserMeta storage self)
    public view {
        require (
          (self.lockTransfers == false),
          "Transfers Locked"
        );
    }
}