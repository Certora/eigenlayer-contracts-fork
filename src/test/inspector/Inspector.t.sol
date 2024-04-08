// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/utils/Strings.sol";

import "script/utils/ExistingDeploymentParser.sol";

// import "src/test/integration/users/User.t.sol";
import "src/test/inspector/Target.t.sol";
import "src/test/inspector/PrintUtils.t.sol";
import "src/test/inspector/TimelockHelper.t.sol";

contract Inspector is ExistingDeploymentParser, PrintUtils, ITargetDeployer {

    using Strings for *;

    string constant MAINNET_DEPLOY_INFO_PATH = "script/configs/mainnet/Mainnet_current_deployment.config.json";

    Vm cheats = Vm(HEVM_ADDRESS);

    bool public isUpgraded = false;

    uint targetNonce;

    function setUp() public {
        // Fork mainnet at the latest block and fetch contracts
        cheats.createSelectFork(cheats.rpcUrl("mainnet"));
        _parseDeployedContracts(MAINNET_DEPLOY_INFO_PATH);
    }

    function test_UpgradeStatus() public {
        _logSection("Checking M2 Upgrade Status");

        bool isQueued = _isUpgradeQueued();

        if (!isQueued) {
            _logGreen("Upgrade status", "complete!");
            isUpgraded = true;
        } else {
            _logYellow("Upgrade status", "queued");
        }

        _log("Inspecting contracts");

        inspect(delegationManager);
        inspect(strategyManager);
        inspect(eigenPodManager);
    }

    function test_M2Upgrade() public {
        inspect(delegationManager);
        inspect(strategyManager);
        inspect(eigenPodManager);

        _upgradeMainnet();

        inspect(delegationManager);
        inspect(strategyManager);
        inspect(eigenPodManager);
    }

    function test_MigrateM1Withdrawal() public {
        // Some dude from etherscan hehe
        Target t = _target(0xf151FeC20505fAf3E6a7E6AA1654e53e23b42CEE);

        // Briefly allow deposits so we can queue a withdrawal in the strategyManager
        _unpauseStrategyManager();
        t.depositIntoEigenlayer();
        _pauseStrategyManager();
        inspect(t);

        // Queue withdrawals in the m1 contracts
        t.queueWithdrawals_M1();
        inspect(t);

        // Upgrade to m2
        _upgradeMainnet();
        
        // Migrate m1 withdrawals to delegationManager
        t.migrateM1Withdrawals();
        inspect(t);
    }

    function test_MigrateEigenPod() public {
        // Some dude from etherscan hehe
        Target t = _target(0xf151FeC20505fAf3E6a7E6AA1654e53e23b42CEE);
        inspect(t);

        // Deploy a pod for the user
        if (!t.hasEigenPod()) {
            t.deployEigenPod();
            inspect(t);
        }

        // Send a little ETH to the pod
        _fundPod(t.pod());
        inspect(t);

        // Upgrade to m2
        _upgradeMainnet();
        
        t.activateRestaking();
        inspect(t);
    }

    /// Base inspect methods

    function inspect(address a) internal returns (Target) {
        // if (isProtocolContract[a]) {}

        // Etch Target contract to access helper methods
        Target t = _target(a);
        inspect(t);
        return t;
    }

    function inspect(Target t) internal {
        t.logBasicInfo();
        _log("");
    }

    function inspect(StrategyManager sm) internal {
        _logHeader("StrategyManager", address(sm));

        address impl = eigenLayerProxyAdmin.getProxyImplementation(TransparentUpgradeableProxy(payable(address(sm))));

        _logDim("Implementation", impl);
        _log("Pause status", sm.paused());
        _log("- PAUSED_DEPOSITS", sm.paused(0));
        _log("");
    }

    function inspect(EigenPodManager em) internal {
        _logHeader("EigenPodManager", address(em));

        address impl = eigenLayerProxyAdmin.getProxyImplementation(TransparentUpgradeableProxy(payable(address(em))));
        _logDim("Implementation", impl);

        address beaconImpl = em.eigenPodBeacon().implementation();
        _logDim("Beacon Implementation", beaconImpl);
        _logDim("Beacon Chain Oracle", address(em.beaconChainOracle()));

        _log("Pause status", em.paused());
        _log("- PAUSED_NEW_EIGENPODS", em.paused(0));
        _log("- PAUSED_WITHDRAW_RESTAKED_ETH", em.paused(1));
        _log("- PAUSED_EIGENPODS_VERIFY_CREDENTIALS", em.paused(2));
        _log("- PAUSED_EIGENPODS_VERIFY_BALANCE_UPDATE", em.paused(3));
        _log("- PAUSED_EIGENPODS_VERIFY_WITHDRAWAL", em.paused(4));
        _log("- PAUSED_NON_PROOF_WITHDRAWALS", em.paused(5));

        if (isUpgraded) {
            _logSection("New Variables in M2");
            _log("EigenPod - Max Balance (Gwei)", EigenPod(payable(beaconImpl)).MAX_RESTAKED_BALANCE_GWEI_PER_VALIDATOR());
            _log("EigenPod - Genesis Timestamp", EigenPod(payable(beaconImpl)).GENESIS_TIME());
            _log("EPManager - Deneb Timestamp", em.denebForkTimestamp());
        }

        _log("");
    }

    function inspect(DelegationManager dm) internal {
        _logHeader("DelegationManager", address(dm));

        address impl = eigenLayerProxyAdmin.getProxyImplementation(TransparentUpgradeableProxy(payable(address(dm))));
        _logDim("Implementation", impl);

        _log("Pause status", dm.paused());
        _log("- PAUSED_NEW_DELEGATION", dm.paused(0));
        _log("- PAUSED_ENTER_WITHDRAWAL_QUEUE", dm.paused(1));
        _log("- PAUSED_EXIT_WITHDRAWAL_QUEUE", dm.paused(2));

        if (isUpgraded) {
            _logSection("New Variables in M2");
            uint minWithdrawalDelayBlocks = dm.minWithdrawalDelayBlocks();
            _log("minWithdrawalDelay (blocks)", minWithdrawalDelayBlocks);
            _log("minWithdrawalDelay (days)", (minWithdrawalDelayBlocks * 12) / 1 days);
        }

        _log("");
    }

    function whitelistedStrategies() external view returns (StrategyBase[] memory) {
        return deployedStrategyArray;
    }

    function _target(address a) internal returns (Target) {
        string memory name = _isEOA(a) ?
            string.concat("Unknown-Ape-", targetNonce.toString()) :
            string.concat("Unknown-Contract-", targetNonce.toString());

        targetNonce++;

        cheats.allowCheatcodes(a);

        Target dummy = new Target();
        cheats.etch(a, address(dummy).code);
        Target t = Target(a);

        t.init(name, deployedStrategyArray);

        return t;
    }

    function _unpauseAll() internal {
        address unpauser = eigenLayerPauserReg.unpauser();
        _log("Pranking unpauser", unpauser);

        cheats.startPrank(unpauser);

        strategyManager.unpause(0);
        eigenPodManager.unpause(0);
        delegationManager.unpause(0);

        cheats.stopPrank();
        _log("Unpaused all contracts!");
        _log("");
    }

    function _unpauseStrategyManager() internal {
        address unpauser = eigenLayerPauserReg.unpauser();
        _log("Pranking unpauser", unpauser);

        cheats.startPrank(unpauser);

        strategyManager.unpause(0);

        cheats.stopPrank();
        _log("Unpaused strategyManager!");
        _log("");
    }

    function _pauseStrategyManager() internal {
        _log("Pranking pauserMultisig", pauserMultisig);

        cheats.startPrank(pauserMultisig);

        strategyManager.pause(1);

        cheats.stopPrank();
        _log("Paused strategyManager!");
        _log("");
    }

    function _fundPod(IEigenPod pod) internal {
        address _pod = address(pod);
        _log("Minting 1 eth to pod", _pod);
        cheats.deal(_pod, 1 ether);
        _log("");
    }

    function _isEOA(address a) internal view returns (bool b) {
        assembly { b := iszero(extcodesize(a)) }
    }

    function _upgradeMainnet() internal {
        _logSection("Checking Queued M2 Upgrade");

        if (_isUpgradeQueued()) {
            if (block.timestamp < TimelockHelper.ETA) {
                _log("Warping to ETA");
                cheats.warp(TimelockHelper.ETA);
            } else {
                _logGreen("Upgrade is executable (ETA)");
            }

            _logAction("operationsMultisig", "timelock.executeTransaction");
            cheats.prank(operationsMultisig);
            ITimelock(timelock).executeTransaction({
                target: executorMultisig,
                value: 0,
                signature: "",
                data: TimelockHelper.EXEC_DATA,
                eta: TimelockHelper.ETA
            });
        } else {
            _log("Already upgraded to M2!");
        }

        isUpgraded = true;
        
        _log("");
    }

    function _isUpgradeQueued() internal returns (bool) {

        bytes32 queuedTxn = keccak256(abi.encode(
            executorMultisig,
            uint(0),
            "",
            TimelockHelper.EXEC_DATA,
            TimelockHelper.ETA
        ));

        _log("Checking queued transaction hash", queuedTxn);
        _log("- ETA", TimelockHelper.ETA);
        bool isQueued = ITimelock(timelock).queuedTransactions(queuedTxn);
        _log("- Upgrade is queued", isQueued);

        return isQueued;
    }
}