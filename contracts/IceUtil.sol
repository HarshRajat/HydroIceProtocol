pragma solidity ^0.5.1;

/**
 * @title Ice Protocol Utility Libray
 * @author Harsh Rajat
 * @notice Ice utility library & checks
 * @dev This Library is part of many that Ice uses form a robust File Management System
 */
library IceUtil {

    /* ***************
    * DEFINE FUNCTIONS
    *************** */
    
    // // STRING / BYTE CONVERSION
    // function stringToBytes32(string calldata source) 
    // external pure 
    // returns (bytes32 result) {
    //     bytes memory tempEmptyStringTest = bytes(source);
    //     string memory tempSource = source;
        
    //     if (tempEmptyStringTest.length == 0) {
    //         return 0x0;
    //     }
    
    //     assembly {
    //         result := mload(add(tempSource, 32))
    //     }
    // }
    
    // function bytes32ToString(bytes32 x) 
    // external pure 
    // returns (string memory) {
    //     bytes memory bytesString = new bytes(32);
    //     uint charCount = 0;
    //     for (uint j = 0; j < 32; j++) {
    //         byte char = byte(bytes32(uint(x) * 2 ** (8 * j)));
    //         if (char != 0) {
    //             bytesString[charCount] = char;
    //             charCount++;
    //         }
    //     }
    //     bytes memory bytesStringTrimmed = new bytes(charCount);
    //     for (uint j = 0; j < charCount; j++) {
    //         bytesStringTrimmed[j] = bytesString[j];
    //     }
    //     return string(bytesStringTrimmed);
    // }
}