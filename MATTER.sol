// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "./Include.sol";

contract Offering is Configurable {
	using SafeMath for uint;
	using SafeERC20 for IERC20;
	
	bytes32 internal constant _quota_           = 'quota';
	bytes32 internal constant _volume_          = 'volume';
	bytes32 internal constant _unlocked_        = 'unlocked';
	bytes32 internal constant _ratioUnlockFirst_= 'ratioUnlockFirst';
	bytes32 internal constant _ratio_           = 'ratio';
	bytes32 internal constant _isSeed_          = 'isSeed';
	bytes32 internal constant _public_          = 'public';
	bytes32 internal constant _recipient_       = 'recipient';
	bytes32 internal constant _time_            = 'time';
	uint internal constant _timeOfferBegin_     = 0;
	uint internal constant _timeOfferEnd_       = 1;
	uint internal constant _timeUnlockFirst_    = 2;
	uint internal constant _timeUnlockBegin_    = 3;
	uint internal constant _timeUnlockEnd_      = 4;
	
	IERC20 public currency;
	IERC20 public token;

	function __Offering_init(address governor_, address currency_, address token_, address public_, address recipient_, uint[5] memory times_) external initializer {
		__Governable_init_unchained(governor_);
		__Offering_init_unchained(currency_, token_, public_, recipient_, times_);
	}
	
	function __Offering_init_unchained(address currency_, address token_, address public_, address recipient_, uint[5] memory times_) public governance {
		currency = IERC20(currency_);
		token = IERC20(token_);
		_setConfig(_ratio_, 0, 28818181818181);     // for private
		_setConfig(_ratio_, 1, 54333333333333);     // for seed
		_setConfig(_public_, uint(public_));
		_setConfig(_recipient_, uint(recipient_));
		_setConfig(_ratioUnlockFirst_, 0.25 ether); // 25%
		for(uint i=0; i<times_.length; i++)
		    _setConfig(_time_, i, times_[i]);
	}
	
    function setQuota(address addr, uint amount, bool isSeed) public governance {
        uint oldVol = getConfig(_quota_, addr).mul(getConfig(_ratio_, getConfig(_isSeed_, addr)));
        
        _setConfig(_quota_, addr, amount);
        if(isSeed)
            _setConfig(_isSeed_, addr, 1);
            
        uint volume = amount.mul(getConfig(_ratio_, isSeed ? 1 : 0));
        uint totalVolume = getConfig(_volume_, address(0)).add(volume).sub(oldVol);
        require(totalVolume <= token.balanceOf(address(this)), 'out of quota');
        _setConfig(_volume_, address(0), totalVolume);
    }
    
    function setQuotas(address[] memory addrs, uint[] memory amounts, bool isSeed) public {
        for(uint i=0; i<addrs.length; i++)
            setQuota(addrs[i], amounts[i], isSeed);
    }
    
    function getQuota(address addr) public view returns (uint) {
        return getConfig(_quota_, addr);
    }

	function offer() external {
		require(now >= getConfig(_time_, _timeOfferBegin_), 'Not begin');
		if(now > getConfig(_time_, _timeOfferEnd_))                                                 // todo timeOfferEnd should be -1
			if(token.balanceOf(address(this)) > 0)
				token.safeTransfer(address(config[_public_]), token.balanceOf(address(this)));
			else
				revert('offer over');
		uint quota = getConfig(_quota_, msg.sender);
		require(quota > 0, 'no quota');
		require(currency.allowance(msg.sender, address(this)) >= quota, 'allowance not enough');
		require(currency.balanceOf(msg.sender) >= quota, 'balance not enough');
		require(getConfig(_volume_, msg.sender) == 0, 'offered already');
		
		currency.safeTransferFrom(msg.sender, address(config[_recipient_]), quota);
		_setConfig(_volume_, msg.sender, quota.mul(getConfig(_ratio_, getConfig(_isSeed_, msg.sender))));
	}
	
	function getVolume(address addr) public view returns (uint) {
	    return getConfig(_volume_, addr);
	}
	
    function unlockCapacity(address addr) public view returns (uint c) {
        uint timeUnlockFirst    = getConfig(_time_, _timeUnlockFirst_);
        if(timeUnlockFirst == 0 || now < timeUnlockFirst)
            return 0;
        uint timeUnlockBegin    = getConfig(_time_, _timeUnlockBegin_);
        uint timeUnlockEnd      = getConfig(_time_, _timeUnlockEnd_);
        uint volume             = getConfig(_volume_, addr);
        uint ratioUnlockFirst   = getConfig(_ratioUnlockFirst_);

        c = volume.mul(ratioUnlockFirst).div(1e18);
        if(now >= timeUnlockEnd)
            c = volume;
        else if(now > timeUnlockBegin)
            c = volume.sub(c).mul(now.sub(timeUnlockBegin)).div(timeUnlockEnd.sub(timeUnlockBegin)).add(c);
        return c.sub(getConfig(_unlocked_, addr));
    }
    
    function unlock() public {
        uint c = unlockCapacity(msg.sender);
        _setConfig(_unlocked_, msg.sender, getConfig(_unlocked_, msg.sender).add(c));
        _setConfig(_unlocked_, address(0), getConfig(_unlocked_, address(0)).add(c));
        token.safeTransfer(msg.sender, c);
    }
    
    function unlocked(address addr) public view returns (uint) {
        return getConfig(_unlocked_, addr);
    }
    
    fallback() external {
        unlock();
    }
}


