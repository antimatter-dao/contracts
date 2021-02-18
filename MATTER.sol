// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "./Include.sol";

contract MATTER is ERC20UpgradeSafe, Configurable {
	function __MATTER_init(address governor_, address offering_, address public_, address team_, address fund_, address mine_, address liquidity_) external initializer {
        __Context_init_unchained();
		__ERC20_init_unchained("Antimatter.Finance Governance Token", "MATTER");
		__Governable_init_unchained(governor_);
		__MATTER_init_unchained(offering_, public_, team_, fund_, mine_, liquidity_);
	}
	
	function __MATTER_init_unchained(address offering_, address public_, address team_, address fund_, address mine_, address liquidity_) public governance {
		_mint(offering_,    24_000_000 * 10 ** uint256(decimals()));
		_mint(public_,       1_000_000 * 10 ** uint256(decimals()));
		_mint(team_,        10_000_000 * 10 ** uint256(decimals()));
		_mint(fund_,        10_000_000 * 10 ** uint256(decimals()));
		_mint(mine_,        50_000_000 * 10 ** uint256(decimals()));
		_mint(liquidity_,    5_000_000 * 10 ** uint256(decimals()));
	}
	
}


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
        _setConfig(_quota_, addr, amount);
        if(isSeed)
            _setConfig(_isSeed_, addr, 1);
            
        uint volume = amount.mul(getConfig(_ratio_, isSeed ? 1 : 0));
        uint totalVolume = getConfig(_volume_, address(0)).add(volume);
        require(totalVolume <= token.balanceOf(address(this)), 'out of quota');
        _setConfig(_volume_, address(0), totalVolume);
    }
    
    function setQuota(address[] memory addrs, uint[] memory amounts, bool isSeed) public {
        for(uint i=0; i<addrs.length; i++)
            setQuota(addrs[i], amounts[i], isSeed);
    }
    
    function getQuota(address addr) public view returns (uint) {
        return getConfig(_quota_, addr);
    }

	function offer() external {
		require(now >= getConfig(_time_, _timeOfferBegin_), 'Not begin');
		if(now > getConfig(_time_, _timeOfferEnd_))
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
