pragma solidity ^0.5.1;


/**
 * @title Ice Protocol Control List (Blacklists / Whitelists) Libray
 * @author Harsh Rajat
 * @notice Create blacklists / whitelists for users
 * @dev This Library is part of many that Ice uses form a robust File Management System
 */
library IceControlList {
    // /* ***************
    // * DEFINE FUNCTIONS
    // *************** */
    // /**
    //  * @dev Check if user is in a particular list (blacklist / whitelist)
    //  * @param _nonOwnerEIN is the ein of the recipient
    //  */
    // function isUserInList(mapping(uint => bool) storage self, uint _nonOwnerEIN) 
    // external view 
    // returns (bool) {
    //     return self[_nonOwnerEIN];
    // }
    
    // /**
    //  * @dev Add a non-owner user to whitelist
    //  * @param _nonOwnerEIN is the ein of the recipient
    //  */
    // function addToWhitelist(mapping(uint => bool) storage self, uint _nonOwnerEIN)
    // external {
    //     // Check Restrictions
    //     condNotBlacklisted(self, _nonOwnerEIN);

    //     // Logic
    //     self[_nonOwnerEIN] = true;
    // }

    // /**
    //  * @dev Remove a non-owner user from whitelist
    //  * @param _nonOwnerEIN is the ein of the recipient
    //  */
    // function removeFromWhitelist(mapping(uint => bool) storage self, uint _nonOwnerEIN)
    // external {
    //     // Check Restrictions
    //     condNotBlacklisted(self, _nonOwnerEIN);

    //     // Logic
    //     self[_nonOwnerEIN] = false;
    // }

    // /**
    //  * @dev Remove a non-owner user to blacklist
    //  * @param _nonOwnerEIN is the ein of the recipient
    //  */
    // function addToBlacklist(mapping(uint => bool) storage self, uint _nonOwnerEIN)
    // external {
    //     // Check Restrictions
    //     condNotWhitelisted(self, _nonOwnerEIN);

    //     // Logic
    //     self[_nonOwnerEIN] = true;
    // }

    // /**
    //  * @dev Remove a non-owner user from blacklist
    //  * @param _nonOwnerEIN is the ein of the recipient
    //  */
    // function removeFromBlacklist(mapping(uint => bool) storage self, uint _nonOwnerEIN)
    // external {
    //     // Check Restrictions
    //     condNotWhitelisted(self, _nonOwnerEIN);

    //     // Logic
    //     self[_nonOwnerEIN] = false;
    // }
}