contract Timelock is Configurable {
	using SafeMath for uint;
	using SafeERC20 for IERC20;
	
	IERC20 public token;
	address public recipient;
	uint public begin;
	uint public span;
	uint public times;
	uint public total;
	
	function start(address _token, address _recipient, uint _begin, uint _span, uint _times) external governance {
		require(address(token) == address(0), 'already start');
		token = IERC20(_token);
		recipient = _recipient;
		begin = _begin;
		span = _span;
		times = _times;
		total = token.balanceOf(address(this));
	}

    function unlockCapacity() public view returns (uint) {
       if(begin == 0 || now < begin)
            return 0;
            
        for(uint i=1; i<=times; i++)
            if(now < span.mul(i).div(times).add(begin))
                return token.balanceOf(address(this)).sub(total.mul(times.sub(i)).div(times));
                
        return token.balanceOf(address(this));
    }
    
    function unlock() public {
        token.safeTransfer(recipient, unlockCapacity());
    }
    
    fallback() external {
        unlock();
    }
}


contract AuthQuota is Configurable {
	using SafeMath for uint;

    bytes32 internal constant _authQuota_       = 'authQuota';
    
    function authQuotaOf(address signatory) virtual public view returns (uint) {
        return getConfig(_authQuota_, signatory);
    }
    
    function increaseAuthQuota(address signatory, uint increment) virtual external governance returns (uint quota) {
        quota = getConfig(_authQuota_, signatory).add(increment);
        _setConfig(_authQuota_, signatory, quota);
        emit IncreaseAuthQuota(signatory, increment, quota);
    }
    event IncreaseAuthQuota(address indexed signatory, uint increment, uint quota);
    
    function decreaseAuthQuota(address signatory, uint decrement) virtual external governance returns (uint quota) {
        quota = getConfig(_authQuota_, signatory);
        if(quota < decrement)
            decrement = quota;
        return _decreaseAuthQuota(signatory, decrement);
    }
    
    function _decreaseAuthQuota(address signatory, uint decrement) virtual internal returns (uint quota) {
        quota = getConfig(_authQuota_, signatory).sub(decrement);
        _setConfig(_authQuota_, signatory, quota);
        emit DecreaseAuthQuota(signatory, decrement, quota);
    }
    event DecreaseAuthQuota(address indexed signatory, uint decrement, uint quota);
}    
    
    
contract TokenMapped is ContextUpgradeSafe, AuthQuota {
    using SafeERC20 for IERC20;
    
    bytes32 public constant REDEEM_TYPEHASH = keccak256("Redeem(address authorizer,address to,uint256 volume,uint256 chainId,uint256 txHash)");
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");
    bytes32 public DOMAIN_SEPARATOR;
    mapping (uint => bool) public redeemed;
    
    address public token;
    
	function __TokenMapped_init(address governor_, address token_) external initializer {
        __Context_init_unchained();
		__Governable_init_unchained(governor_);
		__TokenMapped_init_unchained(token_);
	}
	
	function __TokenMapped_init_unchained(address token_) public governance {
        token = token_;
        
        uint256 chainId;
        assembly { chainId := chainid() }
        DOMAIN_SEPARATOR = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(ERC20UpgradeSafe(token).name())), chainId, address(this)));
	}
	
    function totalMapped() virtual public view returns (uint) {
        return IERC20(token).balanceOf(address(this));
    }
    
    function stake(uint volume, uint chainId, address to) virtual external {
        IERC20(token).safeTransferFrom(_msgSender(), address(this), volume);
        emit Stake(_msgSender(), volume, chainId, to);
    }
    event Stake(address indexed from, uint volume, uint indexed chainId, address indexed to);
    
    function _redeem(address authorizer, address to, uint volume, uint chainId, uint txHash) virtual internal {
        require(!redeemed[chainId ^ txHash], 'redeemed already');
        redeemed[chainId ^ txHash] = true;
        _decreaseAuthQuota(authorizer, volume);
        IERC20(token).safeTransfer(to, volume);
        emit Redeem(authorizer, to, volume, chainId, txHash);
    }
    event Redeem(address indexed signatory, address indexed to, uint volume, uint chainId, uint indexed txHash);
    
    function redeem(address to, uint volume, uint chainId, uint txHash) virtual external {
        _redeem(_msgSender(), to, volume, chainId, txHash);
    }
    
    function redeem(address authorizer, address to, uint256 volume, uint256 chainId, uint256 txHash, uint8 v, bytes32 r, bytes32 s) external virtual {
        bytes32 structHash = keccak256(abi.encode(REDEEM_TYPEHASH, authorizer, to, volume, chainId, txHash));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "invalid signature");
        require(signatory == authorizer, "unauthorized");

        _redeem(authorizer, to, volume, chainId, txHash);
    }

    uint256[50] private __gap;
}


