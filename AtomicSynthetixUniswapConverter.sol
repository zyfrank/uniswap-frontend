pragma solidity ^0.5.7;

import "./SafeDecimalMath.sol";


interface UniswapExchangeInterface {
	function getEthToTokenInputPrice(uint) external view returns (uint);
    function getEthToTokenOutputPrice(uint) external view returns (uint);
	function getTokenToEthInputPrice(uint) external view returns (uint);
    function getTokenToEthOutputPrice(uint) external view returns (uint);
    function ethToTokenTransferInput(uint, uint, address) external payable returns (uint);
	function ethToTokenSwapInput(uint, uint) external payable returns (uint);
    function ethToTokenTransferOutput(uint, uint, address) external payable returns (uint);
    function ethToTokenSwapOutput(uint, uint) external payable returns (uint);
    function tokenToEthTransferInput(uint, uint, uint, address) external returns (uint);
    function tokenToEthTransferOutput(uint, uint, uint, address) external returns (uint);
    function addLiquidity(uint, uint,uint) external payable returns(uint);
}

interface SynthetixInterface {
	function exchange(bytes4 srcKey, uint srcAmt, bytes4 dstKey, address dstAddr) external returns (bool);
}

interface SynthetixRatesInterface{
    function effectiveValue(bytes4 srcKey, uint srcAmt, bytes4 dstKey) external view returns (uint);
}

interface TokenInterface {
    function transfer(address, uint) external returns (bool);
    function approve(address, uint) external;
    function transferFrom(address, address, uint) external returns (bool);
	function balanceOf(address) external view returns (uint);
}

interface SynthetixFeePool{
	function amountReceivedFromTransfer(uint) external view returns (uint);
	function transferredAmountToReceive(uint) external view returns (uint);
	function amountReceivedFromExchange(uint) external view returns (uint);
	function exchangedAmountToReceive(uint) external view returns (uint);
	function exchangeFeeRate() external view returns (uint);
}

