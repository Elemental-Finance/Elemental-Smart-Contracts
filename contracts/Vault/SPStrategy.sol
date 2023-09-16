// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./Interfaces/IStrategyV7.sol";
import "./Interfaces/ISPStrategy.sol";
import "../Interfaces/IStabilityPool.sol";
import "../Interfaces/IPriceFeed.sol";
import "../Interfaces/IERC20Decimals.sol";

contract SPStrategy is IStrategyV7, Ownable {
	using SafeERC20 for IERC20;

	address public immutable STABILITY_POOL;
	address public immutable DEBT_TOKEN;
	address public immutable VAULT;
	address[] public claimCollaterals;
	address public priceFeed;

	error SPStrategy__ZeroAddress();
	error SPStrategy__ArrayNotInAscendingOrder();
	error SPStrategy__CollateralNotEnabledForSwap();
	error SPStrategy__InsufficientOutputAmount();
	error SPStrategy__InsufficientFundsForSwap();
	error SPStrategy__PriceFeedError();
	error SPStrategy__OnlyVault();

	constructor(
		address _debtToken, 
		address _stabilityPool,
		address _vault,
		address _priceFeed
	) {
		DEBT_TOKEN = _debtToken;
		STABILITY_POOL = _stabilityPool;
		VAULT = _vault;
		setPriceFeed(_priceFeed);
	}

	// ----------------- IStrategyV7 -----------------

	modifier onlyVault() {
		if(msg.sender != VAULT) {
			revert SPStrategy__OnlyVault();
		}
		_;
	}

	function vault() external view override returns(address){
		return VAULT;
	}

	function want() public view override returns (IERC20Upgradeable) {
		return IERC20Upgradeable(DEBT_TOKEN);
	}

	function beforeDeposit() external onlyVault override {
		//does nothing
	}

	function deposit() public onlyVault override {
		uint balance = balanceOfWant();
		IStabilityPool(STABILITY_POOL).provideToSP(balance, claimCollaterals);
	}

	function withdrawTo(uint256 _amount, address _to) external onlyVault override {
		uint256 collateralValue = valueOfCollaterals();
		uint256 wantBal = balanceOf();
		// Trying not to send dust, only sends debt token if the collat. value is less than 1%
		bool shouldWithdrawCollateral = (collateralValue * 100_00 / wantBal) > 1_00;
		if(shouldWithdrawCollateral){
			uint256 shares = _amount * 10**18 / (wantBal + collateralValue);
			withdrawDebtToken(wantBal * shares / 10**18, _to);
			withdrawCollaterals(shares, _to);
		} else {
			withdrawDebtToken(_amount, _to);
		}
	}

	function withdrawDebtToken(uint256 _amount, address _to) internal {
		IStabilityPool(STABILITY_POOL).withdrawFromSP(_amount, claimCollaterals);
		IERC20(DEBT_TOKEN).safeTransfer(_to, _amount);
	}

	function withdrawCollaterals(uint256 _percentShare, address _to) internal {
		for (uint i = 0; i < claimCollaterals.length; i++) {
			IERC20 token = IERC20(claimCollaterals[i]);
			uint256 balance = token.balanceOf(address(this));
			uint256 amount = _percentShare * balance / 10**18;
			token.safeTransfer(_to, amount);
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
    function retireStrat() external {

	}
    function panic() external {

	}
    function pause() external{}
    function unpause() external{}
    function paused() external view returns (bool){
		return false;
	}

	// ----------------- Admin -----------------

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

	/// @notice Set the price feed address
	function setPriceFeed(address _priceFeed) public onlyOwner {
		if (_priceFeed == address(0)) {
			revert SPStrategy__ZeroAddress();
		}
		priceFeed = _priceFeed;
	}
}