interface IPermit {
    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;
}


contract MappableToken is ERC20UpgradeSafe, AuthQuota, IPermit {
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    bytes32 public constant REDEEM_TYPEHASH = keccak256("Redeem(address authorizer,address to,uint256 volume,uint256 chainId,uint256 txHash)");
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");
    bytes32 public DOMAIN_SEPARATOR;
    mapping (address => uint) public nonces;
    mapping (uint => bool) public redeemed;
    
    address public token;

	function __MappableToken_init(address governor_, string memory name_, string memory symbol_, uint8 decimals_) external initializer {
        __Context_init_unchained();
		__ERC20_init_unchained(name_, symbol_);
		_setupDecimals(decimals_);
		__Governable_init_unchained(governor_);
		__MappableToken_init_unchained();
	}
	
	function __MappableToken_init_unchained() public governance {
        token = address(this);
        
        uint256 chainId;
        assembly { chainId := chainid() }
        DOMAIN_SEPARATOR = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name())), chainId, address(this)));
	}
	
    function totalMapped() virtual public view returns (uint) {
        return balanceOf(address(this));
    }
    
    function stake(uint volume, uint chainId, address to) virtual external {
        _transfer(_msgSender(), address(this), volume);
        emit Stake(_msgSender(), volume, chainId, to);
    }
    event Stake(address indexed from, uint volume, uint indexed chainId, address indexed to);
    
    function _redeem(address authorizer, address to, uint volume, uint chainId, uint txHash) virtual internal {
        require(!redeemed[chainId ^ txHash], 'redeemed already');
        redeemed[chainId ^ txHash] = true;
        _decreaseAuthQuota(authorizer, volume);
        _transfer(address(this), to, volume);
        emit Redeem(authorizer, to, volume, chainId, txHash);
    }
    event Redeem(address indexed signatory, address indexed to, uint volume, uint chainId, uint indexed txHash);
    
    function redeem(address to, uint volume, uint chainId, uint txHash) virtual external {
        _redeem(_msgSender(), to, volume, chainId, txHash);
    }
    
    function redeem(address authorizer, address to, uint256 volume, uint256 chainId, uint256 txHash, uint8 v, bytes32 r, bytes32 s) external virtual {
        bytes32 structHash = keccak256(abi.encode(REDEEM_TYPEHASH, authorizer, to, volume, chainId, txHash));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "invalid signature");
        require(signatory == authorizer, "unauthorized");

        _redeem(authorizer, to, volume, chainId, txHash);
    }

    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) override external {
        require(deadline >= block.timestamp, 'permit EXPIRED');
        bytes32 digest = keccak256(
            abi.encodePacked(
                '\x19\x01',
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, 'permit INVALID_SIGNATURE');
        _approve(owner, spender, value);
    }
    
    uint256[50] private __gap;
}


