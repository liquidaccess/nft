// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "./interfaces/IERC4906.sol";

contract LiquidAccess is ERC721, ERC721Enumerable, ERC2981, Ownable, IERC4906 {
    using Strings for uint256;

    string private _merchantName; // Merchant name
    uint256 private _merchantId; // Merchant id
    uint256 private _tranferFromCounter; // TransferFrom counter

    mapping(uint256 => string) private dateExpirations; // Mapping from token Id to date_expiration
    mapping(uint256 => string) private typeSubscriptions; // Mapping from token Id to type_subscription
    mapping(address => address) private addressBlacklist; // Black list (user)
    mapping(uint256 => uint256) private nftBlacklist; // Black list (nft)

    event TransferFrom(
        address indexed from,
        address indexed to,
        uint256 tokenId,
        uint256 indexed count
    );

    error TokenIdNotFound(uint256 tokenId);

    modifier tokenExists(uint256 tokenId) {
        if (!_exists(tokenId)) {
            revert TokenIdNotFound(tokenId);
        }
        _;
    }

    constructor(
        string memory name_,
        string memory symbol_,
        string memory merchantName_,
        uint256 merchantId_
    ) ERC721(name_, symbol_) {
        _merchantName = merchantName_;
        _merchantId = merchantId_;

        _setDefaultRoyalty(msg.sender, 500);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable, ERC2981, IERC165)
        returns (bool)
    {
        return interfaceId == bytes4(0x49064906) || super.supportsInterface(interfaceId);
    }

    /**
     * @dev Sets royalty recipient and fee
     */
    function setRoyalty(address _recipient, uint96 _royaltyFee)
        external
        onlyOwner
    {
        _setDefaultRoyalty(_recipient, _royaltyFee);
    }

    function removeRoyalty() external onlyOwner {
        _deleteDefaultRoyalty();
    }

    // safeMint =============================
    function safeMint(
        address to,
        string calldata subscriptionType,
        string calldata expirationDate
    ) external onlyOwner returns(uint256) {
        uint256 tokenId = totalSupply() + 1;
        typeSubscriptions[tokenId] = subscriptionType;
        dateExpirations[tokenId] = expirationDate;
        _safeMint(to, tokenId);
        return tokenId;
    }

    // TransferFrom ===================
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);

        // Transfer or burn
        if (from != address(0)) {
            require(addressBlacklist[from] == address(0), "LA: NFT Holder is blacklisted");
        }

        // Mint or transfer
        if (to != address(0)) {
            require(addressBlacklist[to] == address(0), "LA: Recipient is blacklisted");
        }

        // A transfer
        if (from != address(0) && to != address(0)) {
            require(nftBlacklist[tokenId] == 0, "LA: NFT is blacklisted");
            
            _requireUnlock(tokenId);

            _lockup(tokenId);

            _tranferFromCounter++;
            emit TransferFrom(from, to, tokenId, _tranferFromCounter);
        }
    }

    // Lock-up period ===================
    mapping(uint256 => uint256) private _lockups; // tokenId => locked up until timestamp
    uint256 private _lockupPeriod; // duration of lockup period in seconds

    function lockupLeftOf(uint256 tokenId) public view returns (uint256) {
        uint256 lockup = _lockups[tokenId];
        if (lockup == 0) {
            return 0;
        }
        if (block.timestamp >= lockup) {
            return 0;
        }
        return lockup - block.timestamp;
    }

    function lockupPeriod() public view returns (uint256) {
        return _lockupPeriod;
    }

    function setLockupPeriod(uint256 period) external onlyOwner {
        _lockupPeriod = period;
    }

    function _lockup(uint256 tokenId) private {
        if (_lockupPeriod > 0) {
            _lockups[tokenId] = block.timestamp + _lockupPeriod;
        }
    }

    function _requireUnlock(uint256 tokenId) private {
        uint256 lockup = _lockups[tokenId];
        if (lockup != 0) {
            require(
                block.timestamp >= lockup,
                "LA: Transfer is locked"
            );

            delete _lockups[tokenId];
        }
    }

    // NFT blacklist ===================
    function addNFTToBlacklist(uint256 _nft) external onlyOwner {
        nftBlacklist[_nft] = _nft;
    }

    function removeNFTFromBlacklist(uint256 _nft) external onlyOwner {
        delete nftBlacklist[_nft];
    }

    function isNFTBlacklisted(uint256 _nft) public view returns (bool) {
        return nftBlacklist[_nft] != 0;
    }

    // Users blacklist ===================
    function addAddressToBlacklist(address _address) external onlyOwner {
        addressBlacklist[_address] = _address;
    }

    function removeAddressFromBlacklist(address _address) external onlyOwner {
        delete addressBlacklist[_address];
    }

    function isAddressBlacklisted(address _address) public view returns (bool) {
        return addressBlacklist[_address] != address(0);
    }

    function expirationDateOf(uint256 tokenId)
        public
        view
        tokenExists(tokenId)
        returns (string memory)
    {
        return dateExpirations[tokenId];
    }

    function setExpirationDate(uint256 tokenId, string calldata expirationDate)
        external
        onlyOwner
        tokenExists(tokenId)
    {
        dateExpirations[tokenId] = expirationDate;

        emit MetadataUpdate(tokenId);
    }

    function subscriptionTypeOf(uint256 tokenId)
        public
        view
        tokenExists(tokenId)
        returns (string memory)
    {
        return typeSubscriptions[tokenId];
    }

    function setSubscriptionType(uint256 tokenId, string calldata subscriptionType)
        external
        onlyOwner
        tokenExists(tokenId)
    {
        typeSubscriptions[tokenId] = subscriptionType;

        emit MetadataUpdate(tokenId);
    }

    function merchantName() public view returns (string memory) {
        return _merchantName;
    }

    function merchantId() public view returns (uint256) {
        return _merchantId;
    }

    function userTokens(address owner)
        external
        view
        returns (uint256[] memory)
    {
        uint256 tokenCount = balanceOf(owner);
        uint256[] memory tokens = new uint256[](tokenCount);
        for (uint256 i = 0; i < tokenCount; i++) {
            tokens[i] = tokenOfOwnerByIndex(owner, i);
        }
        return tokens;
    }

    // NFT metadata ===================
    string private _nftName = "NFT Name";
    string private _nftDescription = "NFT Description";
    string private _nftImage = "https://";

    function updateAllTokensMetadata() private {
        uint256 total = totalSupply();

        if (total > 0) {
            emit BatchMetadataUpdate(1, total);
        }
    }

    function setNFTName(string calldata name) external onlyOwner {
        _nftName = name;

        updateAllTokensMetadata();
    }

    function setNFTDescription(string calldata description) external onlyOwner {
        _nftDescription = description;

        updateAllTokensMetadata();
    }

    function setNFTImage(string calldata image) external onlyOwner {
        _nftImage = image;

        updateAllTokensMetadata();
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(
                        bytes(
                            abi.encodePacked(
                                '{"name":"',_nftName,' #',tokenId.toString(),'",',
                                '"description":"',_nftDescription,'",',
                                '"image":"',_nftImage,'",',
                                '"attributes":[',
                                '{"trait_type":"Subscription Type","display_type":"string","value":"',
                                subscriptionTypeOf(tokenId),
                                '"},{"trait_type":"Expiration Date","display_type":"date","value":"',
                                expirationDateOf(tokenId),
                                '"}',
                                "]"
                                "}"
                            )
                        )
                    )
                )
            );
    }

    // Contract metadata ===================
    string private _contractName = "Contract Name";
    string private _contractDescription = "Contract Description";
    string private _contractImage = "https://";

    function setContractName(string calldata name) external onlyOwner {
        _contractName = name;
    }

    function setContractDescription(string calldata description)
        external
        onlyOwner
    {
        _contractDescription = description;
    }

    function setContractImage(string calldata image) external onlyOwner {
        _contractImage = image;
    }

    function contractURI() public view returns (string memory) {
        (address receiver, uint256 fee) = royaltyInfo(0, _feeDenominator());
        string memory receiverString = Strings.toHexString(receiver);
        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(
                        bytes(
                            abi.encodePacked(
                                '{"name":"',_contractName,'",',
                                '"description":"',_contractDescription,'",',
                                '"image":"',_contractImage,'",',
                                '"seller_fee_basis_points":',fee.toString(),',',
                                '"fee_recipient":"',receiverString,'"',
                                '}'
                            )
                        )
                    )
                )
            );
    }
}
