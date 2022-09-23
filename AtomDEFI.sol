//SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

pragma solidity ^0.8.8;

interface DexFactory {
    function createPair(address tokenA, address tokenB)
        external
        returns (address pair);
}

interface DexRouter {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        returns (
            uint256 amountToken,
            uint256 amountETH,
            uint256 liquidity
        );

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

contract AtomDEFI is ERC20, Ownable {
    // decimals are 18, total supply is 1, 000, 000
    uint256 private constant _totalSupply = 1e6 * 1e18;

    DexRouter public s_dexRouter;
    address public s_pairAddress;

    // Tax Settings:
    // Buy + Sell Tax = 16%
    // whitelisted wallets don't have to pay tax
    //Buy Taxes
    uint256 public s_stakingVaultTax = 6;
    uint256 public s_liquidityTax = 1;
    uint256 public s_developmentTax = 1;
    uint256 public s_totalFee = 8;

    uint256 public b_stakingVaultTax = 6;
    uint256 public b_liquidityTax = 1;
    uint256 public b_developmentTax = 1;
    uint256 public b_totalFee = 8;

    uint256 private StakingShare = s_stakingVaultTax + b_stakingVaultTax;
    uint256 private LiquidityShare = s_liquidityTax + b_liquidityTax;
    uint256 private DevelopmentShare = s_developmentTax + b_developmentTax;
    uint256 private TotalTaxes = s_totalFee + b_totalFee;

    mapping(address => bool) private s_whitelisted;

    // swapping
    uint256 public s_swapTokensAtAmount = _totalSupply / 1000000; //after 0.001% of total supply, swap them
    bool public s_swapAndLiquifyEnabled = true;
    bool public s_isSwapping = false;

    // This are tax receiver wallets
    // i used test wallets here, change them to your target wallets
    address public s_stakingVault = 0x6BAFAea58B24266D6C5BDA39698155D47b2305e9;
    address public s_development = 0xeB116F63fE8543BFF2aF0B550CE8A6146D63d801;

    //Events
    event FeesChanged(
        uint256 indexed stakingVault,
        uint256 indexed dvelopment,
        uint256 indexed liquidity
    );
    event DevelopmentWalletChangd(address indexed newWallet);
    event StakingValutChanged(address indexed newWallet);
    event MinimumSwapAmountChaned(uint256 indexed newMin);
    event SwapAndLiuqifityStatusChanged(bool indexed status);
    event WhitelistAction(address indexed wallet, bool indexed status);
    event DexRouterUpdated(address indexed newDex, address indexed newLP);

    //0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0 is pancake router at testing environment
    constructor() ERC20("Atom Defi", "AD") {
        /**
         * @IMPORTANT : Change dex router to 0x10ED43C718714eb63d5aA57B78B54704E256024E when you decided to deploy on mainnet
         */
        s_dexRouter = DexRouter(0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0);
        s_pairAddress = DexFactory(s_dexRouter.factory()).createPair(
            address(this),
            s_dexRouter.WETH()
        );
        // do not whitelist liquidity pool, otherwise there wont be any taxes
        s_whitelisted[msg.sender] = true;
        s_whitelisted[address(s_dexRouter)] = true;
        _mint(msg.sender, _totalSupply);
    }

    function setDevelopmentWallet(address _newDev) external onlyOwner {
        require(
            _newDev != address(0),
            "new Development wallet can not be address zero!"
        );
        s_development = _newDev;
        emit DevelopmentWalletChangd(_newDev);
    }

    function setStakingVault(address _newStaking) external onlyOwner {
        require(
            _newStaking != address(0),
            "new staking vault can not be address 0"
        );
        s_stakingVault = _newStaking;
        emit StakingValutChanged(_newStaking);
    }

    function setBuyFees(
        uint256 _stakingVault,
        uint256 _development,
        uint256 _liquidity
    ) external onlyOwner {
        require(
            _stakingVault + _development + _liquidity <= 30,
            "Can't set taxs more than 30%"
        );
        //Taxes
        b_stakingVaultTax = _stakingVault;
        b_developmentTax = _development;
        b_liquidityTax = _liquidity;
        b_totalFee = _stakingVault + _development + _liquidity;

        //Tax shares
        StakingShare = _stakingVault + s_stakingVaultTax;
        LiquidityShare = _liquidity + s_liquidityTax;
        DevelopmentShare = _development + s_developmentTax;
        TotalTaxes = s_totalFee + b_totalFee;
        emit FeesChanged(_stakingVault, _development, _liquidity);
    }

    function setSellFees(
        uint256 _stakingVault,
        uint256 _development,
        uint256 _liquidity
    ) external onlyOwner {
        require(
            _stakingVault + _development + _liquidity <= 30,
            "Can't set taxs more than 30%"
        );
        //Taxes
        s_stakingVaultTax = _stakingVault;
        s_developmentTax = _development;
        s_liquidityTax = _liquidity;
        s_totalFee = _stakingVault + _development + _liquidity;

        //Tax shares
        StakingShare = _stakingVault + b_stakingVaultTax;
        LiquidityShare = _liquidity + b_liquidityTax;
        DevelopmentShare = _development + b_developmentTax;
        TotalTaxes = s_totalFee + b_totalFee;
        emit FeesChanged(_stakingVault, _development, _liquidity);
    }

    function setSwapTokensAtAmount(uint256 _newAmount) external onlyOwner {
        require(
            _newAmount > 0,
            "MLN : Minimum swap amount must be greater than 0!"
        );
        s_swapTokensAtAmount = _newAmount;
        emit MinimumSwapAmountChaned(_newAmount);
    }

    function toggleSwapping() external onlyOwner {
        s_swapAndLiquifyEnabled = (s_swapAndLiquifyEnabled == true)
            ? false
            : true;
        emit SwapAndLiuqifityStatusChanged(s_swapAndLiquifyEnabled);
    }

    function setWhitelistStatus(address _wallet, bool _status)
        external
        onlyOwner
    {
        s_whitelisted[_wallet] = _status;
        emit WhitelistAction(_wallet, _status);
    }

    function checkWhitelist(address _wallet) external view returns (bool) {
        return s_whitelisted[_wallet];
    }

    function _takeTax(
        address _from,
        address _to,
        uint256 _amount
    ) internal returns (uint256) {
        if (s_whitelisted[_from] || s_whitelisted[_to]) {
            return _amount;
        }
        uint256 totalTax = 0;
        if (_to == s_pairAddress) {
            totalTax = s_totalFee;
        } else if (_from == s_pairAddress) {
            totalTax = b_totalFee;
        }
        uint256 tax = (_amount * totalTax) / 100;
        super._transfer(_from, address(this), tax);
        return (_amount - tax);
    }

    function _transfer(
        address _from,
        address _to,
        uint256 _amount
    ) internal virtual override {
        require(_from != address(0), "transfer from address zero");
        require(_to != address(0), "transfer to address zero");
        uint256 toTransfer = _takeTax(_from, _to, _amount);
        // if toTransfer is equal to _amount, this means that we didnt get taxes and to or from is whitelisted
        bool canSwap = balanceOf(address(this)) >= s_swapTokensAtAmount;
        if (
            s_swapAndLiquifyEnabled &&
            s_pairAddress == _to &&
            canSwap &&
            !s_whitelisted[_from] &&
            !s_whitelisted[_to] &&
            !s_isSwapping
        ) {
            s_isSwapping = true;
            manageTaxes();
            s_isSwapping = false;
        }
        super._transfer(_from, _to, toTransfer);
    }

    function manageTaxes() internal {
        uint256 taxAmount = balanceOf(address(this));
        uint256 totalTaxes = TotalTaxes;
        uint256 liquidityPortion = (taxAmount * LiquidityShare) / totalTaxes;
        uint256 stakingVaultPortion = (taxAmount * StakingShare) / totalTaxes;
        uint256 developmentPortion = (taxAmount * DevelopmentShare) /
            totalTaxes;
        //Add Liquidty taxes to liqudity pool
        if (liquidityPortion > 0) {
            swapAndLiquify(liquidityPortion);
        }
        //send other taxes to staking and development wallets

        //after swap and liquify a little amount of tokens will be stuck in contract
        //we will send this stuck tokens to developement wallet
        uint256 stuckAmount = balanceOf(address(this)) -
            (stakingVaultPortion + developmentPortion);
        super._transfer(address(this), s_stakingVault, stakingVaultPortion);
        super._transfer(
            address(this),
            s_development,
            developmentPortion + stuckAmount
        );
    }

    function swapAndLiquify(uint256 _amount) internal {
        uint256 firstHalf = _amount / 2;
        uint256 otherHalf = _amount - firstHalf;
        uint256 initialETHBalance = address(this).balance;

        //Swapping first half to ETH
        swapToBNB(firstHalf);
        uint256 received = address(this).balance - initialETHBalance;
        addLiquidity(otherHalf, received);
    }

    function swapToBNB(uint256 _amount) internal {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = s_dexRouter.WETH();
        _approve(address(this), address(s_dexRouter), _amount);
        s_dexRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            _amount,
            0, // accept any amount of BaseToken
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 bnbAmount) private {
        _approve(address(this), address(s_dexRouter), tokenAmount);
        s_dexRouter.addLiquidityETH{value: bnbAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(this),
            block.timestamp
        );
    }

    function updateDexRouter(address _newDex) external onlyOwner {
        s_dexRouter = DexRouter(_newDex);
        s_pairAddress = DexFactory(s_dexRouter.factory()).createPair(
            address(this),
            s_dexRouter.WETH()
        );
        emit DexRouterUpdated(_newDex, address(s_pairAddress));
    }

    receive() external payable {}

    function withdrawStuckBNB() external onlyOwner {
        (bool success, ) = address(msg.sender).call{
            value: address(this).balance
        }("");
        require(success, "transfering BNB failed");
    }

    function withdrawStuckTokens(address erc20_token) external onlyOwner {
        bool success = IERC20(erc20_token).transfer(
            msg.sender,
            IERC20(erc20_token).balanceOf(address(this))
        );
        require(success, "trasfering tokens failed!");
    }
}
