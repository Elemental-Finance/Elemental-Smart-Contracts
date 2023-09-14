// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ISPStrategy {
	function getAmountOut(address, uint) external view returns (uint);

	function swap(address, uint, uint) external returns (uint);
}
