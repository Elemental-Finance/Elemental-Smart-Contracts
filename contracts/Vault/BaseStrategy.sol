// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./Interfaces/IStrategyV7.sol";

abstract contract BaseStrategy is IStrategyV7, AccessControl, Pausable  {

     bytes32 public constant CIRCUIT_BREAKER = keccak256("CIRCUIT_BREAKER");

    address public immutable WANT_TOKEN;
    address public immutable VAULT;

    error BaseStrategy__OnlyAdmin();
    error BaseStrategy__OnlyVault();

    constructor(
		address _wantToken, 
		address _vault
	) {
		WANT_TOKEN = _wantToken;
		VAULT = _vault;
	}

    /**
    * IStrategyV7 interface
    */
    modifier onlyAdmin() {
        if(!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert BaseStrategy__OnlyAdmin();
        }
        _;
    }

    modifier onlyVault() {
		if(msg.sender != VAULT) {
			revert BaseStrategy__OnlyVault();
		}
		_;
	}

	function vault() external view override returns(address){
		return VAULT;
	}

	function want() public view override returns (IERC20Upgradeable) {
		return IERC20Upgradeable(WANT_TOKEN);
	}

    function beforeDeposit() external onlyVault override {
		_beforeDeposit();
	}

    function _beforeDeposit() internal virtual;

	function deposit() external onlyVault whenNotPaused override {
        _deposit();
	}

    function _deposit() internal virtual;

    function withdrawTo(uint256 _amount, address _to) external onlyVault override {
        _withdrawTo(_amount, _to);
    }

    function _withdrawTo(uint256 _amount, address _to) internal virtual;

    function retireStrat() external onlyVault override {
		_retireStrat();
        _pause();
	}

    function _retireStrat() internal virtual;

    function panic() external override {
        require(hasRole(CIRCUIT_BREAKER, msg.sender));
        _panic();
        _pause();
    }

    function _panic() internal virtual;

    function pause() onlyAdmin public {
        _pause();
    }
    function unpause() onlyAdmin public{
        _unpause();
    }

    function paused() public view override(Pausable, IStrategyV7) returns (bool) {
        return Pausable.paused();
    }

    /**
     * Access Control
     */
    function addAdmin(address newAdmin) external onlyAdmin {
        grantRole(DEFAULT_ADMIN_ROLE, newAdmin);
    }

    function removeAdmin(address removedAdmin) external onlyAdmin {
        revokeRole(DEFAULT_ADMIN_ROLE, removedAdmin);
    }

    function addCircuitBreaker(address circuitBreaker) external onlyAdmin {
        grantRole(CIRCUIT_BREAKER, circuitBreaker);
    }

    function removeCircuitBreaker(address circuitBreaker) external onlyAdmin {
        revokeRole(CIRCUIT_BREAKER, circuitBreaker);
    }
}