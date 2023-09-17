// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./SPStrategy.sol";
import "./Interfaces/ISPStrategy.sol";

contract SPSwapStrategy is SPStrategy, ISPStrategy {
	using SafeERC20 for IERC20;

	address public treasury;
	uint public swapFee;
	mapping(address => bool) public swapCollaterals;

	error SPStrategy__CollateralNotEnabledForSwap();
	error SPStrategy__InsufficientOutputAmount();
	error SPStrategy__InsufficientFundsForSwap();
	error SPStrategy__PriceFeedError();

	constructor(
		address _debtToken, 
		address _treasury, 
		address _priceFeed, 
		uint _swapFee, 
		address _stabilityPool,
		address _vault
	) SPStrategy(
		_debtToken,
		_stabilityPool,
		_vault,
		_priceFeed
	) {
		setTreasury(_treasury);
		setSwapFee(_swapFee);
	}
    
	/// @notice Get the swap amount out from _tokenOut to DebtToken
	function getAmountOut(address _tokenOut, uint _amountIn) public view override returns (uint) {
		(uint amountOut, ) = _getAmountOut(_tokenOut, _amountIn);
		return amountOut;
	}

	/// @notice Swap DebtToken for _tokenOut
	/// @param _tokenOut The token to swap to
	/// @param _amountIn The amount of DebtToken to swap
	/// @param _minOut The minimum amount of _tokenOut to receive
	function swap(address _tokenOut, uint _amountIn, uint _minOut) external override returns (uint) {
		(uint amountOut, uint fee) = _getAmountOut(_tokenOut, _amountIn);

		if (amountOut < _minOut) {
			revert SPStrategy__InsufficientOutputAmount();
		}
		if (!_checkAndClaimAvailableCollaterals(_tokenOut, amountOut)) {
			revert SPStrategy__InsufficientFundsForSwap();
		}

		address debtToken = WANT_TOKEN;
		IERC20(debtToken).safeTransferFrom(msg.sender, address(this), _amountIn);
		IERC20(debtToken).safeTransfer(treasury, fee);
		IERC20(_tokenOut).safeTransfer(msg.sender, amountOut);
		_deposit(); //deposits funds from swap
		return amountOut;
	}

	function _getAmountOut(address _tokenOut, uint _amountIn) private view returns (uint, uint) {
		if (!swapCollaterals[_tokenOut]) {
			revert SPStrategy__CollateralNotEnabledForSwap();
		}

		uint price = IPriceFeed(priceFeed).fetchPrice(_tokenOut);
		if (price == 0) {
			revert SPStrategy__PriceFeedError();
		}

		uint fee = (_amountIn * swapFee) / 10000;
		// TODO: Check if the feeder always return 18 decimals
		uint amountOut = ((_amountIn - fee) * price) / 1e18;

		return (amountOut, fee);
	}

	function _checkAndClaimAvailableCollaterals(address _token, uint _requiredAmount) private returns (bool) {
		if (IERC20(_token).balanceOf(address(this)) >= _requiredAmount){ 
			return true;
		}
		_claimAssets();
		return IERC20(_token).balanceOf(address(this)) >= _requiredAmount;
	}

	/**
	 * Admin functions
	 */

	/// @notice Enable o disable a collateral for swap
	function setCollateralSwap(address _collateral, bool _whitelisted) external onlyAdmin {
		swapCollaterals[_collateral] = _whitelisted;
	}

	/// @notice Set the treasury address
	function setTreasury(address _treasury) public onlyAdmin {
		if (_treasury == address(0)) {
			revert SPStrategy__ZeroAddress();
		}
		require(_treasury != address(this), "Vault: treasury cannot be this contract");
		treasury = _treasury;
	}

	/// @notice Set the swap fee
	/// @param _rate The swap fee rate in basis points
	function setSwapFee(uint _rate) public onlyAdmin {
		swapFee = _rate;
	}

}