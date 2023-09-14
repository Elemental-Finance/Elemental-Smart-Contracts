// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./Interfaces/IStrategyV7.sol";
import "./Interfaces/ISPStrategy.sol";
import "../Interfaces/IStabilityPool.sol";
import "../Interfaces/IPriceFeed.sol";

contract SPStrategy is ISPStrategy, IStrategyV7, Ownable {
	using SafeERC20 for IERC20;

	address public immutable STABILITY_POOL;
	address public immutable DEBT_TOKEN;
	address public immutable VAULT;
	address public treasury;
	address public priceFeed;
	uint public swapFee;
	mapping(address => bool) public swapCollaterals;
	address[] public claimCollaterals;

	error SPStrategy__ZeroAddress();
	error SPStrategy__ArrayNotInAscendingOrder();
	error SPStrategy__CollateralNotEnabledForSwap();
	error SPStrategy__InsufficientOutputAmount();
	error SPStrategy__InsufficientFundsForSwap();
	error SPStrategy__PriceFeedError();
	error SPStrategy__OnlyVault();

	constructor(
		address _debtToken, 
		address _treasury, 
		address _priceFeed, 
		uint _swapFee, 
		address _stabilityPool,
		address _vault
	) {
		setTreasury(_treasury);
		setPriceFeed(_priceFeed);
		setSwapFee(_swapFee);
		DEBT_TOKEN = _debtToken;
		STABILITY_POOL = _stabilityPool;
		VAULT = _vault;
	}

	// ----------------- IStrategyV7 -----------------

	modifier onlyVault() {
		if(msg.sender != VAULT) {
			revert SPStrategy__OnlyVault();
		}
	}

	function vault() external view override returns(address){
		return VAULT;
	}

	function want() external view override returns (address) {
		return DEBT_TOKEN;
	}

	function beforeDeposit() external view onlyVault override returns() {
		//does nothing
	}

	function deposit() external view onlyVault override returns() {
		uint balance = IERC20(DEBT_TOKEN).balanceOf(address(this));
		IStabilityPool(STABILITY_POOL).provideToSP(balance, claimCollaterals);
	}

	// ----------------- Admin -----------------

	/// @notice Enable o disable a collateral for swap
	function setCollateralSwap(address _collateral, bool _whitelisted) external onlyOwner {
		swapCollaterals[_collateral] = _whitelisted;
	}

	/// @notice Set the treasury address
	function setTreasury(address _treasury) public onlyOwner {
		if (_treasury == address(0)) {
			revert SPStrategy__ZeroAddress();
		}
		require(_treasury != address(this), "Vault: treasury cannot be this contract");
		treasury = _treasury;
	}

	/// @notice Set the price feed address
	function setPriceFeed(address _priceFeed) public onlyOwner {
		if (_priceFeed == address(0)) {
			revert SPStrategy__ZeroAddress();
		}
		priceFeed = _priceFeed;
	}

	/// @notice Set the swap fee
	/// @param _rate The swap fee rate in basis points
	function setSwapFee(uint _rate) public onlyOwner {
		swapFee = _rate;
	}

	/// @notice Set collaterals to claim from the stability pool
	/// @dev At the claim, the collaterals array must be in ascending order,
	/// so each time we want to add a collateral to be claim, we must submit the whole array in order
	function setClaimCollaterals(address[] memory _collaterals) external onlyOwner {
		for (uint i = 1; i < _collaterals.length; i++) {
			if (_collaterals[i] <= _collaterals[i - 1]) {
				revert SPStrategy__ArrayNotInAscendingOrder();
			}
		}
		claimCollaterals = _collaterals;
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

		address debtToken = DEBT_TOKEN;
		IERC20(debtToken).safeTransferFrom(msg.sender, address(this), _amountIn);
		IERC20(debtToken).safeTransfer(treasury, fee);
		IERC20(_tokenOut).safeTransfer(msg.sender, amountOut);
		deposit(); //deposits funds from swap
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
			return true
		};
		_claimAssets();
		return IERC20(_token).balanceOf(address(this)) >= _requiredAmount;
	}

	function _claimAssets() private {
		IStabilityPool(STABILITY_POOL).withdrawFromSP(0, claimCollaterals);
	}
}
