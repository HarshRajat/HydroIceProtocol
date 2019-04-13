pragma solidity >=0.4.0 <0.6.0;

import "./SnowflakeResolver.sol";
import "./zeppelin/math/SafeMath.sol";
import "./interfaces/HydroInterface.sol";
import "./interfaces/SnowflakeInterface.sol";
import "./interfaces/IdentityRegistryInterface.sol";

/**
 * @title Ice Protocol
 * @notice Create Protocol Less File Storage, Grouping, Stamping and hassle free Encryption / Decryption using Snowflake 
 * @dev This Contract forms File Storage / Stamping / Encryption part of Hydro Protocols
 */
contract IceProtocol is SnowflakeResolver {   
    using SafeMath for uint8;
    using SafeMath for uint;

    /* Define the number of supported Protocols.
    * Onchain refers to protocol which dictates file stored on blockchain,
    * IPFS refers to protocol which dictates file stored on IPFS Network: https://ipfs.io/
    */
    enum Protocol { Onchain, IPFS }

    // Define file status - encrypted or normal
    enum Status { Normal, Encrypted }

    /* To define File structure of all stored files
    */
    struct File {
        uint EIN; // the EIN (hydroID) of the owner
        
        Protocol protocol; // the protocol under which the file is stored
        Status status; // the status of the file
        
        uint8 associatedGroup; // The file group
    }   
    
    /* To connect Files in linear grouping,
    * sort of like a folder
    */
    struct Group {
        uint8 groudID; // the id of the Group
        string name; // the name of the group
    }

    event FileAdded( 
        uint indexed fileID
    );
    
    constructor (address snowflakeAddress) public 
    SnowflakeResolver("Ice", "Document Management / Stamping on Snowflake", 
    snowflakeAddress, false, false) { 

    }
    
    /**
     * @dev Add File and it's Associtation on chain
     * @param hash of the file
     * @param protocol used to store the file
     */
    function addFile(string memory hash, uint8 protocol, uint8 status, string memory group, uint8 groupID) public {
        SnowflakeInterface snowflake = SnowflakeInterface(snowflakeAddress);
        IdentityRegistryInterface identityRegistry = IdentityRegistryInterface(snowflake.identityRegistryAddress());

        uint256 ein = identityRegistry.getEIN(msg.sender);
        require(identityRegistry.isResolverFor(ein, address(this)), "ein has not set this resolver");
        
        // Check if group already exists
        
    }
    
    
    // Checks whether the provided (v, r, s) signature was created by the private key associated with _address
    function isSigned(address _address, bytes32 messageHash, uint8 v, bytes32 r, bytes32 s) public pure returns (bool) {
        return (_isSigned(_address, messageHash, v, r, s) || _isSignedPrefixed(_address, messageHash, v, r, s));
    }

    // Checks unprefixed signatures
    function _isSigned(address _address, bytes32 messageHash, uint8 v, bytes32 r, bytes32 s) internal pure returns (bool) {
        return ecrecover(messageHash, v, r, s) == _address;
    }

    // Checks prefixed signatures (e.g. those created with web3.eth.sign)
    function _isSignedPrefixed(address _address, bytes32 messageHash, uint8 v, bytes32 r, bytes32 s) internal pure returns (bool) {
        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        bytes32 prefixedMessageHash = keccak256(abi.encodePacked(prefix, messageHash));
        return ecrecover(prefixedMessageHash, v, r, s) == _address;
    }
}
