// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "../Vault/BaseStrategy.sol";
import "../Vault/Interfaces/ISPStrategy.sol";
import "../Interfaces/IStabilityPool.sol";
import "../Interfaces/IPriceFeed.sol";
import "../Interfaces/IERC20Decimals.sol";

contract MockStrategy is BaseStrategy {
	constructor(address _debtToken, address _vault) BaseStrategy(_debtToken, _vault) {}

	// ----------------- IStrategyV7 -----------------

	function balanceOf() public view override returns (uint256) {}

	function balanceOfPool() public view override returns (uint256) {}

	function balanceOfWant() public view override returns (uint256) {}

	function harvest() external override {}

	function _beforeDeposit() internal override {}

	function _deposit() internal override {}

	function _withdrawTo(uint256 _amount, address _to) internal override {}

	function _retireStrat() internal override {}

	function _panic() internal override {}
}
