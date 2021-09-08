//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

import {Utils88mph} from "./utils/Utils88mph.sol";
import {AirswapUtils} from "./utils/AirswapUtils.sol";
import {RollOverBase} from "./utils/RollOverBase.sol";
import {GammaUtils} from "./utils/GammaUtils.sol";
import {ZeroXUtils} from "./utils/ZeroXUtils.sol";
import {SwapTypes} from "./libraries/SwapTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

import {IController} from "./interfaces/IController.sol";
import {IAction} from "./interfaces/IAction.sol";
import {IOToken} from "./interfaces/IOToken.sol";

import "hardhat/console.sol";

contract StructuredProduct is Utils88mph, ZeroXUtils, RollOverBase, GammaUtils {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    bool vaultClosed;

    /// @dev 100%
    uint256 public constant BASE = 10000;

    /// @dev amount of assets locked in Opyn
    uint256 public lockedAsset;

    /// @dev time at which the last rollover was called
    uint256 public rolloverTime;

    uint256 public amountDepositedIn88mph;

    uint256 public minPeriod;

    uint256 public maxLossPercent;

    /// @dev address of the vault 
    address public immutable vault;

    /// @dev address of the ERC20 asset. Do not use non-ERC20s
    address public immutable asset;

    Position position = Position.Meh;

    enum Position{Meh, Long, Short}




    /** 
    * @notice constructor 
    * @param _vault the address of the vault contract
    * @param _asset address of the ERC20 asset
    * @param 
    * @param 
    * @param 
    * @param _airswap address of airswap swap contract 
    * @param _controller address of Opyn controller contract
    */
    constructor(
      address _vault,
      address _asset, // weth
      address _airswap,
      address _controller,
      address _zcb
    ) {
      vault = _vault;
      asset = _asset;

      // enable vault to take all the asset back and re-distribute.
      IERC20(_asset).safeApprove(_vault, uint256(-1));

      _initGammaUtil(_controller);

      // enable pool contract to pull asset from this contract to mint options.
      address pool = controller.pool();

      address whitelist = controller.whitelist();

      _initSwapContract(_airswap);

      // assuming asset is weth
      _init88mphUtils(_zcb);

      _initRollOverBase(whitelist);
      __Ownable_init();
    }

    modifier onlyVault() {
      require(msg.sender == vault, "!VAULT");

      _;
    }

    function _setPosition(Position _position) internal {
        require(position.Meh);
        position = _position;
    }
    function _setMaxLoss(uint256 _maxLossPercent) internal {
        maxLossPercent = _maxLossPercent;
    }

    /**
    * @notice returns the net worth of this strategy = current balance of the action + collateral deposited into Opyn's vault. 
    * @dev For a more realtime tracking of value, we reccomend calculating the current value as: 
    * currentValue = balance + collateral - (numOptions * cashVal), where: 
    * balance = current balance in the action
    * collateral = collateral deposited into Opyn's vault 
    * numOptions = number of options sold
    * cashVal = cash value of 1 option sold (for puts: Strike - Current Underlying Price, for calls: Current Underlying Price - Strike)
    */
    function currentValue() external view override returns (uint256) {
      uint256 assetBalance = IERC20(asset).balanceOf(address(this));
      return assetBalance.add(lockedAsset);
      // todo: consider cETH value that's used as collateral
    }

    /**
    * @notice the function that the vault will call when the new round is starting. Once this is called, the funds will be sent from the vault to this action. 
    * @dev this does NOT automatically mint options and sell them. This merely receives funds. Before this function is called, the owner should have called 
    * `commitOToken` to decide on what Otoken is being sold. This function can only be called after the commitment period has passed since the call to `commitOToken`.
    * Once this has been called, the owner should call `borrowMintAndTradeOTC`. If the owner doesn't mint and sell the options within 1 day after rollover has been 
    * called, someone can call closePosition and transfer the funds back to the vault. If that happens, the owner needs to commit to a new otoken and call rollover again. 
    */
    function rolloverPosition() external override onlyVault {
      _rollOverNextOTokenAndActivate(); // this function can only be called when the action is `Committed`
      rolloverTime = block.timestamp;
    }

    /**
    * @notice the function will return when someone can close a position. 1 day after rollover,
    * if the option wasn't sold, anyone can close the position and send funds back to the vault. 
    */
    function canClosePosition() public view returns (bool) {
      if (otoken != address(0) && lockedAsset != 0) {
        return _canSettleVault();
      }
      return block.timestamp > rolloverTime + 1 days;
    }
    

    /**
    * @notice the function that the vault will call when the round is over. This will settle the vault in Opyn, repay the usdc debt in Compound
    * and withdraw WETH supplied to Compound. There are 2 main risks involved in this strategy:
    * 1. If the option expired OTM, then all the collateral is returned to this action. If not, some portion of the collateral is deducted 
    * by the Opyn system. 
    * 2. If the ETH price fluctuates a lot, the position in Compound could get liquidated in which case all the collateral may not be 
    * returned even if the option expires OTM. 
    * @dev this can be called after 1 day rollover was called if no options have been sold OR if the sold options expired. 
    */
    function closePosition() external override onlyVault {
      require(_zcbRedeemable());
      if (position.Long){
          require(canClosePosition(), "Cannot close position");
          if (_canSettleVault()) {
            // get back usdc from settlement
            _settleGammaVault();
            lockedAsset = 0;
          }
      } 
      if (position.Short){
          require(otoken[0] != address(0), "position is closed");
          require(_canExerciseOption(), "options not expired");
          if(__isOtokenWorthy(otoken[0])){
            _redeemoptions(otoken[0]);
          }
          if(__isOtokenWorthy(otoken[1])){
            _redeemoptions(otoken[1]);
          }
      }
      position = Position.Meh;
      // set action state.
      _setActionIdle();
    }

    /**
    * @notice checks if the current vault can be settled
    */
    function _canSettleVault() internal view returns (bool) {
       require(position.Short);
       if (lockedAsset != 0 && otoken[0] != address(0)) {
           return controller.isSettlementAllowed(otoken[0]);
      }
      return false;
    }

    function _canExerciseOption() internal view returns (bool) {
      require(position.Long, "");
      if(otoken[0] != address(0) && otoken[1] == address(0)){
          return otoken[0].expiryTimestamp() < block.timestamp ;
      }else if(otoken[0] != address(0) && otoken[1] != address(0)){
          return otoken[0].expiryTimestamp() < block.timestamp && otoken[1].expiryTimestamp() < block.timestamp ;
      } else {
          return false;
      }
    }

    function __isOtokenWorthy(address _otoken) internal {
        require (_otoken != address(0));
        return controller.getPayout(_otoken, IERC20(_otoken).balanceOf(address(this))) > 0;
    }

    function longViaAirSwap(
        SwapTypes.Order[] memory _order
    ) external {
        require(position == Position.Long);
        _tradeAirSwapOTC(_order);
    }

    function shortViaAirSwap(
        uint256[] _collateralAmount,
        uint256[] _otokenAmount,
        SwapTypes.Order[] memory _order
    ){
        require(position == Position.Long);

        for(uint i = 0; i < _order.length; i++){
            require(_collateralAmount[i].mul(MIN_PROFITS).div(BASE) <= _order[i].signer.amount, "Need minimum option premium");
            lockedAsset = lockedAsset.add(_collateralAmount[i]);

            // mint otoken using the util function
            _mintOTokens(asset, _collateralAmount[i], otoken[i], _otokenAmount[i]);
        } 
        _tradeAirSwapOTC(_order);
    }

    function _tradeAirSwapOTC(
        SwapTypes.Order[] memory _order
    ) internal onlyOwner onlyActivated {
        require(_order.length > 0 && _order.length <= 2);
        for(uint i = 0; i < _order.length; i++){
            require(_order[i].sender.wallet == address(this), "!Sender");
            require(_order[i].sender.token == otoken, "Can only sell otoken");
            require(_order[i].signer.token == asset, "Can only sell for asset");

            fillAirswapOrder(_order);
        }  
    }



    function mintZcb(uint256 deposit_amt, Position _position) external {

        uint ir = _getInterestRate(deposit_amt);
        deposit_amt = deposit_amt.sub(deposit_amt.mul(ir.add(maxLossPercent).div(100)));
        uint amt_minted = _mintZcb(deposit_amt);
        zcb_minted += amt_minted;
    }

    function redeemoptions(address _otoken) external {
        _redeemOTokens(_otoken, IERC20(_otoken).balanceOf(address(this)));
    }

    function _zcbRedeemable() internal {
      return block.timestamp > zcb.maturationTimestamp();
    }







}