contract MappingToken is ERC20CappedUpgradeSafe, AuthQuota, IPermit {
    bytes32 public constant MINT_TYPEHASH = keccak256("Mint(address authorizer,address to,uint256 volume,uint256 chainId,uint256 txHash)");
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");
    bytes32 public DOMAIN_SEPARATOR;
    mapping (address => uint) public nonces;
    mapping (uint => bool) public minted;

	function __MappingToken_init(address governor_, uint cap_, string memory name_, string memory symbol_) external initializer {
        __Context_init_unchained();
		__ERC20_init_unchained(name_, symbol_);
		__ERC20Capped_init_unchained(cap_);
		__Governable_init_unchained(governor_);
		__MappingToken_init_unchained();
	}
	
	function __MappingToken_init_unchained() public governance {
        uint256 chainId;
        assembly { chainId := chainid() }
        DOMAIN_SEPARATOR = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name())), chainId, address(this)));
	}
	
    function _mint(address authorizer, address to, uint volume, uint chainId, uint txHash) virtual internal {
        require(!minted[chainId ^ txHash], 'minted already');
        minted[chainId ^ txHash] = true;
        _decreaseAuthQuota(authorizer, volume);
        _mint(to, volume);
        emit Mint(authorizer, to, volume, chainId, txHash);
    }
    event Mint(address indexed signatory, address indexed to, uint volume, uint chainId, uint indexed txHash);
    
    function mint(address to, uint volume, uint chainId, uint txHash) virtual external {
        _mint(_msgSender(), to, volume, chainId, txHash);
    }
    
    function mint(address authorizer, address to, uint256 volume, uint256 chainId, uint256 txHash, uint8 v, bytes32 r, bytes32 s) external virtual {
        bytes32 structHash = keccak256(abi.encode(MINT_TYPEHASH, authorizer, to, volume, chainId, txHash));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "invalid signature");
        require(signatory == authorizer, "unauthorized");

        _mint(authorizer, to, volume, chainId, txHash);
    }

    function burn(uint volume, uint chainId, address to) virtual external {
        _burn(_msgSender(), volume);
        emit Burn(_msgSender(), volume, chainId, to);
    }
    event Burn(address indexed from, uint volume, uint indexed chainId, address indexed to);
    
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) override external {
        require(deadline >= block.timestamp, 'permit EXPIRED');
        bytes32 digest = keccak256(
            abi.encodePacked(
                '\x19\x01',
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, 'permit INVALID_SIGNATURE');
        _approve(owner, spender, value);
    }

    uint256[50] private __gap;
}


contract MappingMATTER is MappingToken {
	function __MappingMATTER_init(address governor_, uint cap_) external initializer {
        __Context_init_unchained();
		__ERC20_init_unchained("Antimatter.Finance Mapping Token", "MATTER");
		__ERC20Capped_init_unchained(cap_);
		__Governable_init_unchained(governor_);
		__MappingToken_init_unchained();
		__MappingMATTER_init_unchained();
	}
	
	function __MappingMATTER_init_unchained() public governance {
	}
}	


contract MATTER is MappableToken {
	function __MATTER_init(address governor_, address offering_, address public_, address team_, address fund_, address mine_, address liquidity_) external initializer {
        __Context_init_unchained();
		__ERC20_init_unchained("Antimatter.Finance Governance Token", "MATTER");
		__Governable_init_unchained(governor_);
		__MappableToken_init_unchained();
		__MATTER_init_unchained(offering_, public_, team_, fund_, mine_, liquidity_);
	}
	
	function __MATTER_init_unchained(address offering_, address public_, address team_, address fund_, address mine_, address liquidity_) public initializer {
		_mint(offering_,    24_000_000 * 10 ** uint256(decimals()));
		_mint(public_,       1_000_000 * 10 ** uint256(decimals()));
		_mint(team_,        10_000_000 * 10 ** uint256(decimals()));
		_mint(fund_,        10_000_000 * 10 ** uint256(decimals()));
		_mint(mine_,        50_000_000 * 10 ** uint256(decimals()));
		_mint(liquidity_,    5_000_000 * 10 ** uint256(decimals()));
	}
}
