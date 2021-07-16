// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "./Include.sol";

contract MATTER2 is PermitERC20UpgradeSafe {
	function __MATTER_init(address offering_, address public_, address team_, address fund_, address mine_, address liquidity_) external initializer {
        __Context_init_unchained();
		__ERC20_init_unchained("Antimatter.Finance Governance Token", "MATTER");
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
