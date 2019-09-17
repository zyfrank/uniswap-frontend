pragma solidity ^0.5.7;

import "./SafeDecimalMath.sol";

interface UniswapExchangeInterface {
	function getEthToTokenInputPrice(uint) external view returns (uint);
    function getEthToTokenOutputPrice(uint) external view returns (uint);
	function getTokenToEthInputPrice(uint256) external view returns (uint);
    function getTokenToEthOutputPrice(uint256) external view returns (uint);
    function ethToTokenTransferInput(uint256, uint256, address) external payable returns (uint256);
	function ethToTokenSwapInput(uint minTokens, uint deadline) external payable returns (uint tokenBought);
    function ethToTokenTransferOutput(uint256, uint256, address) external payable returns (uint256);
    function ethToTokenSwapOutput(uint256, uint256) external payable returns (uint256);
    function tokenToEthTransferInput(uint256, uint256, uint256, address) external returns (uint256);
    function tokenToEthTransferOutput(uint256, uint256, uint256, address) external returns (uint256);
    function addLiquidity(uint256, uint256,uint256) external payable returns(uint256);
}

interface SynthetixInterface {
	function exchange(bytes4 sourceCurrencyKey, uint sourceAmount, bytes4 destinationCurrencyKey, address destinationAddress) external returns (bool);
}

interface SynthetixRatesInterface{
    function effectiveValue(bytes4 sourceCurrencyKey, uint sourceAmount, bytes4 destinationCurrencyKey) external view returns (uint);
}

interface TokenInterface {
    function transfer(address, uint) external returns (bool);
    function approve(address, uint) external;
    function transferFrom(address, address, uint) external returns (bool);
}

interface SynthetixFeePool{
	function amountReceivedFromTransfer(uint value) external view returns (uint);
	function transferredAmountToReceive(uint value) external view returns (uint);
	function amountReceivedFromExchange(uint value) external view returns (uint);
	function exchangedAmountToReceive(uint value) external view returns (uint);
	function exchangeFeeRate() external view returns (uint);
}

