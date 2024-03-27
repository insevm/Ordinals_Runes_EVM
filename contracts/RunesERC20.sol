// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IORDS {
    function ownerOf(uint256 tokenId) external view returns (address);
	function getSlot(address user) external view returns(uint256);
    function initUTXOForNewUser(address to) external returns(uint256);
}

contract RunesERC20 {
    struct WTW {
        uint256 insId;
        uint256 amount;
    }

	// TODO:
	address public ords = address(0);

	uint256 private _totalSupply;
	uint256 private _decimals;

    string private _name;
    string private _symbol;

	// UTXO NFT tokenId => FT balance
    mapping(uint256 => uint256) public balancesUTXO;
	mapping(address => mapping(address => uint256)) private _allowances;

	constructor(string memory name_, string memory symbol_, uint256 decimals_) {
		_name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
	}

    function name() public view virtual returns (string memory) {
        return _name;
    }

    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual returns (uint256) {
        return _decimals;
    }

	function totalSupply() public view virtual returns (uint256) {
        return _totalSupply;
    }

	function balanceOf(address account) public view virtual returns (uint256) {
        require(
            account != address(0),
            "ERC20: address zero is not a valid owner"
        );
		uint256 slot = IORDS(ords).getSlot(account);
        return slot != 0 ? balancesUTXO[slot] : 0;
    }

    /**
     *  --------- approve ---------
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
        // emit Approval(owner, spender, amount);
    }

    function approve(
        address spender,
        uint256 amount
    ) public returns (bool) {
        address owner = msg.sender;
        _approveFT(owner, spender, amount);
        return true;
    }

    /**
     *  --------- transfer ---------
     */

	function transfer(address to, uint256 value) public virtual returns (bool) {
        address from = msg.sender;
        
        _transferFT(from, to, value);
        return true;
    }

    function _transferFT(address from, address to, uint256 value) internal {
        uint256 slotTo = IORDS(ords).getSlot(to);
        if (slotTo == 0) {
            slotTo = IORDS(ords).initUTXOForNewUser(to);
        }

        uint256 slotFrom = IORDS(ords).getSlot(from);
        uint256 fromBalance = balancesUTXO[slotFrom];
        require(fromBalance >= value, "Insufficient balance");

        unchecked {
            balancesUTXO[slotFrom] = fromBalance - value;
        }
        balancesUTXO[slotTo] += value;

        // TODO: emit TransferFT(slotUTXO[from], slotUTXO[to], value);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public returns (bool) {
        _spendAllowance(from, msg.sender, amount);
        _transferFT(from, to, amount);
        return true;
    }

    /// @notice You can freely transfer the balances of multiple inscriptions into one, including slots.
    /// @param froms Multiple inscriptions with a decreased balance
    /// @param to Inscription with a increased balance
    function waterToWine(WTW[] calldata froms, uint256 to) public {
        require(froms.length <= 500, "You drink too much!");
        require(IORDS(ords).ownerOf(to) == msg.sender, "Is not yours");

        uint256 increment;
        // for from
        for (uint256 i; i < froms.length; i++) {
            uint256 from = froms[i].insId;
            require(IORDS(ords).ownerOf(from) == msg.sender, "Is not yours");
            uint256 amount = froms[i].amount;
            uint256 fromBalance = balancesUTXO[from];
            require(fromBalance >= amount, "Insufficient balance");
            unchecked {
                balancesUTXO[from] = fromBalance - amount;
            }
            increment += amount;
            // TODO: emit TransferFT(from, to, amount);
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
            IORDS(ords).ownerOf(from) == msg.sender && IORDS(ords).ownerOf(to) == msg.sender,
            "Is not yours"
        );

        uint256 fromBalance = balancesUTXO[from];
        require(fromBalance >= amount, "Insufficient balance");
        unchecked {
            balancesUTXO[from] = fromBalance - amount;
        }
        balancesUTXO[to] += amount;
        // TODO: emit TransferFT(from, to, amount);
    }
}