// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

/**
 * @title Constants shared between 'BionicPod' and 'BionicPodManager' contracts.
 * @author Layr Labs, Inc.
 * @notice Terms of Service: https://docs.bionicprotocol.com/overview/terms-of-service
 */
abstract contract BionicPodPausingConstants {
    /// @notice Index for flag that pauses creation of new BionicPods when set. See BionicPodManager code for details.
    uint8 internal constant PAUSED_NEW_BIONICPODS = 0;
    /// @notice Index for flag that pauses the `withdrawRestakedBeaconChainETH` function *of the BionicPodManager* when set. See BionicPodManager code for details.
    uint8 internal constant PAUSED_WITHDRAW_RESTAKED_ETH = 1;

    /// @notice Index for flag that pauses the `verifyCorrectWithdrawalCredentials` function *of the BionicPods* when set. see BionicPod code for details.
    uint8 internal constant PAUSED_BIONICPODS_VERIFY_CREDENTIALS = 2;
    /// @notice Index for flag that pauses the `verifyBalanceUpdate` function *of the BionicPods* when set. see BionicPod code for details.
    uint8 internal constant PAUSED_BIONICPODS_VERIFY_BALANCE_UPDATE = 3;
    /// @notice Index for flag that pauses the `verifyBeaconChainFullWithdrawal` function *of the BionicPods* when set. see BionicPod code for details.
    uint8 internal constant PAUSED_BIONICPODS_VERIFY_WITHDRAWAL = 4;
}