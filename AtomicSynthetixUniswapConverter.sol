pragma solidity ^0.5.7;

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
}

contract AtomicSynthetixUniswapConverter {

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

	function _sTokenAmountReceivedFromExchange (uint sentAmt) internal view returns (uint) {
        SynthetixFeePool feePool = SynthetixFeePool(synFeePool);
		return feePool.amountReceivedFromExchange(sentAmt);
	}

	function _sTokenExchangedAmountToReceive (uint receivedAmt) internal view returns (uint) {
        SynthetixFeePool feePool = SynthetixFeePool(synFeePool);
		return feePool.exchangedAmountToReceive(receivedAmt);
	}

    function _sTokenToStokenExchangeAmount (bytes4 src, uint srcAmt, bytes4 dst) internal view returns (uint) {
		uint dstAmt = SynthetixRatesInterface(synRates).effectiveValue(src, srcAmt, dst);
		return _sTokenAmountReceivedFromExchange(dstAmt);
	}

    function inputPrice(bytes4 src, uint srcAmt, bytes4 dst) external view returns (uint) {
		if (src == 'ETH') {
			uint sEthAmt = UniswapExchangeInterface(use).getEthToTokenInputPrice(srcAmt);
			if (dst == 'sETH') {
                return sEthAmt;
			}else {
                return _sTokenToStokenExchangeAmount(sEthCurrencyKey, sEthAmt, dst);
			}
		}else if (src == 'sETH'){
			if  (dst == 'ETH') {
				return UniswapExchangeInterface(use).getTokenToEthInputPrice(srcAmt);
			} else {
                return _sTokenToStokenExchangeAmount(sEthCurrencyKey, srcAmt, dst);
			}
		}else {
			if (dst == 'ETH'){
				uint sEthAmt = _sTokenToStokenExchangeAmount(src, srcAmt, sEthCurrencyKey);
                return UniswapExchangeInterface(use).getTokenToEthInputPrice(sEthAmt);
			}else{
                return _sTokenToStokenExchangeAmount(src, srcAmt, dst);
			}
		}
	}


	
    function sEthToEthInput (uint sEthSold, uint minEth, uint deadline, address recipient) external returns (uint ethAmt) {

		require(TokenInterface(sEthToken).transferFrom (msg.sender, address(this), sEthSold));
		TokenInterface(sEthToken).approve(use, sEthSold);
		UniswapExchangeInterface useContract = UniswapExchangeInterface(use);
		ethAmt = useContract.tokenToEthTransferInput(sEthSold, minEth, deadline, recipient);
	//	recipient.send(ethAmt);
		return ethAmt;
	}

	function sEthToEthOutput (uint ethBought, uint maxSethSold, uint deadline, address recipient) external returns (uint sEthAmt) {
		UniswapExchangeInterface useContract = UniswapExchangeInterface(use);
		uint needSeth = useContract.getTokenToEthOutputPrice(ethBought);
		require (maxSethSold >= needSeth);
		require(TokenInterface(sEthToken).transferFrom (msg.sender, address(this), needSeth));
		TokenInterface(sEthToken).approve(use, needSeth);

		sEthAmt = useContract.tokenToEthTransferOutput(ethBought, needSeth, deadline, recipient);
	}


	function ethToOtherTokenInput (uint minToken, bytes4 boughtCurrencyKey, uint deadline, address recipient) external payable returns (uint) {
		UniswapExchangeInterface useContract = UniswapExchangeInterface(use);
		SynthetixInterface synContract = SynthetixInterface(synthetix);
		SynthetixRatesInterface synRatesContract = SynthetixRatesInterface(synRates);
		uint minsEth = synRatesContract.effectiveValue(boughtCurrencyKey, minToken, sEthCurrencyKey);
		minsEth = _sTokenExchangedAmountToReceive(minsEth);
		uint sEthAmt = useContract.ethToTokenSwapInput.value(msg.value)(minsEth, deadline);
		
	//	uint sEthAmt = useContract.ethToTokenSwapInput.value(msg.value)(minToken, deadline);
		uint tokenAmt = synRatesContract.effectiveValue(sEthCurrencyKey, sEthAmt, boughtCurrencyKey);
		uint receivedAmt = _sTokenAmountReceivedFromExchange(tokenAmt);
        uint receivedAmtAfterTransfered = _sTokenAmountReceivedFromTransfer(receivedAmt);
        assert (receivedAmtAfterTransfered >= minToken);
	    assert (synContract.exchange (sEthCurrencyKey, sEthAmt, boughtCurrencyKey, recipient));
		assert (TokenInterface(synthsAddrs[boughtCurrencyKey]).transfer(recipient, receivedAmt));

        return receivedAmtAfterTransfered;
	}

	function ethToOtherTokenOutput (uint tokenBought, bytes4 boughtCurrencyKey, uint deadline, address recipient) external payable returns (uint) {
		UniswapExchangeInterface useContract = UniswapExchangeInterface(use);
		SynthetixInterface synContract = SynthetixInterface(synthetix);
		SynthetixRatesInterface synRatesContract = SynthetixRatesInterface(synRates);
		
		uint tokenBeforeTranfer = _sTokenTransferredAmountToReceive (tokenBought);
		uint neededsEthBeforeFeePaid = synRatesContract.effectiveValue(boughtCurrencyKey, tokenBeforeTranfer, sEthCurrencyKey);
		uint neededsEth = _sTokenExchangedAmountToReceive(neededsEthBeforeFeePaid);
		uint ethAmt = useContract.ethToTokenSwapOutput.value(msg.value)(neededsEth, deadline);
		if (msg.value > ethAmt){
			msg.sender.send(msg.value - ethAmt);
		} 
	    require (synContract.exchange (sEthCurrencyKey, neededsEth, boughtCurrencyKey, recipient));
		
        //Synthetix FeePool has a minor bug cause following computation
		uint tokenGot = synRatesContract.effectiveValue(sEthCurrencyKey, neededsEth, boughtCurrencyKey);
		tokenGot = _sTokenAmountReceivedFromExchange(tokenGot);
        assert (TokenInterface(synthsAddrs['sUSD']).transfer(recipient, tokenGot));
		return _sTokenAmountReceivedFromTransfer(tokenGot);
	}

	function otherTokenToEthInput (bytes4 sourceCurrencyKey, uint sourceAmount, uint minEth, uint deadline, address recipient) external returns (uint) {
		UniswapExchangeInterface useContract = UniswapExchangeInterface(use);
		SynthetixInterface synContract = SynthetixInterface(synthetix);
        SynthetixRatesInterface synRatesContract = SynthetixRatesInterface(synRates);
		uint sEthAmt = synRatesContract.effectiveValue(sourceCurrencyKey, sourceAmount, sEthCurrencyKey);
		uint sEthAmtReceived = _sTokenAmountReceivedFromExchange(sEthAmt);
		require(TokenInterface(synthsAddrs[sourceCurrencyKey]).transferFrom (msg.sender, address(this), sourceAmount));
		TokenInterface(synthsAddrs[sourceCurrencyKey]).approve(synthetix, sourceAmount);
        require (synContract.exchange (sourceCurrencyKey, sourceAmount, sEthCurrencyKey, address(this)));
		
		TokenInterface(sEthToken).approve(use, sEthAmtReceived);
        return useContract.tokenToEthTransferInput(sEthAmtReceived, minEth, deadline, recipient);
	}


		
	function otherTokenToEthOutput (uint ethBought, bytes4 sourceCurrencyKey, uint maxSourceAmount, uint deadline, address recipient) external returns (uint) {
		UniswapExchangeInterface useContract = UniswapExchangeInterface(use);
		SynthetixRatesInterface synRatesContract = SynthetixRatesInterface(synRates);
		SynthetixInterface synContract = SynthetixInterface(synthetix);

		uint neededSoldSEth = useContract.getTokenToEthOutputPrice (ethBought);
		uint neeedSoldToken = synRatesContract.effectiveValue(sEthCurrencyKey, neededSoldSEth, sourceCurrencyKey);
		neededSoldToken = _sTokenExchangedAmountToReceive(neeedSoldToken);
		neededSoldToken = _sTokenTransferredAmountToReceive(neeedSoldToken);
        require (neededSoldToken <= maxSourceAmount);

        require(TokenInterface(synthsAddrs[sourceCurrencyKey]).transferFrom(msg.sender, address(this), neededSoldToken));
		TokenInterface(synthsAddrs[sourceCurrencyKey]).approve(synthetix, neededSoldToken);
		require (synContract.exchange(sourceCurrencyKey, neededSoldToken, sEthCurrencyKey, recipient));
        uint boughtsEth = synRatesContract.effectiveValue(sourceCurrencyKey, neeedSoldToken, sEthCurrencyKey);
		boughtsEth = _sTokenAmountReceivedFromExchange(boughtsEth);
		boughtsEth = _sTokenAmountReceivedFromTransfer(boughtsEth);

        useContract.tokenToEthTransferOutput(ethBought, neededSoldSEth, deadline, recipient);
		return neededSoldToken;
	}


	function ethToSethInput (uint minSeth, uint deadline, address recipient) external payable returns (uint sEthAmt) {
		UniswapExchangeInterface useContract = UniswapExchangeInterface(use);
		sEthAmt = useContract.ethToTokenTransferInput.value(msg.value)(minSeth, deadline, recipient);
	    return sEthAmt;
	}
   

   	function ethToSethOutput (uint sethBought, uint deadline, address recipient) external payable returns (uint ethAmt) {
		UniswapExchangeInterface useContract = UniswapExchangeInterface(use);
		ethAmt = useContract.ethToTokenTransferOutput.value(msg.value)(sethBought, deadline, recipient);
		msg.sender.send(msg.value - ethAmt);
        return ethAmt;
	}

	function sTokenToStokenInput (bytes4 sourceCurrencyKey, uint sourceAmount, bytes4 destinationCurrencyKey, uint minDstAmt, uint deadline, address destinationAddress) external returns (bool) {
		SynthetixInterface synContract = SynthetixInterface(synthetix);
		SynthetixRatesInterface synRatesContract = SynthetixRatesInterface(synRates);
		uint boughtDstAmt = synRatesContract.effectiveValue(sourceCurrencyKey, sourceAmount, destinationCurrencyKey);
		boughtDstAmt = _sTokenAmountReceivedFromExchange(boughtDstAmt);
		boughtDstAmt = _sTokenAmountReceivedFromTransfer(boughtDstAmt);
		assert (boughtDstAmt >= minDstAmt);
		require(TokenInterface(synthsAddrs[sourceCurrencyKey]).transferFrom (msg.sender, address(this), sourceAmount));
		TokenInterface(synthsAddrs[sourceCurrencyKey]).approve(synthetix, sourceAmount);
		synContract.exchange(sourceCurrencyKey, sourceAmount, destinationCurrencyKey, address(this));
		require(TokenInterface(synthsAddrs[destinationCurrencyKey]).transfer(destinationAddress,boughtDstAmt));

	}

	function sTokenToStokenOutput (bytes4 sourceCurrencyKey, uint maxSourceAmount, bytes4 destinationCurrencyKey, uint boughtDstAmt, address destinationAddress) external returns (uint) {
		SynthetixInterface synContract = SynthetixInterface(synthetix);
		SynthetixRatesInterface synRatesContract = SynthetixRatesInterface(synRates);
		uint srcToBeSoldAfterFeePaid = synRatesContract.effectiveValue(destinationCurrencyKey, boughtDstAmt, sourceCurrencyKey);
		uint srcToBeSold = _sTokenTransferredAmountToReceive(srcToBeSoldAfterFeePaid);
        assert (srcToBeSold <= maxSourceAmount);
		require (synContract.exchange(sourceCurrencyKey, srcToBeSold, destinationCurrencyKey, destinationAddress));
		return srcToBeSold;
	}
} 