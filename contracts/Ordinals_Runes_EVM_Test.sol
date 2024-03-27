// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "contracts/ERC7583/IERC7583.sol";
import "contracts/ERC20/IERC20.sol";
import "contracts/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

interface InscribeContract {
    function generateArt() external returns(bytes memory);
}

contract Ordinals_Runes_EVM is
    IERC7583 /* is more ____ than ERC404 */,
    ERC721,
    Ownable,
    IERC20
{
    using Strings for uint256;

    struct WTW {
        uint256 insId;
        uint256 amount;
    }

    // ODNS_BTC
    uint256 public constant maxSupply = 2_100_000_000_000_000; // 21,000,000 BTC
    uint64 private _mintPerBlock = 5_000_000_000; // 50 BTC for first epoch
    uint64 private _blockNumber;
    uint64 private _totalSupply;
    uint64 private _utxoId;

    // the FT slot of users. user address => slotId(utxoId), the balances of slots are in balancesUTXO
    // mapping(address => uint256) public slotUTXO;
    mapping(address => uint256[]) public UTXOIds;

    // -------- IERC20 --------
    // UTXO balance
    mapping(uint256 => uint256) public balancesUTXO;
    mapping(address => mapping(address => uint256)) private _allowances;

    // -------- block --------
    address public winner;
    uint256 public topBid;
    uint64 public lastETHBlockForORDS;
    uint64 public epoch;
    uint64 public rewardFeeRate = 1000;
    bool public tokenIdIsTooBig;

    // UTXO ID => block number
    mapping(uint256 => uint256) public mintedAt;
    mapping(uint256 => uint256) public bidHistory;
    mapping(uint256 => uint256) public reward;
    mapping(uint256 => address) public mintedBy;

    // for slot
    mapping(address owner => mapping(uint256 index => uint256)) private _ownedTokens;
    mapping(uint256 tokenId => uint256) private _ownedTokensIndex;

    // for runes
    mapping (address => bool) public runes;

    // event TransferFT(uint256 indexed from, uint256 indexed to, uint256 indexed amount);

    constructor(
        address owner
    ) ERC721("Ordinals in EVM", "ORUS") Ownable(owner) {}

    function bidForBlock() public payable {
        require(msg.value > topBid, "There is a higher bid");
        if (winner != address(0)) {
            payable(winner).transfer(topBid);
        }
        topBid = msg.value;
        winner = msg.sender;
    }

    /* 
    Runes:

    Launch Mechanism:
        Fair Launch
        Optional Reserve Allocation for the Project Team
        Airdrop Launch + Whitelist Fundraising Launch + Fundraising Launch + Fair Launch (all combinations should be listed)
    
    Required Attributes:
        Total Supply / Deadline / Block Height Deadline
        Quantity Minted Each Time
        symbol
        decimals
        unit
        
    How to Transfer?
        Transfer by moving UTXOs
        Transfer by operating a specific amount of tokens within the UTXO
     */

    // 50 eth block per block
    function mint() public {
        require(winner != address(0), "There is not a winner");
        require(
            block.number - lastETHBlockForORDS >= 50,
            "Approximately 10 mins per block"
        );

        _utxoId ++;
        balancesUTXO[_utxoId] = _mintPerBlock;
        _addTokenToOwnerEnumeration(winner, _utxoId);
        _mint(winner, _utxoId);

        mintedAt[_utxoId] = _blockNumber;

        payable(msg.sender).transfer((topBid * rewardFeeRate) / 10000);

        _totalSupply += _mintPerBlock;
        if(_blockNumber / 210000 > epoch){
            _mintPerBlock /= 2;
            epoch ++;    
        }

        winner = address(0);
        topBid = 0;
        _blockNumber ++;
        lastETHBlockForORDS = uint64(block.number);
    }

    /// @notice Inscribe `data` into event data.
    function inscribe(uint256 insId, bytes calldata data) external {
        require(
            ERC721._isAuthorized(ERC721.ownerOf(insId), msg.sender, insId),
            "ERC7583: caller is not token owner nor approved"
        );

        emit Inscribe(insId, data);
    }

    // Inscribe and divide, with the partitioning intended to facilitate the trading of inscription NFTs; Satoshi remains inscribed in the first half, and the index in the data cannot exceed the amount
    function inscribeAndDivide(uint256 insId, uint256 amount, bytes calldata data) external {
        address owner = ERC721.ownerOf(insId);
        require(
            ERC721._isAuthorized(owner, msg.sender, insId),
            "ERC7583: caller is not token owner nor approved"
        );

        balancesUTXO[insId] -= amount;
        _utxoId++;
        balancesUTXO[_utxoId] = amount;

        _addTokenToOwnerEnumeration(owner, _utxoId);
        _mint(owner, _utxoId);
        // emit TransferFT(insId, _utxoId, amount);

        emit Inscribe(_utxoId, data);
    }

    // insIdFrom has a lot of FTs, insIdTo is empty
    function inscribe(uint256 insIdFrom, uint256 insIdTo, bytes calldata data) external {
        require(
            ERC721._isAuthorized(ERC721.ownerOf(insIdFrom), msg.sender, insIdFrom) && ERC721._isAuthorized(ERC721.ownerOf(insIdTo), msg.sender, insIdTo),
            "ERC7583: caller is not token owner nor approved"
        );

        // TODO: test for if balancesUTXO[insIdFrom] == 0
        balancesUTXO[insIdFrom] --;
        balancesUTXO[insIdTo] ++;
        // emit TransferFT(insIdFrom, insIdTo, 1);

        emit Inscribe(insIdTo, data);
    }
    
    // Suitable for generating artistic trials
    function inscribe(uint256 insId, address generator) external {
        require(
            ERC721._isAuthorized(ERC721.ownerOf(insId), msg.sender, insId),
            "ERC7583: caller is not token owner nor approved"
        );

        bytes memory artData = InscribeContract(generator).generateArt();
        
        emit Inscribe(insId, artData);
    }

    function inscribe(uint256 insIdFrom, uint256 insIdTo, address generator) external {
        require(
            ERC721._isAuthorized(ERC721.ownerOf(insIdFrom), msg.sender, insIdFrom) && ERC721._isAuthorized(ERC721.ownerOf(insIdTo), msg.sender, insIdTo),
            "ERC7583: caller is not token owner nor approved"
        );

        // TODO: test for if balancesUTXO[insIdFrom] == 0
        balancesUTXO[insIdFrom] --;
        balancesUTXO[insIdTo] ++;
        // emit TransferFT(insIdFrom, insIdTo, 1);

        bytes memory artData = InscribeContract(generator).generateArt();

        emit Inscribe(insIdTo, artData);
    }

    function inscribeAndDivide(uint256 insId, uint256 amount, address generator) external {
        address owner = ERC721.ownerOf(insId);
        require(
            ERC721._isAuthorized(owner, msg.sender, insId),
            "ERC7583: caller is not token owner nor approved"
        );

        balancesUTXO[insId] -= amount;
        _utxoId++;
        balancesUTXO[_utxoId] = amount;

        _addTokenToOwnerEnumeration(owner, _utxoId);
        _mint(owner, _utxoId);
        // emit TransferFT(insId, _utxoId, amount);

        bytes memory artData = InscribeContract(generator).generateArt();
        emit Inscribe(_utxoId, artData);
    }

    /**
     *  --------- overide view functions ---------
     */

    /// @notice If the FT function is already open, then return the balance of FT; otherwise, return the balance of NFT.
    function balanceOf(
        address owner
    ) public view override(ERC721, IERC20) returns (uint256) {
        require(
            owner != address(0),
            "ERC20: address zero is not a valid owner"
        );
        return getSlot(owner) != 0 ? balancesUTXO[getSlot(owner)] : 0;
    }

    function balanceOfNFT(address owner) public view returns (uint256) {
        require(
            owner != address(0),
            "ERC721: address zero is not a valid owner"
        );
        return ERC721.balanceOf(owner);
    }

    /// @notice Has not decimal.
    function decimals() public pure returns (uint8) {
        return 8;
    }

    /// @notice Always return the maximum supply of FT.
    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function UTXONumber() public view returns (uint256) {
        return _utxoId;
    }

    /**
     *  --------- overide approve ---------
     */

    /// @notice Obtain the authorized quantity of FT.
    function allowance(
        address owner,
        address spender
    ) public view returns (uint256) {
        return _allowances[owner][spender];
    }

    /// @notice Check if the spender's authorized limit is sufficient and deduct the amount of this expenditure from the spender's limit.
    function _spendAllowance(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(
                currentAllowance >= amount,
                "ERC20: insufficient allowance"
            );
            unchecked {
                _approveFT(owner, spender, currentAllowance - amount);
            }
        }
    }

    /// @notice The approve function specifically provided for FT.
    /// @param owner The owner of the FT
    /// @param spender The authorized person
    /// @param amount The authorized amount
    function _approveFT(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function approve(
        address spender,
        uint256 amount
    ) public override(ERC721, IERC20) returns (bool) {
        address owner = msg.sender;
        _approveFT(owner, spender, amount);
        return true;
    }

    /**
     *  --------- overide transfer ---------
     */

    /// @notice Transfer like FT for DeFi compatibility. Only the balance in the slot can be transferred using this function.
    /// @param to Receiver address
    /// @return value The amount sent
    function transfer(address to, uint256 value) public virtual returns (bool) {
        address from = msg.sender;
        _transferFT(from, to, value);
        return true;
    }

    function getSlot(address user) public view returns(uint256) {
        return _ownedTokens[user][0];
    }

    function initUTXOForNewUser(address to) external onlyRunesERC20() returns(uint256){
        _utxoId++;
        _ownedTokens[to][0] = _utxoId;
        _ownedTokensIndex[_utxoId] = 0;
        _mint(to, _utxoId);
        return _utxoId;
    }

    function _transferFT(address from, address to, uint256 value) internal {
        // Slots can be minted.
        if (getSlot(to) == 0) {
            _utxoId++;
            _ownedTokens[to][0] = _utxoId;
            _ownedTokensIndex[_utxoId] = 0;
            _mint(to, _utxoId);
        }

        uint256 fromBalance = balancesUTXO[getSlot(from)];
        require(fromBalance >= value, "Insufficient balance");

        unchecked {
            balancesUTXO[getSlot(from)] = fromBalance - value;
        }
        balancesUTXO[getSlot(to)] += value;

        // emit TransferFT(slotUTXO[from], slotUTXO[to], value);
    }

    /// @notice You can freely transfer the balances of multiple inscriptions into one, including slots.
    /// @param froms Multiple inscriptions with a decreased balance
    /// @param to Inscription with a increased balance
    function waterToWine(WTW[] calldata froms, uint256 to) public {
        require(froms.length <= 500, "You drink too much!");
        require(ownerOf(to) == msg.sender, "Is not yours");

        uint256 increment;
        // for from
        for (uint256 i; i < froms.length; i++) {
            uint256 from = froms[i].insId;
            require(ownerOf(from) == msg.sender, "Is not yours");
            uint256 amount = froms[i].amount;
            uint256 fromBalance = balancesUTXO[from];
            require(fromBalance >= amount, "Insufficient balance");
            unchecked {
                balancesUTXO[from] = fromBalance - amount;
            }
            increment += amount;
            // emit TransferFT(from, to, amount);
        }

        balancesUTXO[to] += increment;
    }

    /// @notice You can freely transfer the balances between any two of your inscriptions, including slots.
    /// @notice The inspiration comes from the first miracle of Jesus as described in John 2:1-12.
    /// @param from Inscription with a decreased balance
    /// @param to Inscription with a increased balance
    /// @param amount The value you gonna transfer
    function waterToWine(uint256 from, uint256 to, uint256 amount) public {
        require(
            ownerOf(from) == msg.sender && ownerOf(to) == msg.sender,
            "Is not yours"
        );

        uint256 fromBalance = balancesUTXO[from];
        require(fromBalance >= amount, "Insufficient balance");
        unchecked {
            balancesUTXO[from] = fromBalance - amount;
        }
        balancesUTXO[to] += amount;
        // emit TransferFT(from, to, amount);
    }

    /// @notice only for FT transfer
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override(ERC721, IERC20) returns (bool) {
        // 100 0000 
        if (amount < _utxoId && !tokenIdIsTooBig) {
            if (from != to) {
                if (from != address(0)) _removeTokenFromOwnerEnumeration(from, amount);
                _addTokenToOwnerEnumeration(to, amount);
            }

            ERC721.transferFrom(from, to, amount);
        } else {
            _spendAllowance(from, msg.sender, amount);
            _transferFT(from, to, amount);
        }

        return true;
    }

    /// @notice only for NFT transfer
    function transferFromNFT(
        address from,
        address to,
        uint256 tokenId
    ) public recordSlot(from, to, tokenId) returns (bool) {
        return ERC721.transferFrom(from, to, tokenId);
    }

    /// @notice This place will always support the trading of NFTs.
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override {
        safeTransferFrom(from, to, tokenId, "");
    }

    /// @notice This place will always support the trading of NFTs.
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public override recordSlot(from, to, tokenId) {
        ERC721.safeTransferFrom(from, to, tokenId, data);
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        _requireOwned(tokenId);
        string memory output = string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMinYMin meet" viewBox="0 0 350 350"> <style>.base { fill: white; font-family: serif; font-size: 14px; }</style><rect width="100%" height="100%" fill="black" /><text x="100" y="100" class="base">{</text><text x="130" y="130" class="base">"p":"ERC7583",</text><text x="130" y="160" class="base">"op":"mint",</text><text x="130" y="190" class="base">"tick":"ords",</text><text x="130" y="220" class="base">"amt":',
            balancesUTXO[tokenId].toString(),
            '</text><text x="100" y="250" class="base">}</text></svg>'
        );

        string memory json = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"description": "INS20 is a social experiment, a first attempt to practice inscription within the EVM.", "image": "data:image/svg+xml;base64,',
                        Base64.encode(bytes(output)),
                        '"}'
                    )
                )
            )
        );
        output = string(
            abi.encodePacked("data:application/json;base64,", json)
        );

        string
            memory output0 = '<svg xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMinYMin meet" viewBox="0 0 350 350"> <style> .base { fill: white; font-family: serif; font-size: 14px; } </style> <rect width="100%" height="100%" fill="black" /> <text x="10" y="100" class="base">{</text> <text x="30" y="130" class="base">"tokenId": 0,</text> <text x="30" y="160" class="base">"Description": "The holder of INSC+ #0 will continue</text> <text x="30" y="190" class="base">to keep vigil, until this prophecy (Ezekiel 37:15-28)</text> <text x="30" y="220" class="base"> is fulfilled."</text> <text x="10" y="250" class="base">}</text> </svg>';
        string memory json0 = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"description": "INS20 is a social experiment, a first attempt to practice inscription within the EVM.", "image": "data:image/svg+xml;base64,',
                        Base64.encode(bytes(output0)),
                        '"}'
                    )
                )
            )
        );
        output0 = string(
            abi.encodePacked("data:application/json;base64,", json0)
        );

        return tokenId == 0 ? output0 : output;
    }

    /**
     *  --------- owner access ---------
     */

    function withdraw(address receiver) external onlyOwner {
        payable(receiver).transfer(address(this).balance);
    }

    function setRewardFeeRate(uint64 _rewardFeeRate) public onlyOwner {
        rewardFeeRate = _rewardFeeRate;
    }

    function setTokenIdIsTooBig() public onlyOwner {
        tokenIdIsTooBig = !tokenIdIsTooBig;
    }

    /**
     *  --------- modify ---------
     */

    /// @notice Slot can only be transferred at the end. If the user does not have a slot, then this tokenId will serve as his slot.
    /// @dev This modify is used only for the transfer of NFTs.
    /// @dev The balance of FT is only related to the slot.
    /// @param from Sender
    /// @param to Receiver
    /// @param tokenId TokenID of NFT
    modifier recordSlot(
        address from,
        address to,
        uint256 tokenId
    ) {
        // record the balance of the slot
        if (from != to) {
            if (from != address(0)) _removeTokenFromOwnerEnumeration(from, tokenId);
            _addTokenToOwnerEnumeration(to, tokenId);
        }
        
        _;
    }

    function _removeTokenFromOwnerEnumeration(address from, uint256 tokenId) private {
        // To prevent a gap in from's tokens array, we store the last token in the index of the token to delete, and
        // then delete the last slot (swap and pop).

        uint256 lastTokenIndex = ERC721.balanceOf(from) - 1;
        uint256 tokenIndex = _ownedTokensIndex[tokenId];

        // When the token to delete is the last token, the swap operation is unnecessary
        if (tokenIndex != lastTokenIndex) {
            uint256 lastTokenId = _ownedTokens[from][lastTokenIndex];

            _ownedTokens[from][tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
            _ownedTokensIndex[lastTokenId] = tokenIndex; // Update the moved token's index
        }

        // This also deletes the contents at the last position of the array
        delete _ownedTokensIndex[tokenId];
        delete _ownedTokens[from][lastTokenIndex];
    }

    function _addTokenToOwnerEnumeration(address to, uint256 tokenId) private {
        uint256 length = ERC721.balanceOf(to);
        _ownedTokens[to][length] = tokenId;
        _ownedTokensIndex[tokenId] = length;
    }

    modifier onlyRunesERC20() {
        require(runes[msg.sender], "Only for runes");
        _;
    }
}
