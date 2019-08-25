pragma solidity ^0.5.1;

import "./SafeMath.sol";

import "./IceGlobal.sol";
import "./IceSort.sol";

/**
 * @title Ice Protocol Files / Groups / Users Meta Management System Libray
 * @author Harsh Rajat
 * @notice Create sorting order for maximizing space utilization
 * @dev This Library is part of many that Ice uses form a robust File Management System
 */
library IceFMSAdv {
    using SafeMath for uint;
    
    using IceGlobal for IceGlobal.GlobalRecord;
    using IceGlobal for IceGlobal.Association;
    using IceGlobal for IceGlobal.UserMeta;
    using IceGlobal for mapping (uint8 => IceGlobal.ItemOwner);
    
    using IceSort for mapping (uint => IceSort.SortOrder);
    
    
    /* ***************
    * DEFINE STRUCTURES
    *************** */
     
    /* ***************
    * DEFINE FUNCTIONS
    *************** */
    // 1. SHARING FUNCTIONS
    function shareItemToEINs(
        mapping (uint => mapping(uint => IceGlobal.GlobalRecord)) storage self, 
        mapping (uint => mapping(uint => IceGlobal.Association)) storage _globalItems, 
        mapping (uint => mapping(uint => IceSort.SortOrder)) storage _shareOrder, 
        mapping (uint => uint) storage _shareCount,
        mapping (uint => IceGlobal.UserMeta) storage _usermeta,
        mapping (uint => mapping(uint => bool)) storage _blacklist, 
        IceGlobal.GlobalRecord storage _rec, 
        uint _ein, 
        uint[] calldata _toEINs
    )
    external {
        // Warn: Unbounded Loop
        for (uint i=0; i < _toEINs.length; i++) {
            // call share for each EIN you want to share with
            // Since its multiple share, don't put require blacklist but ignore the share
            // if owner of the file is in blacklist
            if (_blacklist[_toEINs[i]][_ein] == false && (_ein != _toEINs[i])) {
                // track new count
                _shareItemToEIN(
                    self[_toEINs[i]], 
                    _globalItems, 
                    _shareOrder[_toEINs[i]], 
                    _shareCount, 
                    _usermeta[_toEINs[i]],
                    _rec, 
                    _toEINs[i]
                );
            }
        }
    }
    
    function _shareItemToEIN(
        mapping (uint => IceGlobal.GlobalRecord) storage self, 
        mapping (uint => mapping (uint => IceGlobal.Association)) storage _globalItems, 
        mapping (uint => IceSort.SortOrder) storage _shareOrder, 
        mapping (uint => uint) storage _shareCount, 
        IceGlobal.UserMeta storage _usermeta, 
        IceGlobal.GlobalRecord storage _rec, 
        uint _toEIN
    )
    internal {
        // Check Restrictions
        _usermeta.condSharingsOpFree(); // Check if sharing operations are locked
        
        // Logic
        // Set Lock
        _usermeta.lockSharings = true;

        // Create Sharing
        uint curIndex = _shareCount[_toEIN];
        uint nextIndex = curIndex.add(1);
        
        // no need to require as share can be multiple
        // and thus should not hamper other sharings
        if (nextIndex > curIndex) {
            self[nextIndex] = _rec;

            // Add to share order & global mapping
            _shareCount[_toEIN] = _shareOrder.addToSortOrder(_shareOrder[0].prev, _shareCount[_toEIN], 0);
            
            IceGlobal.Association storage globalItem = self[nextIndex].getGlobalItemViaRecord(_globalItems);
            globalItem.addToGlobalItemsMapping(uint8(IceGlobal.AsscProp.sharedTo), _toEIN, nextIndex);
        }

        // Reset Lock
        _usermeta.lockSharings = false;
    }

    /**
     * @dev Function to remove all shares of an Item, always called by owner of the Item
     */
    function removeAllShares(
        mapping (uint => mapping(uint => IceGlobal.GlobalRecord)) storage self,
        uint _ein,
        IceGlobal.Association storage _globalItemIndividual,
        mapping (uint => mapping(uint => IceSort.SortOrder)) storage _shareOrderMapping, 
        mapping (uint => uint) storage _shareCountMapping,
        mapping (uint => IceGlobal.UserMeta) storage _userMetaMapping
    ) 
    external {
        if (_globalItemIndividual.sharedToCount > 0) {
            // Check Restriction
            _userMetaMapping[_ein].condSharingsOpFree(); // Check if sharing operations are locked or not for the owner
    
            // Logic
            // get and pass all EINs, remove share takes care of locking
            uint[32] memory fromEINs = _globalItemIndividual.sharedTo.getHistoralEINsForGlobalItems(_globalItemIndividual.sharedToCount);
            
            // Remove item from share
            removeShareFromEINs(
                self, 
                _ein, 
                fromEINs,
                _globalItemIndividual, 
                _shareOrderMapping, 
                _shareCountMapping, 
                _userMetaMapping
            );
        }
    }
    
    /**
     * @dev Function to remove a shared item from the multiple user's mapping, always called by owner of the Item
     */
    function removeShareFromEINs(
        mapping (uint => mapping(uint => IceGlobal.GlobalRecord)) storage self,
        uint _ein,
        uint[32] memory _fromEINs,
        IceGlobal.Association storage _globalItemIndividual,
        mapping (uint => mapping(uint => IceSort.SortOrder)) storage _shareOrderMapping, 
        mapping (uint => uint) storage _shareCountMapping,
        mapping (uint => IceGlobal.UserMeta) storage _userMetaMapping
    )
    public {
        // Adjust for valid loop
        for (uint i=0; i < _globalItemIndividual.sharedToCount; i++) {
            
            // call share for each EIN you want to remove the share with which is unique
            if ((_ein != _fromEINs[i])) {
                
                // remove individual share 
                _removeShareFromEIN(
                    self[_fromEINs[i]], 
                    _fromEINs[i],
                    _globalItemIndividual, 
                    _shareOrderMapping[_fromEINs[i]], 
                    _shareCountMapping, 
                    _userMetaMapping[_fromEINs[i]]
                );
            }
        }
    }
    
    /**
     * @dev Private Function to remove a shared item from the user's mapping
     */
    function _removeShareFromEIN(
        mapping (uint => IceGlobal.GlobalRecord) storage self,
        uint _fromEIN,
        IceGlobal.Association storage _globalItemIndividual,
        mapping (uint => IceSort.SortOrder) storage _shareOrderMapping, 
        mapping (uint => uint) storage _shareCountMapping,
        IceGlobal.UserMeta storage _specificUserMeta
    )
    internal {
        // Check Restrictions
        _specificUserMeta.condSharingsOpFree(); // Check if sharing operations are locked
        
        // Logic
        // Set Lock
        _specificUserMeta.lockSharings = true;

        // Create Sharing
        uint curIndex = _shareCountMapping[_fromEIN];

        // no need to require as share can be multiple
        // and thus should not hamper other sharings removals
        if (curIndex > 0) {
            uint8 mappedIndex = _globalItemIndividual.sharedTo.findItemOwnerInGlobalItems(_globalItemIndividual.sharedToCount, _fromEIN);
            
            // Only proceed if mapping if found 
            if (mappedIndex > 0) {
                uint _itemIndex = _globalItemIndividual.sharedTo[mappedIndex].index;
                
                // Remove the share from global items mapping
                _globalItemIndividual.removeFromGlobalItemsMapping(uint8(IceGlobal.AsscProp.sharedTo), mappedIndex);
                
                // Swap the shares, then Reove from share order & stich
                self[_itemIndex] = self[curIndex];
                _shareCountMapping[_fromEIN] = _shareOrderMapping.stichSortOrder(_itemIndex, curIndex, 0);
            }
        }

        // Reset Lock
        _specificUserMeta.lockSharings = false;
    }
    
    /**
     * @dev Function to remove shared item by the user to whom the item is shared
     */
    function removeSharingItemBySharee(
        mapping (uint => IceGlobal.GlobalRecord) storage self,
        uint _shareeEIN,
        IceGlobal.Association storage _globalItemIndividual,
        mapping (uint => IceSort.SortOrder) storage _shareOrderMapping, 
        mapping (uint => uint) storage _shareCountMapping,
        IceGlobal.UserMeta storage _specificUserMeta
    ) 
    external {
        // Logic
        _removeShareFromEIN(
            self, 
            _shareeEIN,
            _globalItemIndividual, 
            _shareOrderMapping, 
            _shareCountMapping, 
            _specificUserMeta
        );
    }
}