// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.24;

import {ERC721A} from "erc721a/contracts/ERC721A.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {OperatorFilterer} from "closedsea/src/OperatorFilterer.sol";
import {MerkleProof} from '@openzeppelin/contracts/utils/cryptography/MerkleProof.sol';

error MaxPerOrderExceeded();
error MaxSupplyExceeded();
error MaxPerWalletExceeded();
error PresaleClosed();
error NotInPresaleList();
error PublicSaleClosed();
error TransfersLocked();
error NotAllowedByRegistry();
error RegistryNotSet();
error WrongWeiSent();
error MaxFeeExceeded();
error InputLengthsMismatch();
error InvalidMerkleProof();

interface IRegistry {
    function isAllowedOperator(address operator) external view returns (bool);
}

interface IERC20 {
    /**
        * @dev Returns the amount of tokens owned by `account`.
        */
    function balanceOf(address account) external view returns (uint256);

    /**
        * @dev Moves `amount` tokens from the caller's account to `to`.
        *
        * Returns a boolean value indicating whether the operation succeeded.
        *
        * Emits a {Transfer} event.
        */
    function transfer(address to, uint256 amount) external returns (bool);
}

contract MintifyBaseKeys is Ownable, OperatorFilterer, ERC2981, ERC721A {
    using BitMaps for BitMaps.BitMap;

    bool public presaleOpen;
    bool public publicOpen;
    uint256 private maxSupply = 10000;
    uint256 private maxPerWallet;
    uint256 private maxPerOrder;
    uint256 private publicPrice = 26900000000000000;
    uint256 private presalePrice = 30000000000000000;

    bytes32 public merkleRoot;

    bool public operatorFilteringEnabled = true;
    bool public initialTransferLockOn = true;
    bool public isRegistryActive;
    address public registryAddress;

    string public _baseTokenURI = "https://genesis-metas.mintify.xyz";

    constructor() ERC721A("Mintify Base Keys", "MNFBSK") {

        // Register operator filtering
        _registerForOperatorFiltering();

        // Set initial 2% royalty
        _setDefaultRoyalty(owner(), 200);
    }

    // PreSale Mint
    function presaleMint(uint256 quantity, bytes32[] calldata merkleProof) external payable {
        if (maxPerOrder != 0 && quantity > maxPerOrder) {
            revert MaxPerOrderExceeded();
        }
        if (maxSupply != 0 && totalSupply() + quantity > maxSupply) {
            revert MaxSupplyExceeded();
        }
        if (maxPerWallet != 0 && balanceOf(msg.sender) + quantity > maxPerWallet) {
            revert MaxPerWalletExceeded();
        }
        if (!presaleOpen) {
            revert PresaleClosed();
        }
        if (msg.value != (presalePrice * quantity)) {
            revert WrongWeiSent();
        }

        // Using Merkle Tree
        bytes32 node = keccak256(abi.encodePacked(msg.sender));
        if (!MerkleProof.verify(merkleProof, merkleRoot, node)) {
            revert InvalidMerkleProof();
        }

         _mint(msg.sender, quantity);
    }

    // Public Mint
    function publicMint(uint256 quantity) external payable {
        if (maxPerOrder != 0 && quantity > maxPerOrder) {
            revert MaxPerOrderExceeded();
        }
        if (maxSupply != 0 && totalSupply() + quantity > maxSupply) {
            revert MaxSupplyExceeded();
        }
        if (maxPerWallet != 0 && balanceOf(msg.sender) + quantity > maxPerWallet) {
            revert MaxPerWalletExceeded();
        }
        if (!publicOpen) {
            revert PublicSaleClosed();
        }
        if (msg.value != (publicPrice * quantity)) {
            revert WrongWeiSent();
        }
        _mint(msg.sender, quantity);
    }

    // =========================================================================
    //                           Owner Only Functions
    // =========================================================================

    // Owner airdrop
    function airDrop(address[] memory users, uint256[] memory amounts) external onlyOwner {
        // iterate over users and amounts
        if (users.length != amounts.length) {
            revert InputLengthsMismatch();
        }
        for (uint256 i; i < users.length;) {
            if (maxSupply != 0 && totalSupply() + amounts[i] > maxSupply) {
                revert MaxSupplyExceeded();
            }
            _mint(users[i], amounts[i]);
            unchecked {
                ++i;
            }
        }
    }

    // Owner unrestricted mint
    function ownerMint(address to, uint256 quantity) external onlyOwner {
        if (maxSupply != 0 && totalSupply() + quantity > maxSupply) {
            revert MaxSupplyExceeded();
        }
        _mint(to, quantity);
    }

    // Enables or disables public sale
    function setPublicState(bool newState) external onlyOwner {
        publicOpen = newState;
    }

    // Enables or disables presale
    function setPresaleState(bool newState) external onlyOwner {
        presaleOpen = newState;
    }

    // Set merkle root
    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;
    }

    // Set max supply
    function setMaxSupply(uint256 newMaxSupply) external onlyOwner {
        maxSupply = newMaxSupply;
    }

    // Set max per wallet
    function setMaxPerWallet(uint256 newMaxPerWallet) external onlyOwner {
        maxPerWallet = newMaxPerWallet;
    }

    // Set max per order
    function setMaxPerOrder(uint256 newMaxPerOrder) external onlyOwner {
        maxPerOrder = newMaxPerOrder;
    }

    // Set public sale price
    function setPublicSalePrice(uint256 newPrice) external onlyOwner {
        publicPrice = newPrice;
    }

    // Set presale price
    function setPresalePrice(uint256 newPrice) external onlyOwner {
        presalePrice = newPrice;
    }

    // Withdraw Balance to owner
    function withdraw() public onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    // Withdraw Balance to Address
    function withdrawTo(address payable _to) public onlyOwner {
        _to.transfer(address(this).balance);
    }

    // Break Transfer Lock
    function breakLock() external onlyOwner {
        initialTransferLockOn = false;
    }

    // Withdraw any ERC20 balance
    function withdrawERC20(address _token, address _to) external onlyOwner {
        IERC20 token = IERC20(_token);
        token.transfer(_to, token.balanceOf(address(this)));
    }

    // =========================================================================
    //                             ERC721A Misc
    // =========================================================================

    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }

    // =========================================================================
    //                           Operator filtering
    // =========================================================================

    function setApprovalForAll(address operator, bool approved)
        public
        override (ERC721A)
        onlyAllowedOperatorApproval(operator)
    {
        if (initialTransferLockOn) {
            revert TransfersLocked();
        }
        super.setApprovalForAll(operator, approved);
    }

    function approve(address operator, uint256 tokenId)
        public
        payable
        override (ERC721A)
        onlyAllowedOperatorApproval(operator)
    {
        if (initialTransferLockOn) {
            revert TransfersLocked();
        }
        super.approve(operator, tokenId);
    }

    function transferFrom(address from, address to, uint256 tokenId)
        public
        payable
        override (ERC721A)
        onlyAllowedOperator(from)
    {
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId)
        public
        payable
        override (ERC721A)
        onlyAllowedOperator(from)
    {
        super.safeTransferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data)
        public
        payable
        override (ERC721A)
        onlyAllowedOperator(from)
    {
        super.safeTransferFrom(from, to, tokenId, data);
    }

    function setOperatorFilteringEnabled(bool value) public onlyOwner {
        operatorFilteringEnabled = value;
    }

    function _operatorFilteringEnabled() internal view override returns (bool) {
        return operatorFilteringEnabled;
    }

    // =========================================================================
    //                             Registry Check
    // =========================================================================
    function _beforeTokenTransfers(
        address from,
        address to,
        uint256 startTokenId,
        uint256 quantity
    ) internal override {
        if (initialTransferLockOn && from != address(0) && to != address(0)) {
            revert TransfersLocked();
        }
        if (_isValidAgainstRegistry(msg.sender)) {
            super._beforeTokenTransfers(from, to, startTokenId, quantity);
        } else {
            revert NotAllowedByRegistry();
        }
    }

    function _isValidAgainstRegistry(address operator)
        internal
        view
        returns (bool)
    {
        if (isRegistryActive) {
            IRegistry registry = IRegistry(registryAddress);
            return registry.isAllowedOperator(operator);
        }
        return true;
    }

    function setIsRegistryActive(bool _isRegistryActive) external onlyOwner {
        if (registryAddress == address(0)) revert RegistryNotSet();
        isRegistryActive = _isRegistryActive;
    }

    function setRegistryAddress(address _registryAddress) external onlyOwner {
        registryAddress = _registryAddress;
    }

    // =========================================================================
    //                                  ERC165
    // =========================================================================

    function supportsInterface(bytes4 interfaceId) public view override (ERC721A, ERC2981) returns (bool) {
        // Supports the following `interfaceId`s:
        // - IERC165: 0x01ffc9a7
        // - IERC721: 0x80ac58cd
        // - IERC721Metadata: 0x5b5e139f
        // - IERC2981: 0x2a55205a
        return ERC721A.supportsInterface(interfaceId) || ERC2981.supportsInterface(interfaceId);
    }

    // =========================================================================
    //                                 ERC2891
    // =========================================================================

    function setDefaultRoyalty(address receiver, uint96 feeNumerator) public onlyOwner {
        if (feeNumerator > 1000) {
            revert MaxFeeExceeded();
        }
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function setTokenRoyalty(
        uint256 tokenId,
        address receiver,
        uint96 feeNumerator
    ) external onlyOwner {
        if (feeNumerator > 1000) {
            revert MaxFeeExceeded();
        }
        _setTokenRoyalty(tokenId, receiver, feeNumerator);
    }

    // =========================================================================
    //                                 Metadata
    // =========================================================================

    function setBaseURI(string calldata baseURI) external onlyOwner {
        _baseTokenURI = baseURI;
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (!_exists(tokenId)) revert URIQueryForNonexistentToken();

        string memory baseURI = _baseURI();
        return bytes(baseURI).length != 0 ? string(abi.encodePacked(baseURI, "/base/", _toString(tokenId))) : "";

    }

}