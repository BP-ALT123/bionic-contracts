// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/Create2.sol";
import "./BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";

import "../../contracts/interfaces/IStrategyManager.sol";
import "../../contracts/interfaces/IDelegationManager.sol";
import "../../contracts/interfaces/IBionicPodManager.sol";
import "../../contracts/interfaces/IETHPOSDeposit.sol";
import "../../contracts/interfaces/IBionicPod.sol";
import "../../contracts/interfaces/IBeaconChainOracle.sol";

// import "forge-std/Test.sol";

/**
 * @title The contract used for creating and managing BionicPods
 * @author Layr Labs, Inc.
 * @notice Terms of Service: https://docs.bionicprotocol.com/overview/terms-of-service
 * @notice The main functionalities are:
 * - creating BionicPods
 * - staking for new validators on BionicPods
 * - keeping track of the balances of all validators of BionicPods, and their stake in Bionic
 * - withdrawing eth when withdrawals are initiated
 */
contract BionicPodManagerNEW is Initializable, OwnableUpgradeable, IBionicPodManager {
    function getBeaconChainStateRoot(uint64 slot) external view returns(bytes32) {}

    function pause(uint256 newPausedStatus) external {}    

    function pauseAll() external {}

    function paused() external view returns (uint256) {}

    function paused(uint8 index) external view returns (bool) {}

    function setPauserRegistry(IPauserRegistry newPauserRegistry) external {}

    function pauserRegistry() external view returns (IPauserRegistry) {}

    function unpause(uint256 newPausedStatus) external {}

    function ownerToPod(address podOwner) external view returns(IBionicPod) {}


    //TODO: change this to constant in prod
    IETHPOSDeposit internal immutable ethPOS;
    /// @notice Beacon proxy to which the BionicPods point
    IBeacon public immutable bionicPodBeacon;

    /// @notice Bionic's StrategyManager contract
    IStrategyManager public immutable strategyManager;

    /// @notice Bionic's Slasher contract
    ISlasher public immutable slasher;

    /// @notice Oracle contract that provides updates to the beacon chain's state
    IBeaconChainOracle public beaconChainOracle;
    
    /// @notice Pod owner to the amount of penalties they have paid that are still in this contract
    mapping(address => uint256) public podOwnerToUnwithdrawnPaidPenalties;

    /// @notice Emitted to notify the update of the beaconChainOracle address
    event BeaconOracleUpdated(address indexed newOracleAddress);

    /// @notice Emitted to notify the deployment of an BionicPod
    event PodDeployed(address indexed bionicPod, address indexed podOwner);

    /// @notice Emitted to notify a deposit of beacon chain ETH recorded in the  manager
    event BeaconChainETHDeposited(address indexed podOwner, uint256 amount);

    /// @notice Emitted when an BionicPod pays penalties, on behalf of its owner
    event PenaltiesPaid(address indexed podOwner, uint256 amountPaid);

    modifier onlyBionicPod(address podOwner) {
        require(address(getPod(podOwner)) == msg.sender, "BionicPodManager.onlyBionicPod: not a pod");
        _;
    }

    modifier onlyStrategyManager {
        require(msg.sender == address(strategyManager), "BionicPodManager.onlyStrategyManager: not strategyManager");
        _;
    }

    constructor(IETHPOSDeposit _ethPOS, IBeacon _bionicPodBeacon, IStrategyManager _strategyManager, ISlasher _slasher) {
        ethPOS = _ethPOS;
        bionicPodBeacon = _bionicPodBeacon;
        strategyManager = _strategyManager;
        slasher = _slasher;
        _disableInitializers();
        
    }

    function initialize(IBeaconChainOracle _beaconChainOracle, address initialOwner) public initializer {
        _updateBeaconChainOracle(_beaconChainOracle);
        _transferOwnership(initialOwner);
    }

    /**
     * @notice Creates an BionicPod for the sender.
     * @dev Function will revert if the `msg.sender` already has an BionicPod.
     */
    function createPod() external {
        require(!hasPod(msg.sender), "BionicPodManager.createPod: Sender already has a pod");
        //deploy a pod if the sender doesn't have one already
        IBionicPod pod = _deployPod();

        emit PodDeployed(address(pod), msg.sender);
    }

    /**
     * @notice Stakes for a new beacon chain validator on the sender's BionicPod. 
     * Also creates an BionicPod for the sender if they don't have one already.
     * @param pubkey The 48 bytes public key of the beacon chain validator.
     * @param signature The validator's signature of the deposit data.
     * @param depositDataRoot The root/hash of the deposit data for the validator's deposit.
     */
    function stake(bytes calldata pubkey, bytes calldata signature, bytes32 depositDataRoot) external payable {
        IBionicPod pod = getPod(msg.sender);
        if(!hasPod(msg.sender)) {
            //deploy a pod if the sender doesn't have one already
            pod = _deployPod();
        }
        pod.stake{value: msg.value}(pubkey, signature, depositDataRoot);
    }

    /**
     * @notice Deposits/Restakes beacon chain ETH in Bionic on behalf of the owner of an BionicPod.
     * @param podOwner The owner of the pod whose balance must be deposited.
     * @param amount The amount of ETH to 'deposit' (i.e. be credited to the podOwner).
     * @dev Callable only by the podOwner's BionicPod contract.
     */
    function restakeBeaconChainETH(address podOwner, uint256 amount) external onlyBionicPod(podOwner) {
        strategyManager.depositBeaconChainETH(podOwner, amount);
        emit BeaconChainETHDeposited(podOwner, amount);
    }

    /**
     * @notice Removes beacon chain ETH from Bionic on behalf of the owner of an BionicPod, when the
     *         balance of a validator is lower than how much stake they have committed to Bionic
     * @param podOwner The owner of the pod whose balance must be removed.
     * @param sharesDelta is the change in podOwner's beaconChainETHStrategy shares
     * @dev Callable only by the podOwner's BionicPod contract.
     */
     function recordBeaconChainETHBalanceUpdate(address podOwner, uint256 beaconChainETHStrategyIndex, int256 sharesDelta) external onlyBionicPod(podOwner) {
        strategyManager.recordBeaconChainETHBalanceUpdate(podOwner, beaconChainETHStrategyIndex, sharesDelta);
    }

    /**
     * @notice Withdraws ETH from an BionicPod. The ETH must have first been withdrawn from the beacon chain.
     * @param podOwner The owner of the pod whose balance must be withdrawn.
     * @param recipient The recipient of the withdrawn ETH.
     * @param amount The amount of ETH to withdraw.
     * @dev Callable only by the StrategyManager contract.
     */
    function withdrawRestakedBeaconChainETH(address podOwner, address recipient, uint256 amount) external onlyStrategyManager {
        getPod(podOwner).withdrawRestakedBeaconChainETH(recipient, amount);
    }

    /**
     * @notice Records receiving ETH from the `PodOwner`'s BionicPod, paid in order to fullfill the BionicPod's penalties to Bionic
     * @param podOwner The owner of the pod whose balance is being sent.
     * @dev Callable only by the podOwner's BionicPod contract.
     */
    function payPenalties(address podOwner) external payable onlyBionicPod(podOwner) {
        podOwnerToUnwithdrawnPaidPenalties[podOwner] += msg.value;
        emit PenaltiesPaid(podOwner, msg.value);
    }

    /**
     * @notice Withdraws paid penalties of the `podOwner`'s BionicPod, to the `recipient` address
     * @param recipient The recipient of withdrawn ETH.
     * @param amount The amount of ETH to withdraw.
     * @dev Callable only by the strategyManager.owner().
     */
    function withdrawPenalties(address podOwner, address recipient, uint256 amount) external {
        require(msg.sender == Ownable(address(strategyManager)).owner(), "BionicPods.withdrawPenalties: only strategyManager owner");
        podOwnerToUnwithdrawnPaidPenalties[podOwner] -= amount;
        // transfer penalties from pod to `recipient`
        Address.sendValue(payable(recipient), amount);
    }

    /**
     * @notice Updates the oracle contract that provides the beacon chain state root
     * @param newBeaconChainOracle is the new oracle contract being pointed to
     * @dev Callable only by the owner of this contract (i.e. governance)
     */
    function updateBeaconChainOracle(IBeaconChainOracle newBeaconChainOracle) external onlyOwner {
        _updateBeaconChainOracle(newBeaconChainOracle);
    }


    // INTERNAL FUNCTIONS
    function _deployPod() internal returns (IBionicPod) {
        IBionicPod pod = 
            IBionicPod(
                Create2.deploy(
                    0, 
                    bytes32(uint256(uint160(msg.sender))), 
                    // set the beacon address to the bionicPodBeacon and initialize it
                    abi.encodePacked(
                        type(BeaconProxyNEW).creationCode, 
                        abi.encode(bionicPodBeacon, abi.encodeWithSelector(IBionicPod.initialize.selector, IBionicPodManager(address(this)), msg.sender))
                    )
                )
            );
        return pod;
    }

    function _updateBeaconChainOracle(IBeaconChainOracle newBeaconChainOracle) internal {
        beaconChainOracle = newBeaconChainOracle;
        emit BeaconOracleUpdated(address(newBeaconChainOracle));
    }

    // VIEW FUNCTIONS
    /// @notice Returns the address of the `podOwner`'s BionicPod (whether it is deployed yet or not).
    function getPod(address podOwner) public view returns (IBionicPod) {
        return IBionicPod(
                Create2.computeAddress(
                    bytes32(uint256(uint160(podOwner))), //salt
                    keccak256(abi.encodePacked(
                        type(BeaconProxyNEW).creationCode, 
                        abi.encode(bionicPodBeacon, abi.encodeWithSelector(IBionicPod.initialize.selector, IBionicPodManager(address(this)), podOwner))
                    )) //bytecode
                ));
    }

    /// @notice Returns 'true' if the `podOwner` has created an BionicPod, and 'false' otherwise.
    function hasPod(address podOwner) public view returns (bool) {
        return address(getPod(podOwner)).code.length > 0;
    }

    function getBeaconChainStateRoot() external view returns(bytes32) {
        // return beaconChainOracle.getBeaconChainStateRoot();
    }

    function decrementWithdrawableRestakedExecutionLayerGwei(address podOwner, uint256 amountWei) external{}

    function incrementWithdrawableRestakedExecutionLayerGwei(address podOwner, uint256 amountWei) external{}

}