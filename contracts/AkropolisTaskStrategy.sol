// SPDX-License-Identifier: AGPL-3.0
// Feel free to change the license, but this is what we use

// Feel free to change this version of Solidity. We support >=0.6.0 <0.7.0;
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

interface YieldFarming {
    function stakeInPool(uint256 _pid, uint256 _amount) public;
    function withdrawFromPool(uint256 _pid, uint256 _amount) public;
    function poolInfo(uint256 _pid) external view returns (address, uint256, uint256, uint256);
    function stakerInfo(uint256 _pid, address _user) external view returns (uint256, uint256);
}

// These are the core Yearn libraries
import {
    BaseStrategy,
    StrategyParams
} from "@yearnvaults/contracts/BaseStrategy.sol";
import {
    SafeERC20,
    SafeMath,
    IERC20,
    Address
} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

// Import interfaces for many popular DeFi projects, or add your own!
//import "../interfaces/<protocol>/<Interface>.sol";


contract AkropolisTaskStrategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public yieldfarming;
    address public reward;

    // uniswap router address
    address private constant uniswapRouter = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    // address of wrapped ethereum
    address private constant weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    address public router;
    uint256 public pid;

    address[] public path;

    event Cloned(address indexed clone);

    constructor(
        address _vault,
        address _yieldfarming,
        address _reward,
        address _router,
        uint256 _pid
    ) public BaseStrategy(_vault) {
        _initializeStrat(_yieldfarming, _reward, _router, _pid);
    }

    function initialize(
        address _vault,
        address _strategist,
        address _rewards,
        address _keeper,
        address _yiedfarming,
        address _reward,
        address _router,
        uint256 _pid
    ) external {
        _initialize(_vault, _strategist, _rewards, _keeper);
        _initializeStrat(_yiedfarming, _reward, _router, _pid);
    }

    /**
     * @notice
     *  Initializes the Strategy, this is called only once, when the
     *  contract is deployed.
     * @dev `_vault` should implement `VaultAPI`.
     * @param _vault The address of the Vault responsible for this Strategy.
     * @param _strategist The address to assign as `strategist`.
     * The strategist is able to change the reward address
     * @param _rewards  The address to use for pulling rewards.
     * @param _keeper The adddress of the _keeper. _keeper
     * can harvest and tend a strategy.
     */
    function _initializeStrat(
        address _yieldfarming,
        address _reward,
        address _router,
        uint256 _pid
    ) internal {
        require(router == address(0), "the yieldfarming has already been initialized");
        require(_router == uniswapRouter, "incorrect Router");

        maxReportDelay = 6300;
        profitFactor = 1500;
        debtThreshold = 1_000_000 * 1e18;
        yieldfarming = _yieldfarming;
        reward = _reward;
        router = _router;
        pid = _pid;
        

        (address poolToken, , ,) = YieldFarming(yieldfarming).poolInfo(pid);

        require(poolToken == address(want), "wrong pool id");

        want.safeApprove(_yiedfarming, uint256(-1));
        IERC20(reward).safeApprove(router, uint256(-1));
    }


    // clone a strategy
    function cloneStrategy(
        address _vault,
        address _yieldfarming,
        address _reward,
        address _router,
        uint256 _pid
    ) external returns (address nStrategy) {
        nStrategy = this.cloneStrategy(_vault, msg.sender, msg.sender, msg.sender, _yieldfarming, _reward, _router, _pid);
    }


    function cloneStrategy(address _vault, address _strategist, address rewards, address _keeper, address _yieldfarming, address _reward, address _router,uint256  _pid) external returns (address nStrategy) {
        // Copied from https://github.com/optionality/clone-factory/blob/master/contracts/CloneFactory.sol
        bytes20 addressBytes = bytes20(address(this));

        assembly {
            // EIP-1167 bytecode
            let clone_code := mload(0x40)
            mstore(
                clone_code,
                0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000
            )
            mstore(add(clone_code, 0x14), addressBytes)
            mstore(
                add(clone_code, 0x28),
                0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000
            )
        }

        AkropolisTaskStrategy(nStrategy).initialize(_vault, _strategist, _rewards, _keeper, _yiedfarming, _reward, _router, _pid);
        emit Cloned(newStrategy);
    }


    function setRouter(address _router) public onlyAuthorized {
        require(_router == uniswapRouter, "incorrect router address");
        router = _router;
        IERC20(reward).safeApprove(router, 0);
        IERC20(reward).safeApprove(router, uint256(-1));
    }

    function setPath(address[] calldata _path) public onlyGovernance {
        path = _path;
    }

    //Base contract methods 

    /**
     * @notice This Strategy's name.
     * @dev
     *  You can use this field to manage the "version" of this Strategy, e.g.
     *  `StrategySomethingOrOtherV1`. However, "API Version" is managed by
     *  `apiVersion()` function above.
     * @return This Strategy's name.
     */

    function name() external view override returns (string memory) {
        return "AkropolisTaskStrategy";
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        (uint256 amount, ) =
            YieldFarming(yieldfarming).stakerInfo(pid, address(this));
        return want.balanceOf(address(this)).add(amount);
    }

    /**
     * Perform any Strategy unwinding or other calls necessary to capture the
     * "free return" this Strategy has generated since the last time its core
     * position(s) were adjusted. Examples include unwrapping extra rewards.
     * This call is only used during "normal operation" of a Strategy, and
     * should be optimized to minimize losses as much as possible.
     *
     * This method returns any realized profits and/or realized losses
     * incurred, and should return the total amounts of profits/losses/debt
     * payments (in `want` tokens) for the Vault's accounting (e.g.
     * `want.balanceOf(this) >= _debtPayment + _profit - _loss`).
     *
     * `_debtOutstanding` will be 0 if the Strategy is not past the configured
     * debt limit, otherwise its value will be how far past the debt limit
     * the Strategy is. The Strategy's debt limit is configured in the Vault.
     *
     * NOTE: `_debtPayment` should be less than or equal to `_debtOutstanding`.
     *       It is okay for it to be less than `_debtOutstanding`, as that
     *       should only used as a guide for how much is left to pay back.
     *       Payments should be made to minimize loss from slippage, debt,
     *       withdrawal fees, etc.
     *
     * See `vault.debtOutstanding()`.
     */
    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        YieldFarming(yieldfarming).stakeInPool(pid, 0);

        _sell();

        uint256 assets = estimatedTotalAssets();
        uint256 wantBal = want.balanceOf(address(this));

        uint256 debt = vault.strategies(address(this)).totalDebt;

        if (assets > debt) {
            _debtPayment = _debtOutstanding;
            _profit = assets - debt;

            uint256 amountToFree = _profit.add(_debtPayment);

            if (amountToFree > 0 && wantBal < amountToFree) {
                liquidatePosition(amountToFree);

                uint256 newLoose = want.balanceOf(address(this));

                //if we dont have enough money adjust _debtOutstanding and only change profit if needed
                if (newLoose < amountToFree) {
                    if (_profit > newLoose) {
                        _profit = newLoose;
                        _debtPayment = 0;
                    } else {
                        _debtPayment = Math.min(
                            newLoose - _profit,
                            _debtPayment
                        );
                    }
                }
            }
        } else {
            //serious loss should never happen but if it does lets record it accurately
            _loss = debt - assets;
        }
    }


    /**
     * Perform any adjustments to the core position(s) of this Strategy given
     * what change the Vault made in the "investable capital" available to the
     * Strategy. Note that all "free capital" in the Strategy after the report
     * was made is available for reinvestment. Also note that this number
     * could be 0, and you should handle that scenario accordingly.
     *
     * See comments regarding `_debtOutstanding` on `prepareReturn()`.
     */

    function adjustPosition(uint256 _debtOutstanding) internal override {
        if (emergencyExit) {
            return;
        }

        uint256 wantBalance = want.balanceOf(address(this));
        YieldFarming(yieldfarming).stakeInPool(pid, wantBalance);
    }


     /**
     * Liquidate up to `_amountNeeded` of `want` of this strategy's positions,
     * irregardless of slippage. Any excess will be re-invested with `adjustPosition()`.
     * This function should return the amount of `want` tokens made available by the
     * liquidation. If there is a difference between them, `_loss` indicates whether the
     * difference is due to a realized loss, or if there is some other sitution at play
     * (e.g. locked funds) where the amount made available is less than what is needed.
     * This function is used during emergency exit instead of `prepareReturn()` to
     * liquidate all of the Strategy's positions back to the Vault.
     *
     * NOTE: The invariant `_liquidatedAmount + _loss <= _amountNeeded` should always be maintained
     */
    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        uint256 totalAssets = want.balanceOf(address(this));
        if (_amountNeeded > totalAssets) {
            uint256 amountToFree = _amountNeeded.sub(totalAssets);

            (uint256 amount, ) =
                YieldFarming(yieldfarming).stakerInfo(pid, address(this));
            if (amount < amountToFree) {
                amountToFree = amount;
            }
            if (amount > 0) {
                YieldFarming(yieldfarming).withdrawFromPool(pid, amountToFree);
            }

            _liquidatedAmount = want.balanceOf(address(this));
        } else {
            _liquidatedAmount = _amountNeeded;
        }
    }


    function prepareMigration(address _newStrategy) internal override {
        liquidatePosition(uint256(-1)); //withdraw all. does not matter if we ask for too much
        _sell();
    }

    function _sell() internal {

        uint256 rewardBal = IERC20(reward).balanceOf(address(this));
        if( rewardBal == 0){
            return;
        }


        if(path.length == 0){
            address[] memory tpath;
            if(address(want) != weth){
                tpath = new address[](3);
                tpath[2] = address(want);
            }else{
                tpath = new address[](2);
            }
            
            tpath[0] = address(reward);
            tpath[1] = weth;

            IUniswapV2Router02(router).swapExactTokensForTokens(rewardBal, uint256(0), tpath, address(this), now);
        }else{
            IUniswapV2Router02(router).swapExactTokensForTokens(rewardBal, uint256(0), path, address(this), now);
        }  

    }


    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    {}
}

