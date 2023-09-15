// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import "../contracts/interfaces/IDelegationManager.sol";
import "../contracts/core/DelegationManager.sol";

import "../contracts/interfaces/IETHPOSDeposit.sol";
import "../contracts/interfaces/IBeaconChainOracle.sol";
import "../contracts/interfaces/IVoteWeigher.sol";

import "../contracts/core/StrategyManager.sol";
import "../contracts/strategies/StrategyBase.sol";
import "../contracts/core/Slasher.sol";

import "../contracts/pods/BionicPod.sol";
import "../contracts/pods/BionicPodManager.sol";
import "../contracts/pods/DelayedWithdrawalRouter.sol";
import "../contracts/pods/BeaconChainOracle.sol";

import "../contracts/permissions/PauserRegistry.sol";


import "./utils/Operators.sol";

import "./mocks/LiquidStakingToken.sol";
import "./mocks/EmptyContract.sol";
import "./mocks/ETHDepositMock.sol";

// import "forge-std/Test.sol";

contract BionicDeployer is Operators {

    Vm cheats = Vm(HEVM_ADDRESS);

    // Bionic contracts
    ProxyAdmin public BionicProxyAdmin;
    PauserRegistry public BionicPauserReg;

    Slasher public slasher;
    DelegationManager public delegation;
    StrategyManager public strategyManager;
    BionicPodManager public bionicPodManager;
    IBionicPod public pod;
    IDelayedWithdrawalRouter public delayedWithdrawalRouter;
    IETHPOSDeposit public ethPOSDeposit;
    IBeacon public bionicPodBeacon;
    IBeaconChainOracle public beaconChainOracle;

    // testing/mock contracts
    IERC20 public bionicToken;
    IERC20 public weth;
    StrategyBase public wethStrat;
    StrategyBase public bionicStrat;
    StrategyBase public baseStrategyImplementation;
    EmptyContract public emptyContract;

    mapping(uint256 => IStrategy) public strategies;

    //from testing seed phrase
    bytes32 priv_key_0 = 0x1234567812345678123456781234567812345678123456781234567812345678;
    bytes32 priv_key_1 = 0x1234567812345678123456781234567812345698123456781234567812348976;

    //strategy indexes for undelegation (see commitUndelegation function)
    uint256[] public strategyIndexes;
    address[2] public stakers;
    address sample_registrant = cheats.addr(436364636);

    address[] public slashingContracts;

    uint256 wethInitialSupply = 10e50;
    uint256 public constant bionicTotalSupply = 1000e18;
    uint256 nonce = 69;
    uint256 public gasLimit = 750000;
    uint32 PARTIAL_WITHDRAWAL_FRAUD_PROOF_PERIOD_BLOCKS = 7 days / 12 seconds;
    uint256 REQUIRED_BALANCE_WEI = 31 ether;
    uint64 MAX_PARTIAL_WTIHDRAWAL_AMOUNT_GWEI = 1 ether / 1e9;
    uint64 MAX_VALIDATOR_BALANCE_GWEI = 32e9;
    uint64 EFFECTIVE_RESTAKED_BALANCE_OFFSET = 75e7;

    address pauser;
    address unpauser;
    address theMultiSig = address(420);
    address operator = address(0x4206904396bF2f8b173350ADdEc5007A52664293); //sk: e88d9d864d5d731226020c5d2f02b62a4ce2a4534a39c225d32d3db795f83319
    address acct_0 = cheats.addr(uint256(priv_key_0));
    address acct_1 = cheats.addr(uint256(priv_key_1));
    address _challenger = address(0x6966904396bF2f8b173350bCcec5007A52669873);
    address public BionicReputedMultisig = address(this);

    address BionicProxyAdminAddress;
    address BionicPauserRegAddress;
    address slasherAddress;
    address delegationAddress;
    address strategyManagerAddress;
    address bionicPodManagerAddress;
    address podAddress;
    address delayedWithdrawalRouterAddress;
    address bionicPodBeaconAddress;
    address beaconChainOracleAddress;
    address emptyContractAddress;
    address operationsMultisig;
    address executorMultisig;


    uint256 public initialBeaconChainOracleThreshold = 3;

    string internal goerliDeploymentConfig = vm.readFile("script/output/M1_deployment_goerli_2023_3_23.json");


    // addresses excluded from fuzzing due to abnormal behavior. TODO: @Sidu28 define this better and give it a clearer name
    mapping (address => bool) fuzzedAddressMapping;


    //ensures that a passed in address is not set to true in the fuzzedAddressMapping
    modifier fuzzedAddress(address addr) virtual {
        cheats.assume(fuzzedAddressMapping[addr] == false);
        _;
    }

    modifier cannotReinit() {
        cheats.expectRevert(bytes("Initializable: contract is already initialized"));
        _;
    }

    //performs basic deployment before each test
    // for fork tests run:  forge test -vv --fork-url https://eth-goerli.g.alchemy.com/v2/demo   -vv
    function setUp() public virtual {
        if(vm.envUint("CHAIN_ID") == 31337) {
            _deployBionicContractsLocal();

        }else if(vm.envUint("CHAIN_ID") == 5) {
            _deployBionicContractsGoerli();
        }

        fuzzedAddressMapping[address(0)] = true;
        fuzzedAddressMapping[address(BionicProxyAdmin)] = true;
        fuzzedAddressMapping[address(strategyManager)] = true;
        fuzzedAddressMapping[address(bionicPodManager)] = true;
        fuzzedAddressMapping[address(delegation)] = true;
        fuzzedAddressMapping[address(slasher)] = true;
    }

    function _deployBionicContractsGoerli() internal {
        _setAddresses(goerliDeploymentConfig);
        pauser = operationsMultisig;
        unpauser = executorMultisig;
        // deploy proxy admin for ability to upgrade proxy contracts
        BionicProxyAdmin = ProxyAdmin(BionicProxyAdminAddress);

        emptyContract = new EmptyContract();
        
        //deploy pauser registry
        BionicPauserReg = PauserRegistry(BionicPauserRegAddress);

        delegation = DelegationManager(delegationAddress);
        strategyManager = StrategyManager(strategyManagerAddress);
        slasher = Slasher(slasherAddress);
        bionicPodManager = BionicPodManager(bionicPodManagerAddress);
        delayedWithdrawalRouter = DelayedWithdrawalRouter(delayedWithdrawalRouterAddress);

        address[] memory initialOracleSignersArray = new address[](0);
        beaconChainOracle = new BeaconChainOracle(BionicReputedMultisig, initialBeaconChainOracleThreshold, initialOracleSignersArray);

        ethPOSDeposit = new ETHPOSDepositMock();
        pod = new BionicPod(ethPOSDeposit, delayedWithdrawalRouter, bionicPodManager, MAX_VALIDATOR_BALANCE_GWEI, EFFECTIVE_RESTAKED_BALANCE_OFFSET);

        bionicPodBeacon = new UpgradeableBeacon(address(pod));



        //simple ERC20 (**NOT** WETH-like!), used in a test strategy
        weth = new ERC20PresetFixedSupply(
            "weth",
            "WETH",
            wethInitialSupply,
            address(this)
        );

        // deploy StrategyBase contract implementation, then create upgradeable proxy that points to implementation and initialize it
        baseStrategyImplementation = new StrategyBase(strategyManager);
        wethStrat = StrategyBase(
            address(
                new TransparentUpgradeableProxy(
                    address(baseStrategyImplementation),
                    address(BionicProxyAdmin),
                    abi.encodeWithSelector(StrategyBase.initialize.selector, weth, BionicPauserReg)
                )
            )
        );

        bionicToken = new ERC20PresetFixedSupply(
            "bionic",
            "BIONIC",
            wethInitialSupply,
            address(this)
        );

        // deploy upgradeable proxy that points to StrategyBase implementation and initialize it
        bionicStrat = StrategyBase(
            address(
                new TransparentUpgradeableProxy(
                    address(baseStrategyImplementation),
                    address(BionicProxyAdmin),
                    abi.encodeWithSelector(StrategyBase.initialize.selector, bionicToken, BionicPauserReg)
                )
            )
        );

        stakers = [acct_0, acct_1];
    }

    function _deployBionicContractsLocal() internal {
        pauser = address(69);
        unpauser = address(489);
        // deploy proxy admin for ability to upgrade proxy contracts
        BionicProxyAdmin = new ProxyAdmin();

        //deploy pauser registry
        address[] memory pausers = new address[](1);
        pausers[0] = pauser;
        BionicPauserReg = new PauserRegistry(pausers, unpauser);

        /**
         * First, deploy upgradeable proxy contracts that **will point** to the implementations. Since the implementation contracts are
         * not yet deployed, we give these proxies an empty contract as the initial implementation, to act as if they have no code.
         */
        emptyContract = new EmptyContract();
        delegation = DelegationManager(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(BionicProxyAdmin), ""))
        );
        strategyManager = StrategyManager(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(BionicProxyAdmin), ""))
        );
        slasher = Slasher(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(BionicProxyAdmin), ""))
        );
        bionicPodManager = BionicPodManager(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(BionicProxyAdmin), ""))
        );
        delayedWithdrawalRouter = DelayedWithdrawalRouter(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(BionicProxyAdmin), ""))
        );

        address[] memory initialOracleSignersArray = new address[](0);
        beaconChainOracle = new BeaconChainOracle(BionicReputedMultisig, initialBeaconChainOracleThreshold, initialOracleSignersArray);

        ethPOSDeposit = new ETHPOSDepositMock();
        pod = new BionicPod(ethPOSDeposit, delayedWithdrawalRouter, bionicPodManager, MAX_VALIDATOR_BALANCE_GWEI, EFFECTIVE_RESTAKED_BALANCE_OFFSET);

        bionicPodBeacon = new UpgradeableBeacon(address(pod));

        // Second, deploy the *implementation* contracts, using the *proxy contracts* as inputs
        DelegationManager delegationImplementation = new DelegationManager(strategyManager, slasher);
        StrategyManager strategyManagerImplementation = new StrategyManager(delegation, bionicPodManager, slasher);
        Slasher slasherImplementation = new Slasher(strategyManager, delegation);
        BionicPodManager bionicPodManagerImplementation = new BionicPodManager(ethPOSDeposit, bionicPodBeacon, strategyManager, slasher);
        DelayedWithdrawalRouter delayedWithdrawalRouterImplementation = new DelayedWithdrawalRouter(bionicPodManager);

        // Third, upgrade the proxy contracts to use the correct implementation contracts and initialize them.
        BionicProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(delegation))),
            address(delegationImplementation),
            abi.encodeWithSelector(
                DelegationManager.initialize.selector,
                BionicReputedMultisig,
                BionicPauserReg,
                0/*initialPausedStatus*/
            )
        );
        BionicProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(strategyManager))),
            address(strategyManagerImplementation),
            abi.encodeWithSelector(
                StrategyManager.initialize.selector,
                BionicReputedMultisig,
                BionicReputedMultisig,
                BionicPauserReg,
                0/*initialPausedStatus*/,
                0/*withdrawalDelayBlocks*/
            )
        );
        BionicProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(slasher))),
            address(slasherImplementation),
            abi.encodeWithSelector(
                Slasher.initialize.selector,
                BionicReputedMultisig,
                BionicPauserReg,
                0/*initialPausedStatus*/
            )
        );
        BionicProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(bionicPodManager))),
            address(bionicPodManagerImplementation),
            abi.encodeWithSelector(
                BionicPodManager.initialize.selector,
                type(uint256).max, // maxPods
                beaconChainOracle,
                BionicReputedMultisig,
                BionicPauserReg,
                0/*initialPausedStatus*/
            )
        );
        uint256 initPausedStatus = 0;
        uint256 withdrawalDelayBlocks = PARTIAL_WITHDRAWAL_FRAUD_PROOF_PERIOD_BLOCKS;
        BionicProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(delayedWithdrawalRouter))),
            address(delayedWithdrawalRouterImplementation),
            abi.encodeWithSelector(DelayedWithdrawalRouter.initialize.selector,
            BionicReputedMultisig,
            BionicPauserReg,
            initPausedStatus,
            withdrawalDelayBlocks)
        );

        //simple ERC20 (**NOT** WETH-like!), used in a test strategy
        weth = new ERC20PresetFixedSupply(
            "weth",
            "WETH",
            wethInitialSupply,
            address(this)
        );

        // deploy StrategyBase contract implementation, then create upgradeable proxy that points to implementation and initialize it
        baseStrategyImplementation = new StrategyBase(strategyManager);
        wethStrat = StrategyBase(
            address(
                new TransparentUpgradeableProxy(
                    address(baseStrategyImplementation),
                    address(BionicProxyAdmin),
                    abi.encodeWithSelector(StrategyBase.initialize.selector, weth, BionicPauserReg)
                )
            )
        );

        bionicToken = new ERC20PresetFixedSupply(
            "bionic",
            "BIONIC",
            wethInitialSupply,
            address(this)
        );

        // deploy upgradeable proxy that points to StrategyBase implementation and initialize it
        bionicStrat = StrategyBase(
            address(
                new TransparentUpgradeableProxy(
                    address(baseStrategyImplementation),
                    address(BionicProxyAdmin),
                    abi.encodeWithSelector(StrategyBase.initialize.selector, bionicToken, BionicPauserReg)
                )
            )
        );

        stakers = [acct_0, acct_1];
    }

    function _setAddresses(string memory config) internal {
        BionicProxyAdminAddress = stdJson.readAddress(config, ".addresses.BionicProxyAdmin");   
        BionicPauserRegAddress = stdJson.readAddress(config, ".addresses.BionicPauserReg");
        delegationAddress = stdJson.readAddress(config, ".addresses.delegation");
        strategyManagerAddress = stdJson.readAddress(config, ".addresses.strategyManager");
        slasherAddress = stdJson.readAddress(config, ".addresses.slasher");
        bionicPodManagerAddress = stdJson.readAddress(config, ".addresses.bionicPodManager"); 
        delayedWithdrawalRouterAddress = stdJson.readAddress(config, ".addresses.delayedWithdrawalRouter");
        emptyContractAddress = stdJson.readAddress(config, ".addresses.emptyContract");
        operationsMultisig = stdJson.readAddress(config, ".parameters.operationsMultisig");
        executorMultisig = stdJson.readAddress(config, ".parameters.executorMultisig");
    }
    
}