// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "./BaseStrategy.sol";
import "./Interfaces/ISPStrategy.sol";
import "../Interfaces/IStabilityPool.sol";
import "../Interfaces/IPriceFeed.sol";
import "../Interfaces/IERC20Decimals.sol";

contract SPStrategy is BaseStrategy {
	using SafeERC20 for IERC20;

	uint8 internal constant SHARES_DECIMAL = 18;
	address public immutable STABILITY_POOL;
	address[] public claimCollaterals;
	address public priceFeed;

	error SPStrategy__ZeroAddress();
	error SPStrategy__ArrayNotInAscendingOrder();

	constructor(
		address _debtToken, 
		address _spAddress,
		address _vault,
		address _priceFeed
	) BaseStrategy(_debtToken, _vault) {
		STABILITY_POOL = _spAddress;
		setPriceFeed(_priceFeed);
	}

	// ----------------- IStrategyV7 -----------------


	function _beforeDeposit() internal override {
		//does nothing
	}

	function _deposit() internal override {
		uint balance = balanceOfWant();
		_stabilityPool().provideToSP(balance, claimCollaterals);
	}

	function _stabilityPool() internal view returns (IStabilityPool){
		return IStabilityPool(STABILITY_POOL);
	}

	function _withdrawTo(uint256 _amount, address _to) internal override {
		uint256 collateralValue = valueOfCollaterals();
		uint256 wantBal = balanceOf();
		// Trying not to send dust, only sends debt token if the collat. value is less than 1%
		bool shouldWithdrawCollateral = (collateralValue * 100_00 / wantBal) > 1_00;
		if(shouldWithdrawCollateral){
			uint256 shares = _amount * 10**SHARES_DECIMAL / (wantBal + collateralValue);
			_withdrawDebtToken(wantBal * shares / 10**SHARES_DECIMAL, _to);
			_withdrawCollateralsShare(shares, _to);
		} else {
			_withdrawDebtToken(_amount, _to);
		}
	}

	function _withdrawDebtToken(uint256 _amount, address _to) internal {
		IStabilityPool(STABILITY_POOL).withdrawFromSP(_amount, claimCollaterals);
		IERC20(WANT_TOKEN).safeTransfer(_to, _amount);
	}

	function _withdrawCollateralsShare(uint256 _percentShare, address _to) internal {
		for (uint i = 0; i < claimCollaterals.length; i++) {
			IERC20 token = IERC20(claimCollaterals[i]);
			uint256 balance = token.balanceOf(address(this));
			uint256 amount = _percentShare * balance / 10**SHARES_DECIMAL;
			token.safeTransfer(_to,amount);
		}
	}

	function debtBalance() public view returns(uint256) {
		return balanceOfWant() + balanceOfPool();
	}

	function balanceOf() public view returns (uint256){
		return balanceOfWant() + balanceOfPool() + valueOfCollaterals();
	}

    function balanceOfWant() public view returns (uint256) {
		return want().balanceOf(address(this));
	}

	/**
	 * Returns the value of all collaterals
	 */
	function valueOfCollaterals() public view returns (uint256) {
		(address[] memory assetGains, uint256[] memory amounts) = balanceOfCollaterals();
		uint256 value = 0;
		for(uint256 i = 0; i < assetGains.length; i++){
			if (amounts[i] > 0){
				uint256 price = IPriceFeed(priceFeed).fetchPrice(assetGains[i]);
				value += (price * amounts[i]) / (10 ** IERC20Decimals(assetGains[i]).decimals());
			} 
		}
		return value;
	}

	/**
	* Sums the collateral in the SP and in the strat
	*/
	function balanceOfCollaterals() public view returns (address[] memory, uint256[] memory){
		(address[] memory assetGains, uint256[] memory amounts) = IStabilityPool(STABILITY_POOL).getDepositorGains(address(this), claimCollaterals);
		for(uint256 i = 0; i < assetGains.length; i++){
			amounts[i] += IERC20(assetGains[i]).balanceOf(address(this));
		}
		return (assetGains, amounts);
	}

    function balanceOfPool() public view returns (uint256) {
		return IStabilityPool(STABILITY_POOL).getCompoundedDebtTokenDeposits(address(this));
	}

	function harvest() external {
		_claimAssets();
	}

	function _claimAssets() internal {
		IStabilityPool(STABILITY_POOL).withdrawFromSP(0, claimCollaterals);
	}

	function _retireStrat() internal override {
		_withdrawToVault();
	}

	function _withdrawToVault() internal {
		uint256 poolBal = balanceOfPool();
		_withdrawDebtToken(poolBal, VAULT);
		_withdrawCollateralsShare(10**SHARES_DECIMAL, VAULT);
	}

    function _panic() internal override {
		_withdrawToVault();
	}

	// ----------------- Admin -----------------

	/// @notice Set collaterals to claim from the stability pool
	/// @dev At the claim, the collaterals array must be in ascending order,
	/// so each time we want to add a collateral to be claim, we must submit the whole array in order
	function setClaimCollaterals(address[] memory _collaterals) external onlyAdmin {
		for (uint i = 1; i < _collaterals.length; i++) {
			if (_collaterals[i] <= _collaterals[i - 1]) {
				revert SPStrategy__ArrayNotInAscendingOrder();
			}
		}
		claimCollaterals = _collaterals;
	}

	/// @notice Set the price feed address
	function setPriceFeed(address _priceFeed) public onlyAdmin {
		if (_priceFeed == address(0)) {
			revert SPStrategy__ZeroAddress();
		}
		priceFeed = _priceFeed;
	}
}