contract AtomicSynthetixUniswapConverter {
	using SafeMath for uint;
    using SafeDecimalMath for uint;

    //following are Rinkeby addresses
	address public use = 0xA1b571D290faB6DA975b7A95Eef80788ba85F4C6; // Uniswap sEth Exchange
	//address public sEthToken = 0x3731ab0E9FeEE3Ef0C427E874265E8F9a9111e27;  //Synthetix SynthsETH
    address public synRates = 0xA66F3a1333DF69A2B7e330e1265d2f468ff4808C; //Synthetix Rates
    address public synthetix = 0xC1b37C07820d612F941C0B8b344119300F904903; //Synthetix
	address public synFeePool = 0x2d5eb59D4881aDd873B640E701FddFed0DDcef0c;   //Synthetix FeePool
    bytes4 sEthCurrencyKey = 'sETH';
    mapping(bytes4 => address) public synthsAddrs;

	constructor() public {
		//following are synth token addresses
		synthsAddrs['sETH'] = 0x3731ab0E9FeEE3Ef0C427E874265E8F9a9111e27;
		synthsAddrs['sUSD'] = 0x95b92876a85c64Ede4a159161D502FCAeDAFc7C8;
		synthsAddrs['sBNB'] = 0xeB082E1B4a79a97bA352DC77489C8594d12eFff0;
	}
    
	//to recieve refund from uniswap
	function() external payable { 
		require(msg.sender == use);
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
		require(TokenInterface(synthsAddrs[sEthCurrencyKey]).transferFrom (msg.sender, address(this), sEthSold));
		TokenInterface(synthsAddrs[sEthCurrencyKey]).approve(use, sEthSold);
		UniswapExchangeInterface useContract = UniswapExchangeInterface(use);
		if (recipient == address(0)){
		    ethAmt = useContract.tokenToEthTransferInput(sEthSold, minEth, deadline, msg.sender);
		}else{
			ethAmt = useContract.tokenToEthTransferInput(sEthSold, minEth, deadline, recipient);
		}
		require(address(this).balance == 0);
		require (TokenInterface(synthsAddrs[sEthCurrencyKey]).balanceOf(address(this)) == 0);

		return ethAmt;
	}

	function sEthToEthOutput (uint ethBought, uint maxSethSold, uint deadline, address recipient) external returns (uint sEthAmt) {
		require (deadline >= block.timestamp);
		UniswapExchangeInterface useContract = UniswapExchangeInterface(use);
		uint needSeth = useContract.getTokenToEthOutputPrice(ethBought);
		require (maxSethSold >= needSeth);
		require(TokenInterface(synthsAddrs[sEthCurrencyKey]).transferFrom (msg.sender, address(this), needSeth));
		TokenInterface(synthsAddrs[sEthCurrencyKey]).approve(use, needSeth);
        if (recipient == address(0)){
		    sEthAmt = useContract.tokenToEthTransferOutput(ethBought, needSeth, deadline, msg.sender);
        }else{
            sEthAmt = useContract.tokenToEthTransferOutput(ethBought, needSeth, deadline, recipient);
		}
		require(address(this).balance == 0);
		require (TokenInterface(synthsAddrs[sEthCurrencyKey]).balanceOf(address(this)) == 0);
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
		require(address(this).balance == 0);
		require (TokenInterface(synthsAddrs[sEthCurrencyKey]).balanceOf(address(this)) == 0);
		require (TokenInterface(synthsAddrs[boughtCurrencyKey]).balanceOf(address(this)) == 0);
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
		require(address(this).balance == 0);
		require (TokenInterface(synthsAddrs[sEthCurrencyKey]).balanceOf(address(this)) == 0);
		require (TokenInterface(synthsAddrs[boughtCurrencyKey]).balanceOf(address(this)) == 0);
		return ethAmt;
	}

	function otherTokenToEthInput (bytes4 srcKey, uint srcAmt, uint minEth, uint deadline, address recipient) external returns (uint) {
		require (deadline >= block.timestamp);

		UniswapExchangeInterface useContract = UniswapExchangeInterface(use);
		SynthetixInterface synContract = SynthetixInterface(synthetix);
		uint sEthAmtReceived = _sTokenAmtRecvFromExchangeByToken(srcAmt, srcKey,sEthCurrencyKey);
		require(TokenInterface(synthsAddrs[srcKey]).transferFrom (msg.sender, address(this), srcAmt));
		TokenInterface(synthsAddrs[srcKey]).approve(synthetix, srcAmt);
        require (synContract.exchange (srcKey, srcAmt, sEthCurrencyKey, address(this)));
		
		TokenInterface(synthsAddrs[sEthCurrencyKey]).approve(use, sEthAmtReceived);
		uint ethAmt;
		if (recipient == address(0)){
            ethAmt = useContract.tokenToEthTransferInput(sEthAmtReceived, minEth, deadline, msg.sender);
		}else{
            ethAmt = useContract.tokenToEthTransferInput(sEthAmtReceived, minEth, deadline, recipient);
		}
		require(address(this).balance == 0);
		require (TokenInterface(synthsAddrs[sEthCurrencyKey]).balanceOf(address(this)) == 0);
		require (TokenInterface(synthsAddrs[srcKey]).balanceOf(address(this)) == 0);
		return ethAmt;
	}
		
	function otherTokenToEthOutput (uint ethBought, bytes4 srcKey, uint maxSrcAmt, uint deadline, address recipient) external returns (uint) {
		require (deadline >= block.timestamp);

		UniswapExchangeInterface useContract = UniswapExchangeInterface(use);
		SynthetixRatesInterface synRatesContract = SynthetixRatesInterface(synRates);
		SynthetixInterface synContract = SynthetixInterface(synthetix);

		uint sEthAmt = useContract.getTokenToEthOutputPrice (ethBought);
		uint srcAmt = _sTokenEchangedAmtToRecvByToken(sEthAmt, sEthCurrencyKey, srcKey);
        require (srcAmt <= maxSrcAmt);

        require(TokenInterface(synthsAddrs[srcKey]).transferFrom(msg.sender, address(this), srcAmt));
		TokenInterface(synthsAddrs[srcKey]).approve(synthetix, srcAmt);
		require (synContract.exchange(srcKey, srcAmt, sEthCurrencyKey, address(this)));

		if (recipient == address(0)){
            useContract.tokenToEthTransferOutput(ethBought, sEthAmt, deadline, msg.sender);
		}else{
            useContract.tokenToEthTransferOutput(ethBought, sEthAmt, deadline, recipient);
		}
		require(address(this).balance == 0);
		require (TokenInterface(synthsAddrs[sEthCurrencyKey]).balanceOf(address(this)) == 0);
		require (TokenInterface(synthsAddrs[srcKey]).balanceOf(address(this)) == 0);
		return srcAmt;
	}

	function ethToSethInput (uint minSeth, uint deadline, address recipient) external payable returns (uint) {
		require (deadline >= block.timestamp);

		UniswapExchangeInterface useContract = UniswapExchangeInterface(use);
        uint sEthAmt;
		if (recipient == address(0)){
		    sEthAmt = useContract.ethToTokenTransferInput.value(msg.value)(minSeth, deadline, msg.sender);
		}else{
            sEthAmt = useContract.ethToTokenTransferInput.value(msg.value)(minSeth, deadline, recipient);
		}
		require(address(this).balance == 0);
		require (TokenInterface(synthsAddrs[sEthCurrencyKey]).balanceOf(address(this)) == 0);
		return sEthAmt;
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
		require(address(this).balance == 0);
		require (TokenInterface(synthsAddrs[sEthCurrencyKey]).balanceOf(address(this)) == 0);
        return ethAmt;
	}

	function sTokenToStokenInput (bytes4 srcKey, uint srcAmt, bytes4 dstKey, uint minDstAmt, uint deadline, address recipient) external returns (uint) {
		require (deadline >= block.timestamp);

		SynthetixInterface synContract = SynthetixInterface(synthetix);
		SynthetixRatesInterface synRatesContract = SynthetixRatesInterface(synRates);
		uint dstAmt = _sTokenAmtRecvFromExchangeByToken(srcAmt, srcKey, dstKey);
		require (dstAmt >= minDstAmt);
		require(TokenInterface(synthsAddrs[srcKey]).transferFrom (msg.sender, address(this), srcAmt));
		TokenInterface(synthsAddrs[srcKey]).approve(synthetix, srcAmt);
		require (synContract.exchange(srcKey, srcAmt, dstKey, address(this)));

		if (recipient == address(0)){
		    require(TokenInterface(synthsAddrs[dstKey]).transfer(msg.sender, dstAmt));
		}else{
            require(TokenInterface(synthsAddrs[dstKey]).transfer(recipient, dstAmt));
		}
		require(address(this).balance == 0);
		require (TokenInterface(synthsAddrs[sEthCurrencyKey]).balanceOf(address(this)) == 0);
		require (TokenInterface(synthsAddrs[srcKey]).balanceOf(address(this)) == 0);
		require (TokenInterface(synthsAddrs[dstKey]).balanceOf(address(this)) == 0);
		return dstAmt;
	}

	function sTokenToStokenOutput (bytes4 srcKey, uint maxSrcAmt, bytes4 dstKey, uint boughtDstAmt, uint deadline, address recipient) external returns (uint) {
		require (deadline >= block.timestamp);

		SynthetixInterface synContract = SynthetixInterface(synthetix);
		uint srcAmt = _sTokenEchangedAmtToRecvByToken(boughtDstAmt, dstKey, srcKey);
        require (srcAmt <= maxSrcAmt);

        require(TokenInterface(synthsAddrs[srcKey]).transferFrom (msg.sender, address(this), srcAmt));
		TokenInterface(synthsAddrs[srcKey]).approve(synthetix, srcAmt);
		require (synContract.exchange(srcKey, srcAmt, dstKey, address(this)));

		if (recipient == address(0)){
		   require(TokenInterface(synthsAddrs[dstKey]).transfer(msg.sender, boughtDstAmt));
		}else{
           require(TokenInterface(synthsAddrs[dstKey]).transfer(recipient, boughtDstAmt));
		}
		require(address(this).balance == 0);
		require (TokenInterface(synthsAddrs[sEthCurrencyKey]).balanceOf(address(this)) == 0);
		require (TokenInterface(synthsAddrs[srcKey]).balanceOf(address(this)) == 0);
		require (TokenInterface(synthsAddrs[dstKey]).balanceOf(address(this)) == 0);
		return srcAmt;
	}

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

} 