contract AtomicSynthetixUniswapConverter {
	using SafeMath for uint;
    using SafeDecimalMath for uint;

	address public use = 0xA1b571D290faB6DA975b7A95Eef80788ba85F4C6; // Uniswap sEth Exchange
	address public sEthToken = 0x3731ab0E9FeEE3Ef0C427E874265E8F9a9111e27;  //Synthetix SynthsETH
    address public synRates = 0xA66F3a1333DF69A2B7e330e1265d2f468ff4808C; //Synthetix Rates
    address public synthetix = 0xC1b37C07820d612F941C0B8b344119300F904903; //Synthetix
	address public synFeePool = 0x2d5eb59D4881aDd873B640E701FddFed0DDcef0c;   //Synthetix FeePool
    bytes4 sEthCurrencyKey = 'sETH';
    mapping(bytes4 => address) public synthsAddrs;

	constructor() public {
		synthsAddrs['sUSD'] = 0x95b92876a85c64Ede4a159161D502FCAeDAFc7C8;
		synthsAddrs['sBNB'] = 0xeB082E1B4a79a97bA352DC77489C8594d12eFff0;
	}
    
	//to recieve refund from uniswap
	function() external payable { }

    function _sTokenAmountReceivedFromTransfer (uint sentAmt) internal view returns (uint) {
        SynthetixFeePool feePool = SynthetixFeePool(synFeePool);
		return feePool.amountReceivedFromTransfer(sentAmt);
	}

	function _sTokenTransferredAmountToReceive (uint receivedAmt) internal view returns (uint) {
        SynthetixFeePool feePool = SynthetixFeePool(synFeePool);
		return feePool.transferredAmountToReceive(receivedAmt);
	}

    function _sTokenAmtRecvFromExchangeByToken (uint srcAmt, bytes4 srcKey, bytes4 dstKey) internal view returns (uint){
        SynthetixFeePool feePool = SynthetixFeePool(synFeePool);
		SynthetixRatesInterface synRatesContract = SynthetixRatesInterface(synRates);
		uint dstAmt = synRatesContract.effectiveValue(srcKey, srcAmt, dstKey);
		uint feeRate = feePool.exchangeFeeRate();
		return  dstAmt.multiplyDecimal(SafeDecimalMath.unit().sub(feeRate));
	}

    function _sTokenEchangedAmtToRecvByToken (uint receivedAmt, bytes4 receivedKey, bytes4 srcKey) internal view returns (uint) {
		SynthetixFeePool feePool = SynthetixFeePool(synFeePool);
		SynthetixRatesInterface synRatesContract = SynthetixRatesInterface(synRates);
		uint feeRate = feePool.exchangeFeeRate();
		uint dstAmt = receivedAmt.divideDecimal(SafeDecimalMath.unit().sub(feeRate));
		return synRatesContract.effectiveValue(receivedKey, dstAmt, srcKey);
	}

    function inputPrice(bytes4 src, uint srcAmt, bytes4 dst) external view returns (uint) {
		if (src == 'ETH') {
			uint sEthAmt = UniswapExchangeInterface(use).getEthToTokenInputPrice(srcAmt);
			if (dst == 'sETH') {
                return sEthAmt;
			}else {
				return _sTokenAmtRecvFromExchangeByToken(sEthAmt, sEthCurrencyKey, dst);
			}
		}else if (src == 'sETH'){
			if  (dst == 'ETH') {
				return UniswapExchangeInterface(use).getTokenToEthInputPrice(srcAmt);
			} else {
				return _sTokenAmtRecvFromExchangeByToken(srcAmt, sEthCurrencyKey, dst);
			}
		}else {
			if (dst == 'ETH'){
				uint sEthAmt = _sTokenAmtRecvFromExchangeByToken(srcAmt, src, sEthCurrencyKey);
                return UniswapExchangeInterface(use).getTokenToEthInputPrice(sEthAmt);
			}else{
                return _sTokenAmtRecvFromExchangeByToken(srcAmt, src, dst);
			}
		}
	}

	function outputPrice(bytes4 src, bytes4 dst, uint dstAmt) external view returns (uint) {
		if (src == 'ETH') {
			if (dst == 'sETH') {
                return UniswapExchangeInterface(use).getEthToTokenOutputPrice(dstAmt);
			}else {
				uint sEthAmt = _sTokenEchangedAmtToRecvByToken(dstAmt, dst, sEthCurrencyKey);
				return UniswapExchangeInterface(use).getEthToTokenOutputPrice(sEthAmt);
			}
		}else if (src == 'sETH'){
			if  (dst == 'ETH') {
				return UniswapExchangeInterface(use).getTokenToEthOutputPrice(dstAmt);
			} else {
				return _sTokenEchangedAmtToRecvByToken(dstAmt, dst, sEthCurrencyKey);
			}
		}else {
			if (dst == 'ETH'){
				uint sEthAmt = UniswapExchangeInterface(use).getTokenToEthOutputPrice(dstAmt);
				return _sTokenEchangedAmtToRecvByToken(sEthAmt, sEthCurrencyKey, src);
			}else{
                return _sTokenEchangedAmtToRecvByToken(dstAmt, dst, src);
			}
		}
	}

    function sEthToEthInput (uint sEthSold, uint minEth, uint deadline, address recipient) external returns (uint ethAmt) {
		require (deadline >= block.timestamp);
		require(TokenInterface(sEthToken).transferFrom (msg.sender, address(this), sEthSold));
		TokenInterface(sEthToken).approve(use, sEthSold);
		UniswapExchangeInterface useContract = UniswapExchangeInterface(use);
		if (recipient == address(0)){
		    ethAmt = useContract.tokenToEthTransferInput(sEthSold, minEth, deadline, msg.sender);
		}else{
			ethAmt = useContract.tokenToEthTransferInput(sEthSold, minEth, deadline, recipient);
		}
		return ethAmt;
	}

	function sEthToEthOutput (uint ethBought, uint maxSethSold, uint deadline, address recipient) external returns (uint sEthAmt) {
		require (deadline >= block.timestamp);
		UniswapExchangeInterface useContract = UniswapExchangeInterface(use);
		uint needSeth = useContract.getTokenToEthOutputPrice(ethBought);
		require (maxSethSold >= needSeth);
		require(TokenInterface(sEthToken).transferFrom (msg.sender, address(this), needSeth));
		TokenInterface(sEthToken).approve(use, needSeth);
        if (recipient == address(0)){
		    sEthAmt = useContract.tokenToEthTransferOutput(ethBought, needSeth, deadline, msg.sender);
        }else{
            sEthAmt = useContract.tokenToEthTransferOutput(ethBought, needSeth, deadline, recipient);
		}
	}

	function ethToOtherTokenInput (uint minToken, bytes4 boughtCurrencyKey, uint deadline, address recipient) external payable returns (uint) {
		require (deadline >= block.timestamp);

		UniswapExchangeInterface useContract = UniswapExchangeInterface(use);
		SynthetixInterface synContract = SynthetixInterface(synthetix);

		uint minsEth = _sTokenEchangedAmtToRecvByToken(minToken, boughtCurrencyKey, sEthCurrencyKey);
		uint sEthAmt = useContract.ethToTokenSwapInput.value(msg.value)(minsEth, deadline);
		uint receivedAmt = _sTokenAmtRecvFromExchangeByToken(sEthAmt, sEthCurrencyKey, boughtCurrencyKey);
        require (receivedAmt >= minToken);
	    require (synContract.exchange (sEthCurrencyKey, sEthAmt, boughtCurrencyKey, address(this)));
		if (recipient == address(0)){
		    require (TokenInterface(synthsAddrs[boughtCurrencyKey]).transfer(msg.sender, receivedAmt));
		}else{
            require (TokenInterface(synthsAddrs[boughtCurrencyKey]).transfer(recipient, receivedAmt));
		}
        return receivedAmt;
	}

	function ethToOtherTokenOutput (uint tokenBought, bytes4 boughtCurrencyKey, uint deadline, address recipient) external payable returns (uint) {
		require (deadline >= block.timestamp);

		UniswapExchangeInterface useContract = UniswapExchangeInterface(use);
		SynthetixInterface synContract = SynthetixInterface(synthetix);

		uint sEthAmt = _sTokenEchangedAmtToRecvByToken(tokenBought, boughtCurrencyKey, sEthCurrencyKey);
		uint ethAmt = useContract.ethToTokenSwapOutput.value(msg.value)(sEthAmt, deadline);
		if (msg.value > ethAmt){
			msg.sender.transfer(msg.value - ethAmt);
		} 
	    require (synContract.exchange(sEthCurrencyKey, sEthAmt, boughtCurrencyKey, address(this)));
		if (recipient == address(0)){
		    require (TokenInterface(synthsAddrs[boughtCurrencyKey]).transfer(msg.sender, tokenBought));
		}else{
			require (TokenInterface(synthsAddrs[boughtCurrencyKey]).transfer(recipient, tokenBought));
		}
		return ethAmt;
	}

	function otherTokenToEthInput (bytes4 sourceCurrencyKey, uint sourceAmount, uint minEth, uint deadline, address recipient) external returns (uint) {
		require (deadline >= block.timestamp);

		UniswapExchangeInterface useContract = UniswapExchangeInterface(use);
		SynthetixInterface synContract = SynthetixInterface(synthetix);
		uint sEthAmtReceived = _sTokenAmtRecvFromExchangeByToken(sourceAmount, sourceCurrencyKey,sEthCurrencyKey);
		require(TokenInterface(synthsAddrs[sourceCurrencyKey]).transferFrom (msg.sender, address(this), sourceAmount));
		TokenInterface(synthsAddrs[sourceCurrencyKey]).approve(synthetix, sourceAmount);
        require (synContract.exchange (sourceCurrencyKey, sourceAmount, sEthCurrencyKey, address(this)));
		
		TokenInterface(sEthToken).approve(use, sEthAmtReceived);
		if (recipient == address(0)){
            return useContract.tokenToEthTransferInput(sEthAmtReceived, minEth, deadline, msg.sender);
		}else{
            return useContract.tokenToEthTransferInput(sEthAmtReceived, minEth, deadline, recipient);
		}
	}
		
	function otherTokenToEthOutput (uint ethBought, bytes4 sourceCurrencyKey, uint maxSourceAmount, uint deadline, address recipient) external returns (uint) {
		require (deadline >= block.timestamp);

		UniswapExchangeInterface useContract = UniswapExchangeInterface(use);
		SynthetixRatesInterface synRatesContract = SynthetixRatesInterface(synRates);
		SynthetixInterface synContract = SynthetixInterface(synthetix);

		uint sEthAmt = useContract.getTokenToEthOutputPrice (ethBought);
		uint srcAmt = _sTokenEchangedAmtToRecvByToken(sEthAmt, sEthCurrencyKey, sourceCurrencyKey);
        require (srcAmt <= maxSourceAmount);

        require(TokenInterface(synthsAddrs[sourceCurrencyKey]).transferFrom(msg.sender, address(this), srcAmt));
		TokenInterface(synthsAddrs[sourceCurrencyKey]).approve(synthetix, srcAmt);
		require (synContract.exchange(sourceCurrencyKey, srcAmt, sEthCurrencyKey, address(this)));

		if (recipient == address(0)){
            useContract.tokenToEthTransferOutput(ethBought, sEthAmt, deadline, msg.sender);
		}else{
            useContract.tokenToEthTransferOutput(ethBought, sEthAmt, deadline, recipient);
		}
		return srcAmt;
	}

	function ethToSethInput (uint minSeth, uint deadline, address recipient) external payable returns (uint) {
		require (deadline >= block.timestamp);

		UniswapExchangeInterface useContract = UniswapExchangeInterface(use);

		if (recipient == address(0)){
		    return useContract.ethToTokenTransferInput.value(msg.value)(minSeth, deadline, msg.sender);
		}else{
            return useContract.ethToTokenTransferInput.value(msg.value)(minSeth, deadline, recipient);
		}
	}
   
   	function ethToSethOutput (uint sethBought, uint deadline, address recipient) external payable returns (uint ethAmt) {
		require (deadline >= block.timestamp);

		UniswapExchangeInterface useContract = UniswapExchangeInterface(use);

		if (recipient == address(0)){
		    ethAmt = useContract.ethToTokenTransferOutput.value(msg.value)(sethBought, deadline, msg.sender);
		}else{
            ethAmt = useContract.ethToTokenTransferOutput.value(msg.value)(sethBought, deadline, recipient);
		}
		msg.sender.transfer(msg.value - ethAmt);
        return ethAmt;
	}

	function sTokenToStokenInput (bytes4 sourceCurrencyKey, uint sourceAmount, bytes4 destinationCurrencyKey, uint minDstAmt, uint deadline, address recipient) external returns (bool) {
		require (deadline >= block.timestamp);

		SynthetixInterface synContract = SynthetixInterface(synthetix);
		SynthetixRatesInterface synRatesContract = SynthetixRatesInterface(synRates);
		uint dstAmt = _sTokenAmtRecvFromExchangeByToken(sourceAmount, sourceCurrencyKey, destinationCurrencyKey);
		require (dstAmt >= minDstAmt);
		require(TokenInterface(synthsAddrs[sourceCurrencyKey]).transferFrom (msg.sender, address(this), sourceAmount));
		TokenInterface(synthsAddrs[sourceCurrencyKey]).approve(synthetix, sourceAmount);
		require (synContract.exchange(sourceCurrencyKey, sourceAmount, destinationCurrencyKey, address(this)));

		if (recipient == address(0)){
		    require(TokenInterface(synthsAddrs[destinationCurrencyKey]).transfer(msg.sender, dstAmt));
		}else{
            require(TokenInterface(synthsAddrs[destinationCurrencyKey]).transfer(recipient, dstAmt));
		}
	}

	function sTokenToStokenOutput (bytes4 sourceCurrencyKey, uint maxSourceAmount, bytes4 destinationCurrencyKey, uint boughtDstAmt, uint deadline, address recipient) external returns (uint) {
		require (deadline >= block.timestamp);

		SynthetixInterface synContract = SynthetixInterface(synthetix);
		uint srcAmt = _sTokenEchangedAmtToRecvByToken(boughtDstAmt, destinationCurrencyKey, sourceCurrencyKey);
        require (srcAmt <= maxSourceAmount);

        require(TokenInterface(synthsAddrs[sourceCurrencyKey]).transferFrom (msg.sender, address(this), srcAmt));
		TokenInterface(synthsAddrs[sourceCurrencyKey]).approve(synthetix, srcAmt);
		require (synContract.exchange(sourceCurrencyKey, srcAmt, destinationCurrencyKey, address(this)));

		if (recipient == address(0)){
		   require(TokenInterface(synthsAddrs[destinationCurrencyKey]).transfer(msg.sender, boughtDstAmt));
		}else{
           require(TokenInterface(synthsAddrs[destinationCurrencyKey]).transfer(recipient, boughtDstAmt));
		}
		return srcAmt;
	}
} 