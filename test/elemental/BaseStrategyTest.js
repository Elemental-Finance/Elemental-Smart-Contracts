const deploymentHelper = require("../utils/deploymentHelpers.js")
const testHelpers = require("../utils/testHelpers.js")
const th = testHelpers.TestHelper
const { assertRevert } = th
const MockStrategy = artifacts.require("MockStrategy")

var contracts
var snapshotId
var initialSnapshotId

const deploy = async (treasury, owner, mintingAccounts) => {
	contracts = await deploymentHelper.deployTestContracts(treasury, mintingAccounts)

	debtToken = contracts.core.debtToken

	// Use owner as vault to test permissions easily
	mockStrategy = await MockStrategy.new(debtToken.address, owner)

	circuitBreakerRole = await mockStrategy.CIRCUIT_BREAKER()
	defaultAdminRole = await mockStrategy.DEFAULT_ADMIN_ROLE()
}

contract("BaseStrategy", async accounts => {
	const [
		owner,
		alice,
		bob,
		treasury,
	] = accounts

	describe("Base Strategy Main Functions", async () => {
		before(async () => {
			await deploy(treasury, owner, accounts.slice(0, 20))
			initialSnapshotId = await network.provider.send("evm_snapshot")
		})

		beforeEach(async () => {
			snapshotId = await network.provider.send("evm_snapshot")
		})

		afterEach(async () => {
			await network.provider.send("evm_revert", [snapshotId])
		})

		after(async () => {
			await network.provider.send("evm_revert", [initialSnapshotId])
		})

		describe("Main view functions", async () => {
			it("vault() returns vault address", async () => {
				assert.equal(await mockStrategy.vault(), owner)
			})

			it("want() returns debt token", async () => {
				assert.equal(await mockStrategy.want(), debtToken.address)
			})
		})

		describe("Vault functions", async () => {
			it("beforeDeposit reverts if called from non-vault address", async () => {
				await assertRevert(mockStrategy.beforeDeposit({ from: alice }))
			})

			it("beforeDeposit does not revert when called by the vault address", async () => {
				await mockStrategy.beforeDeposit({ from: owner })
			})

			it("deposit reverts if called from non-vault address", async () => {
				await assertRevert(mockStrategy.deposit({ from: alice }))
			})

			it("deposit reverts when the strategy is paused", async () => {
				await mockStrategy.pause({ from: owner })
				await assertRevert(mockStrategy.deposit({ from: owner }))
			})

			it("deposit does not revert when called by the vault address", async () => {
				await mockStrategy.deposit({ from: owner })
			})

			it("withdrawTo reverts if called from non-vault address", async () => {
				await assertRevert(mockStrategy.withdrawTo(0, alice, { from: alice }))
			})

			it("withdrawTo does not revert when called by the vault address", async () => {
				await mockStrategy.withdrawTo(0, alice, { from: owner })
			})

			it("retireStrat reverts if called from non-vault address", async () => {
				await assertRevert(mockStrategy.retireStrat({ from: alice }))
			})

			it("retireStrat pause contract", async () => {
				await mockStrategy.retireStrat({ from: owner })
				assert.isTrue(await mockStrategy.paused())
			})
		})

		describe("Circuit breaker", async () => {
			it("addCircuitBreaker reverts if called from non-admin address", async () => {
				await assertRevert(mockStrategy.addCircuitBreaker(alice, { from: alice }))
			})

			it("addCircuitBreaker grants CIRCUIT_BREAKER role", async () => {
				await mockStrategy.addCircuitBreaker(bob, { from: owner })
				assert.isTrue(await mockStrategy.hasRole(circuitBreakerRole, bob))
			})

			it("removeCircuitBreaker reverts if called from non-admin address", async () => {
				await assertRevert(mockStrategy.removeCircuitBreaker(alice, { from: alice }))
			})

			it("removeCircuitBreaker revokes role", async () => {
				await mockStrategy.addCircuitBreaker(bob, { from: owner })
				assert.isTrue(await mockStrategy.hasRole(circuitBreakerRole, bob))
				await mockStrategy.removeCircuitBreaker(bob, { from: owner })
				assert.isFalse(await mockStrategy.hasRole(circuitBreakerRole, bob))
			})

			it("panic reverts if called from non-circuit breaker address", async () => {
				await assertRevert(mockStrategy.panic({ from: alice }))
			})

			it("panic pause contract", async () => {
				await mockStrategy.addCircuitBreaker(bob, { from: owner })
				assert.isFalse(await mockStrategy.paused())
				await mockStrategy.panic({ from: bob })
				assert.isTrue(await mockStrategy.paused())
			})
		})

		describe("Admin functions", async () => {
			it("pause reverts if called from non-admin address", async () => {
				await assertRevert(mockStrategy.pause({ from: alice }))
			})

			it("pause contract", async () => {
				assert.isFalse(await mockStrategy.paused())
				await mockStrategy.pause({ from: owner })
				assert.isTrue(await mockStrategy.paused())
			})

			it("unpause reverts if called from non-admin address", async () => {
				await assertRevert(mockStrategy.unpause({ from: alice }))
			})

			it("unpause contract", async () => {
				await mockStrategy.pause({ from: owner })
				assert.isTrue(await mockStrategy.paused())
				await mockStrategy.unpause({ from: owner })
				assert.isFalse(await mockStrategy.paused())
			})

			it("addAdmin reverts if called from non-admin address", async () => {
				await assertRevert(mockStrategy.addAdmin(alice, { from: alice }))
			})

			it("addAdmin grants DEFAULT_ADMIN_ROLE role", async () => {
				await mockStrategy.addAdmin(bob, { from: owner })
				assert.isTrue(await mockStrategy.hasRole(defaultAdminRole, bob))
			})

			it("removeAdmin reverts if called from non-admin address", async () => {
				await assertRevert(mockStrategy.removeAdmin(alice, { from: alice }))
			})

			it("removeAdmin revokes role", async () => {
				await mockStrategy.addAdmin(bob, { from: owner })
				assert.isTrue(await mockStrategy.hasRole(defaultAdminRole, bob))
				await mockStrategy.removeAdmin(bob, { from: owner })
				assert.isFalse(await mockStrategy.hasRole(defaultAdminRole, bob))
			})
		})
	})
})
