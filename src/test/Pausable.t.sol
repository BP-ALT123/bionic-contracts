// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.12;

import "./BionicTestHelper.t.sol";

contract PausableTests is BionicTestHelper {

    /// @notice Emitted when the `pauserRegistry` is set to `newPauserRegistry`.
    event PauserRegistrySet(IPauserRegistry pauserRegistry, IPauserRegistry newPauserRegistry);

    ///@dev test that pausing a contract works
    function testPausingWithdrawalsFromStrategyManager(uint256 amountToDeposit, uint256 amountToWithdraw) public {
        cheats.assume(amountToDeposit <= weth.balanceOf(address(this)));
        // if first deposit amount to base strategy is too small, it will revert. ignore that case here.
        cheats.assume(amountToDeposit >= 1);
        cheats.assume(amountToWithdraw <= amountToDeposit);

        address sender = getOperatorAddress(0);
        _testDepositToStrategy(sender, amountToDeposit, weth, wethStrat);

        cheats.startPrank(pauser);
        strategyManager.pause(type(uint256).max);
        cheats.stopPrank();

        // uint256 strategyIndex = 0;

        cheats.prank(sender);

        // TODO: write this to work with completing a queued withdrawal
        // cheats.expectRevert(bytes("Pausable: paused"));
        // strategyManager.withdrawFromStrategy(strategyIndex, wethStrat, weth, amountToWithdraw);
        // cheats.stopPrank();
    }

    function testUnauthorizedPauserStrategyManager(address unauthorizedPauser)
        public
        fuzzedAddress(unauthorizedPauser)
    {
        cheats.assume(!BionicPauserReg.isPauser(unauthorizedPauser));
        cheats.startPrank(unauthorizedPauser);
        cheats.expectRevert(bytes("msg.sender is not permissioned as pauser"));
        strategyManager.pause(type(uint256).max);
        cheats.stopPrank();
    }

    function testSetPauser(address newPauser) public fuzzedAddress(newPauser) {
        cheats.startPrank(unpauser);
        BionicPauserReg.setIsPauser(newPauser, true);
        cheats.stopPrank();
    }

    function testSetUnpauser(address newUnpauser) public fuzzedAddress(newUnpauser) {
        cheats.startPrank(unpauser);
        BionicPauserReg.setUnpauser(newUnpauser);
        cheats.stopPrank();
    }

    function testSetPauserUnauthorized(address fakePauser, address newPauser)
        public
        fuzzedAddress(newPauser)
        fuzzedAddress(fakePauser)
    {
        cheats.assume(fakePauser != BionicPauserReg.unpauser());
        cheats.startPrank(fakePauser);
        cheats.expectRevert(bytes("msg.sender is not permissioned as unpauser"));
        BionicPauserReg.setIsPauser(newPauser, true);
        cheats.stopPrank();
    }

    function testSetPauserRegistryUnpauser(IPauserRegistry newPauserRegistry) public {
        cheats.assume(address(newPauserRegistry) != address(0));
        IPauserRegistry oldPauserRegistry = strategyManager.pauserRegistry();
        cheats.prank(unpauser);
        cheats.expectEmit(true, true, true, true, address(strategyManager));
        emit PauserRegistrySet(oldPauserRegistry, newPauserRegistry);
        strategyManager.setPauserRegistry(newPauserRegistry);
        
        assertEq(address(newPauserRegistry), address(strategyManager.pauserRegistry()));
    }

    function testSetPauserRegistyUnauthorized(IPauserRegistry newPauserRegistry, address notUnpauser) public fuzzedAddress(notUnpauser) {
        cheats.assume(notUnpauser != BionicPauserReg.unpauser());
        
        cheats.prank(notUnpauser);
        cheats.expectRevert(bytes("msg.sender is not permissioned as unpauser"));
        strategyManager.setPauserRegistry(newPauserRegistry);
    }
}
