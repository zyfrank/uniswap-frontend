import React, { useState, useReducer, useEffect } from 'react'
import ReactGA from 'react-ga'

import { useTranslation } from 'react-i18next'
import { useWeb3Context } from 'web3-react'

import { ethers } from 'ethers'
import styled from 'styled-components'

import { Button } from '../../theme'
import CurrencyInputPanel from '../CurrencyInputPanel'
import AddressInputPanel from '../AddressInputPanel'
import OversizedPanel from '../OversizedPanel'
import TransactionDetails from '../TransactionDetails'
import ArrowDown from '../../assets/svg/SVGArrowDown'
import { amountFormatter, calculateGasMargin } from '../../utils'
import { useAtomicSynthetixUniswapConverterContract } from '../../hooks'
import { useTokenDetails } from '../../contexts/Tokens'
import { useTransactionAdder } from '../../contexts/Transactions'
import { useAddressBalance } from '../../contexts/Balances'
import { useFetchAllBalances } from '../../contexts/AllBalances'
import { useAddressAllowance } from '../../contexts/Allowances'

const INPUT = 0
const OUTPUT = 1

const ETH_TO_SETH = 0
const SETH_TO_ETH = 1
const ETH_TO_OTHERSTOKEN = 2
const OTHERSTOKEN_TO_ETH = 3
const STOKEN_TO_STOKEN = 4

const SETH_UNISWAP_EXCHANGE_ADDR = '0xA1b571D290faB6DA975b7A95Eef80788ba85F4C6'
const ATOMIC_CONVERT_ADDR = '0x1b8ee97d4159e7ad029bd69bf38b5190b2d5ec7d'

// denominated in bips
const ALLOWED_SLIPPAGE_DEFAULT = 100
const TOKEN_ALLOWED_SLIPPAGE_DEFAULT = 100

// 15 minutes, denominated in seconds
const DEADLINE_FROM_NOW = 60 * 15

// % above the calculated gas cost that we actually send, denominated in bips
const GAS_MARGIN = ethers.utils.bigNumberify(1000)

const DownArrowBackground = styled.div`
  ${({ theme }) => theme.flexRowNoWrap}
  justify-content: center;
  align-items: center;
`

const WrappedArrowDown = ({ clickable, active, ...rest }) => <ArrowDown {...rest} />
const DownArrow = styled(WrappedArrowDown)`
  color: ${({ theme, active }) => (active ? theme.royalBlue : theme.chaliceGray)};
  width: 0.625rem;
  height: 0.625rem;
  position: relative;
  padding: 0.875rem;
  cursor: ${({ clickable }) => clickable && 'pointer'};
`

const ExchangeRateWrapper = styled.div`
  ${({ theme }) => theme.flexRowNoWrap};
  align-items: center;
  color: ${({ theme }) => theme.doveGray};
  font-size: 0.75rem;
  padding: 0.5rem 1rem;
`

const ExchangeRate = styled.span`
  flex: 1 1 auto;
  width: 0;
  color: ${({ theme }) => theme.doveGray};
`

const Flex = styled.div`
  display: flex;
  justify-content: center;
  padding: 2rem;

  button {
    max-width: 20rem;
  }
`

function calculateSlippageBounds(value, token = false, tokenAllowedSlippage, allowedSlippage) {
  if (value) {
    const offset = value.mul(token ? tokenAllowedSlippage : allowedSlippage).div(ethers.utils.bigNumberify(10000))
    const minimum = value.sub(offset)
    const maximum = value.add(offset)
    return {
      minimum: minimum.lt(ethers.constants.Zero) ? ethers.constants.Zero : minimum,
      maximum: maximum.gt(ethers.constants.MaxUint256) ? ethers.constants.MaxUint256 : maximum
    }
  } else {
    return {}
  }
}

function getSwapType(inputCurrency, outputCurrency) {
  if (!inputCurrency || !outputCurrency) {
    return null
  }else if (inputCurrency === 'ETH') {
    if (outputCurrency ==='sETH'){
      return ETH_TO_SETH
    }else {
      return ETH_TO_OTHERSTOKEN
    }
  }else {
    if (inputCurrency === 'sETH') {
      if (outputCurrency ==='ETH') {
        return SETH_TO_ETH
      }else {
        return STOKEN_TO_STOKEN
      }
    }else {
      if (outputCurrency ==='ETH') {
        return OTHERSTOKEN_TO_ETH
      }else {
        return STOKEN_TO_STOKEN
      }
    }
  }
}

function getInitialSwapState(outputCurrency) {
  return {
    independentValue: '', // this is a user input
    dependentValue: '', // this is a calculated number
    independentField: INPUT,
    inputCurrency: 'ETH',
    outputCurrency: outputCurrency ? outputCurrency : ''
  }
}

function swapStateReducer(state, action) {
  switch (action.type) {
    case 'FLIP_INDEPENDENT': {
      const { independentField, inputCurrency, outputCurrency } = state
      return {
        ...state,
        dependentValue: '',
        independentField: independentField === INPUT ? OUTPUT : INPUT,
        inputCurrency: outputCurrency,
        outputCurrency: inputCurrency
      }
    }
    case 'SELECT_CURRENCY': {
      const { inputCurrency, outputCurrency } = state
      const { field, currency } = action.payload

      const newInputCurrency = field === INPUT ? currency : inputCurrency
      const newOutputCurrency = field === OUTPUT ? currency : outputCurrency

      if (newInputCurrency === newOutputCurrency) {
        return {
          ...state,
          inputCurrency: field === INPUT ? currency : '',
          outputCurrency: field === OUTPUT ? currency : ''
        }
      } else {
        return {
          ...state,
          inputCurrency: newInputCurrency,
          outputCurrency: newOutputCurrency
        }
      }
    }
    case 'UPDATE_INDEPENDENT': {
      const { field, value } = action.payload
      const { dependentValue, independentValue } = state
      return {
        ...state,
        independentValue: value,
        dependentValue: value === independentValue ? dependentValue : '',
        independentField: field
      }
    }
    case 'UPDATE_DEPENDENT': {
      return {
        ...state,
        dependentValue: action.payload
      }
    }
    case 'UPDATE_DEPENDENT_RATE': {
      return {
        ...state,
        dependentEthSethRate: action.payload
      }
    }
    default: {
      return getInitialSwapState()
    }
  }
}

function getExchangeRate(inputValue, inputDecimals, outputValue, outputDecimals, invert = false) {
  try {
    if (
      inputValue &&
      (inputDecimals || inputDecimals === 0) &&
      outputValue &&
      (outputDecimals || outputDecimals === 0)
    ) {
      const factor = ethers.utils.bigNumberify(10).pow(ethers.utils.bigNumberify(18))

      if (invert) {
        return inputValue
          .mul(factor)
          .div(outputValue)
          .mul(ethers.utils.bigNumberify(10).pow(ethers.utils.bigNumberify(outputDecimals)))
          .div(ethers.utils.bigNumberify(10).pow(ethers.utils.bigNumberify(inputDecimals)))
      } else {
        return outputValue
          .mul(factor)
          .div(inputValue)
          .mul(ethers.utils.bigNumberify(10).pow(ethers.utils.bigNumberify(inputDecimals)))
          .div(ethers.utils.bigNumberify(10).pow(ethers.utils.bigNumberify(outputDecimals)))
      }
    }
  } catch {}
}
/*
function getMarketRate(
  swapType,
  reserveETH,
  reserveSEthToken,
  inputDecimals,
 // outputReserveETH,
 // outputReserveToken,
  outputDecimals,
  invert = false
) {
  console.log("inputDecimals:" + inputDecimals + " outputDecimals:" + outputDecimals)
  if ((swapType === ETH_TO_SETH) | (swapType === ETH_TO_OTHERSTOKEN)){
    return getExchangeRate(reserveETH, 18, reserveSEthToken, outputDecimals, invert)
  }else if ((swapType === SETH_TO_ETH) | (swapType === OTHERSTOKEN_TO_ETH)){
    return getExchangeRate(reserveSEthToken, inputDecimals, reserveETH, 18, invert)
  }
  return undefined
 
}

*/
function getMarketRate(
  swapType,
  reserveETH,
  reserveSEthToken,
  invert = false
) {
  if ((swapType === ETH_TO_SETH) | (swapType === ETH_TO_OTHERSTOKEN)){
    return getExchangeRate(reserveETH, 18, reserveSEthToken, 18, invert)
  }else if ((swapType === SETH_TO_ETH) | (swapType === OTHERSTOKEN_TO_ETH)){
    return getExchangeRate(reserveSEthToken, 18, reserveETH, 18, invert)
  }
  return undefined
}

export default function ExchangePage({ initialCurrency, sending }) {
  const { t } = useTranslation()
  const { account } = useWeb3Context()

  const addTransaction = useTransactionAdder()

  const [rawSlippage, setRawSlippage] = useState(ALLOWED_SLIPPAGE_DEFAULT)
  const [rawTokenSlippage, setRawTokenSlippage] = useState(TOKEN_ALLOWED_SLIPPAGE_DEFAULT)

  const allowedSlippageBig = ethers.utils.bigNumberify(rawSlippage)
  const tokenAllowedSlippageBig = ethers.utils.bigNumberify(rawTokenSlippage)

  // analytics
  useEffect(() => {
    ReactGA.pageview(window.location.pathname + window.location.search)
  }, [])

  // core swap state
  const [swapState, dispatchSwapState] = useReducer(swapStateReducer, initialCurrency, getInitialSwapState)

  const { independentValue, dependentValue, independentField, inputCurrency, outputCurrency, dependentEthSethRate} = swapState

  const [recipient, setRecipient] = useState({ address: '', name: '' })
  const [recipientError, setRecipientError] = useState()

  // get decimals and exchange address for each of the currency types
  const { symbol: inputSymbol, decimals: inputDecimals} = useTokenDetails(
    inputCurrency
  )
  const { symbol: outputSymbol, decimals: outputDecimals} = useTokenDetails(
    outputCurrency
  )

  // get swap type from the currency types
  const swapType = getSwapType(inputSymbol, outputSymbol)

  const atomicConverterContract = useAtomicSynthetixUniswapConverterContract(ATOMIC_CONVERT_ADDR)

  // get input allowance
  const inputAllowance = useAddressAllowance(account, inputCurrency, ATOMIC_CONVERT_ADDR)

  // fetch reserves for SETH
  //const { reserveETH, reserveToken} = useExchangeReserves(SETH_UNISWAP_EXCHANGE_ADDR)
  const reserveETH = useAddressBalance(SETH_UNISWAP_EXCHANGE_ADDR, 'ETH')
  const reserveToken = useAddressBalance(SETH_UNISWAP_EXCHANGE_ADDR, '0x3731ab0E9FeEE3Ef0C427E874265E8F9a9111e27')

  // get balances for each of the currency types
  const inputBalance = useAddressBalance(account, inputCurrency)
  const outputBalance = useAddressBalance(account, outputCurrency)
  const inputBalanceFormatted = !!(inputBalance && Number.isInteger(inputDecimals))
    ? amountFormatter(inputBalance, inputDecimals, Math.min(4, inputDecimals))
    : ''
  const outputBalanceFormatted = !!(outputBalance && Number.isInteger(outputDecimals))
    ? amountFormatter(outputBalance, outputDecimals, Math.min(4, outputDecimals))
    : ''

  // compute useful transforms of the data above
  const independentDecimals = independentField === INPUT ? inputDecimals : outputDecimals
  const dependentDecimals = independentField === OUTPUT ? inputDecimals : outputDecimals

  // declare/get parsed and formatted versions of input/output values
  const [independentValueParsed, setIndependentValueParsed] = useState()
  const dependentValueFormatted = !!(dependentValue && (dependentDecimals || dependentDecimals === 0))
    ? amountFormatter(dependentValue, dependentDecimals, Math.min(4, dependentDecimals), false)
    : ''
  const inputValueParsed = independentField === INPUT ? independentValueParsed : dependentValue
  const inputValueFormatted = independentField === INPUT ? independentValue : dependentValueFormatted
  const outputValueParsed = independentField === OUTPUT ? independentValueParsed : dependentValue
  const outputValueFormatted = independentField === OUTPUT ? independentValue : dependentValueFormatted

  // validate + parse independent value
  const [independentError, setIndependentError] = useState()
  useEffect(() => {
    if (independentValue && (independentDecimals || independentDecimals === 0)) {
      try {
        const parsedValue = ethers.utils.parseUnits(independentValue, independentDecimals)

        if (parsedValue.lte(ethers.constants.Zero) || parsedValue.gte(ethers.constants.MaxUint256)) {
          throw Error()
        } else {
          setIndependentValueParsed(parsedValue)
          setIndependentError(null)
        }
      } catch {
        setIndependentError(t('inputNotValid'))
      }

      return () => {
        setIndependentValueParsed()
        setIndependentError()
      }
    }
  }, [independentValue, independentDecimals, t])

  // calculate slippage from target rate
  const { minimum: dependentValueMinumum, maximum: dependentValueMaximum } = calculateSlippageBounds(
    dependentValue,
    swapType === STOKEN_TO_STOKEN,
    tokenAllowedSlippageBig,
    allowedSlippageBig
  )

  // validate input allowance + balance
  const [inputError, setInputError] = useState()
  const [showUnlock, setShowUnlock] = useState(false)
  useEffect(() => {
    const inputValueCalculation = independentField === INPUT ? independentValueParsed : dependentValueMaximum
    if (inputBalance && (inputAllowance || inputCurrency === 'ETH') && inputValueCalculation) {
      if (inputBalance.lt(inputValueCalculation)) {
        setInputError(t('insufficientBalance'))
      } else if (inputCurrency !== 'ETH' && inputAllowance.lt(inputValueCalculation)) {
        setInputError(t('unlockTokenCont'))
        setShowUnlock(true)
      } else {
        setInputError(null)
        setShowUnlock(false)
      }

      return () => {
        setInputError()
        setShowUnlock(false)
      }
    }
  }, [independentField, independentValueParsed, dependentValueMaximum, inputBalance, inputCurrency, inputAllowance, t])

  // calculate dependent value
  useEffect(() => {
    const amount = independentValueParsed
        
    try {
      const ethBytes4 = ethers.utils.formatBytes32String('ETH').substring(0,10)
      const sEthBytes4 = ethers.utils.formatBytes32String('sETH').substring(0,10)
      const srcBytes4 = ethers.utils.formatBytes32String(inputSymbol).substring(0,10)
      const dstBytes4 = ethers.utils.formatBytes32String(outputSymbol).substring(0,10)
      let method, args, args2
      if (independentField === INPUT){
        console.log("1111111111111111")
        method = atomicConverterContract.inputPrice
        args = [srcBytes4, amount, dstBytes4]
        if (inputSymbol === 'ETH'){
          args2 = [ethBytes4, amount, sEthBytes4]
        }else if (inputSymbol === 'sETH'){
          args2 = [sEthBytes4, amount, ethBytes4]
        }
      }else{
        console.log("22222222222222222")
        method = atomicConverterContract.outputPrice
        args = [srcBytes4, dstBytes4, amount]
        if (inputSymbol === 'ETH'){
          args2 = [ethBytes4, sEthBytes4, amount]
        }else if (inputSymbol === 'sETH'){
          args2 = [sEthBytes4, ethBytes4, amount]
        }
      }
      method(...args).then(response => {
        const resultAmt = ethers.utils.bigNumberify(response)
        if (resultAmt.lte(ethers.constants.Zero)) {
          throw Error()
        }
        dispatchSwapState({ type: 'UPDATE_DEPENDENT', payload: resultAmt})
      })
      if (args2) {
        method(...args2).then(response => {
          const resultAmt = ethers.utils.bigNumberify(response)
          if (resultAmt.lte(ethers.constants.Zero)) {
            throw Error()
          }
          dispatchSwapState({ type: 'UPDATE_DEPENDENT_RATE', payload: resultAmt})
        })
      } 
    } catch {
      setIndependentError(t('insufficientLiquidity'))
    }
    return () => {
      dispatchSwapState({ type: 'UPDATE_DEPENDENT', payload: '' })
    }
  }, [
    independentValueParsed,
    swapType,
    independentField,
    inputSymbol,
    outputSymbol,
    atomicConverterContract,
    t
  ])

  const [inverted, setInverted] = useState(false)
  const ethSethExchangeRate = getExchangeRate(inputValueParsed, inputDecimals, dependentEthSethRate, outputDecimals)
  const exchangeRate  = getExchangeRate(inputValueParsed, inputDecimals, outputValueParsed, outputDecimals)

  //const exchangeRate = getExchangeRate(inputValueParsed, inputDecimals, outputValueParsed, outputDecimals)
  const exchangeRateInverted = getExchangeRate(inputValueParsed, inputDecimals, outputValueParsed, outputDecimals, true)

  const marketRate = getMarketRate(
    swapType,
    reserveETH,
    reserveToken
  )
/*
    const marketRate = getMarketRate(
    swapType,
    reserveETH,
    reserveToken,
    inputDecimals,
   // outputReserveETH,
   // outputReserveToken,
    outputDecimals
  )
*/
  
  console.log("dependentEthSethRate:           " + dependentEthSethRate)
  console.log("independentValue    :           " + independentValueParsed)
  console.log("dependentValue:                 " + dependentValue)
  console.log("exchangeRate:                   "+exchangeRate)
  console.log("exchangeRateInvert:             "+exchangeRateInverted)
  console.log("exchanethSethExchangeRategeRate:"+ethSethExchangeRate)
  console.log("marketRate:                     " + marketRate)
  
  const percentSlippage =
    ethSethExchangeRate && marketRate
      ? ethSethExchangeRate
          .sub(marketRate)
          .abs()
          .mul(ethers.utils.bigNumberify(10).pow(ethers.utils.bigNumberify(18)))
          .div(marketRate)
          .sub(ethers.utils.bigNumberify(3).mul(ethers.utils.bigNumberify(10).pow(ethers.utils.bigNumberify(15))))
      : undefined
  const percentSlippageFormatted = percentSlippage && amountFormatter(percentSlippage, 16, 2)
  const slippageWarning =
    percentSlippage &&
    percentSlippage.gte(ethers.utils.parseEther('.05')) &&
    percentSlippage.lt(ethers.utils.parseEther('.2')) // [5% - 20%)
  const highSlippageWarning = percentSlippage && percentSlippage.gte(ethers.utils.parseEther('.2')) // [20+%

  const isValid = sending
    ? exchangeRate && inputError === null && independentError === null && recipientError === null
    : exchangeRate && inputError === null && independentError === null

  const estimatedText = `(${t('estimated')})`
  function formatBalance(value) {
    return `Balance: ${value}`
  }

  async function onSwap() {
    const deadline = Math.ceil(Date.now() / 1000) + DEADLINE_FROM_NOW

    let estimate, method, args, value
    if (independentField === INPUT) {
      ReactGA.event({
        category: `${swapType}`,
        action: sending ? 'TransferInput' : 'SwapInput'
      })

      if (swapType === ETH_TO_SETH) {
        estimate = atomicConverterContract.estimate.ethToSethInput
        method = atomicConverterContract.ethToSethInput
        args = sending
          ? [dependentValueMinumum, deadline, recipient.address]
          : [dependentValueMinumum, deadline, ethers.constants.AddressZero]
        value = independentValueParsed
      } else if (swapType === SETH_TO_ETH) {
        estimate = atomicConverterContract.estimate.sEthToEthInput
        method = atomicConverterContract.sEthToEthInput
        args = sending
          ? [independentValueParsed, dependentValueMinumum, deadline, recipient.address]
          : [independentValueParsed, dependentValueMinumum, deadline, ethers.constants.AddressZero]
        value = ethers.constants.Zero
      } else if (swapType === ETH_TO_OTHERSTOKEN) {
        
        estimate = atomicConverterContract.estimate.ethToOtherTokenInput
        method = atomicConverterContract.ethToOtherTokenInput
        const outputKey = ethers.utils.formatBytes32String(outputSymbol).substring(0,10)
        args = sending
          ? [dependentValueMinumum, outputKey, deadline, recipient.address]
          : [dependentValueMinumum, outputKey, deadline, ethers.constants.AddressZero]
        value = independentValueParsed

      }else if (swapType === OTHERSTOKEN_TO_ETH) {
        estimate = atomicConverterContract.estimate.otherTokenToEthInput
        method = atomicConverterContract.otherTokenToEthInput
        const inputKey = ethers.utils.formatBytes32String(inputSymbol).substring(0,10)
        args = sending
          ? [inputKey, independentValueParsed, dependentValueMinumum, deadline, recipient.address]
          : [inputKey, independentValueParsed, dependentValueMinumum, deadline, ethers.constants.AddressZero]
        value = ethers.constants.Zero
      }else if (swapType === STOKEN_TO_STOKEN){
        estimate = atomicConverterContract.estimate.sTokenToStokenInput
        method = atomicConverterContract.sTokenToStokenInput
        const inputKey = ethers.utils.formatBytes32String(inputSymbol).substring(0,10)
        const outputKey = ethers.utils.formatBytes32String(outputSymbol).substring(0,10)
        args = sending
          ? [inputKey, independentValueParsed, outputKey, dependentValueMinumum, deadline, recipient.address]
          : [inputKey, independentValueParsed, outputKey, dependentValueMinumum, deadline, ethers.constants.AddressZero]
        value = ethers.constants.Zero
      }
    } else if (independentField === OUTPUT) {
      ReactGA.event({
        category: `${swapType}`,
        action: sending ? 'TransferOutput' : 'SwapOutput'
      })

      if (swapType === ETH_TO_SETH) {
        estimate = atomicConverterContract.estimate.ethToSethOutput
        method = atomicConverterContract.ethToSethOutput
        args = sending
          ? [independentValueParsed, deadline, recipient.address]
          : [independentValueParsed, deadline, ethers.constants.AddressZero]
        value = dependentValueMaximum
      } else if (swapType === SETH_TO_ETH) {
        estimate = atomicConverterContract.estimate.sEthToEthOutput
        method = atomicConverterContract.sEthToEthOutput
        args = sending
          ? [independentValueParsed, dependentValueMaximum, deadline, recipient.address]
          : [independentValueParsed, dependentValueMaximum, deadline, ethers.constants.AddressZero]
        value = ethers.constants.Zero
      } else if (swapType === ETH_TO_OTHERSTOKEN) {
        estimate = atomicConverterContract.estimate.ethToOtherTokenOutput
        method = atomicConverterContract.ethToOtherTokenOutput
        const outputKey = ethers.utils.formatBytes32String(outputSymbol).substring(0,10)
        args = sending
          ? [dependentValueMaximum, outputKey, deadline, recipient.address]
          : [dependentValueMaximum, outputKey, deadline, ethers.constants.AddressZero]
        value = independentValueParsed
      }else if (swapType === OTHERSTOKEN_TO_ETH) {
        estimate = atomicConverterContract.estimate.otherTokenToEthOutput
        method = atomicConverterContract.otherTokenToEthOutput
        const inputKey = ethers.utils.formatBytes32String(inputSymbol).substring(0,10)
        args = sending
          ? [inputKey, dependentValueMaximum, independentValueParsed, deadline, recipient.address] 
          : [inputKey, dependentValueMaximum, independentValueParsed, deadline, ethers.constants.AddressZero]
        value = ethers.constants.Zero
      }else if (swapType === STOKEN_TO_STOKEN){
        estimate = atomicConverterContract.estimate.sTokenToStokenOutput
        method = atomicConverterContract.sTokenToStokenOutput
        const inputKey = ethers.utils.formatBytes32String(inputSymbol).substring(0,10)
        const outputKey = ethers.utils.formatBytes32String(outputSymbol).substring(0,10)
        args = sending
          ? [inputKey, dependentValueMaximum, outputKey, independentValueParsed, deadline, recipient.address]
          : [inputKey, dependentValueMaximum, outputKey, independentValueParsed, deadline, ethers.constants.AddressZero]
        value = ethers.constants.Zero
      }
    }
    console.log(args)
    console.log("value:" + value)
    console.log("SWAP TYPE:" + swapType)
    //const estimatedGasLimit = await estimate(...args, { value })
    const estimatedGasLimit = ethers.utils.bigNumberify(6000000)
    //console.log("estimatedGasLimit:" + estimatedGasLimit)
    method(...args, { value, gasLimit: calculateGasMargin(estimatedGasLimit, GAS_MARGIN) }).then(response => {
      addTransaction(response)
    })
  }
  
  const [customSlippageError, setcustomSlippageError] = useState('')

  const allBalances = useFetchAllBalances()

  return (
    <>
      <CurrencyInputPanel
        title={t('input')}
        allBalances={allBalances}
        description={inputValueFormatted && independentField === OUTPUT ? estimatedText : ''}
        extraText={inputBalanceFormatted && formatBalance(inputBalanceFormatted)}
        extraTextClickHander={() => {
          if (inputBalance && inputDecimals) {
            const valueToSet = inputCurrency === 'ETH' ? inputBalance.sub(ethers.utils.parseEther('.1')) : inputBalance
            if (valueToSet.gt(ethers.constants.Zero)) {
              dispatchSwapState({
                type: 'UPDATE_INDEPENDENT',
                payload: { value: amountFormatter(valueToSet, inputDecimals, inputDecimals, false), field: INPUT }
              })
            }
          }
        }}
        onCurrencySelected={inputCurrency => {
          dispatchSwapState({ type: 'SELECT_CURRENCY', payload: { currency: inputCurrency, field: INPUT } })
        }}
        onValueChange={inputValue => {
          dispatchSwapState({ type: 'UPDATE_INDEPENDENT', payload: { value: inputValue, field: INPUT } })
        }}
        showUnlock={showUnlock}
        selectedTokens={[inputCurrency, outputCurrency]}
        selectedTokenAddress={inputCurrency}
        value={inputValueFormatted}
        errorMessage={inputError ? inputError : independentField === INPUT ? independentError : ''}
      />
      <OversizedPanel>
        <DownArrowBackground>
          <DownArrow
            onClick={() => {
              dispatchSwapState({ type: 'FLIP_INDEPENDENT' })
            }}
            clickable
            alt="swap"
            active={isValid}
          />
        </DownArrowBackground>
      </OversizedPanel>
      <CurrencyInputPanel
        title={t('output')}
        allBalances={allBalances}
        description={outputValueFormatted && independentField === INPUT ? estimatedText : ''}
        extraText={outputBalanceFormatted && formatBalance(outputBalanceFormatted)}
        onCurrencySelected={outputCurrency => {
          dispatchSwapState({ type: 'SELECT_CURRENCY', payload: { currency: outputCurrency, field: OUTPUT } })
        }}
        onValueChange={outputValue => {
          dispatchSwapState({ type: 'UPDATE_INDEPENDENT', payload: { value: outputValue, field: OUTPUT } })
        }}
        selectedTokens={[inputCurrency, outputCurrency]}
        selectedTokenAddress={outputCurrency}
        value={outputValueFormatted}
        errorMessage={independentField === OUTPUT ? independentError : ''}
        disableUnlock
      />
      {sending ? (
        <>
          <OversizedPanel>
            <DownArrowBackground>
              <DownArrow active={isValid} alt="arrow" />
            </DownArrowBackground>
          </OversizedPanel>
          <AddressInputPanel onChange={setRecipient} onError={setRecipientError} />
        </>
      ) : (
        ''
      )}
      <OversizedPanel hideBottom>
        <ExchangeRateWrapper
          onClick={() => {
            setInverted(inverted => !inverted)
          }}
        >
          <ExchangeRate>{t('exchangeRate')}</ExchangeRate>
          {inverted ? (
            <span>
              {exchangeRate
                ? `1 ${inputSymbol} = ${amountFormatter(exchangeRate, 18, 4, false)} ${outputSymbol}`
                : ' - '}
            </span>
          ) : (
            <span>
              {exchangeRate
                ? `1 ${outputSymbol} = ${amountFormatter(exchangeRateInverted, 18, 4, false)} ${inputSymbol}`
                : ' - '}
            </span>
          )}
        </ExchangeRateWrapper>
      </OversizedPanel>
      <TransactionDetails
        account={account}
        setRawSlippage={setRawSlippage}
        setRawTokenSlippage={setRawTokenSlippage}
        rawSlippage={rawSlippage}
        slippageWarning={slippageWarning}
        highSlippageWarning={highSlippageWarning}
        inputError={inputError}
        independentError={independentError}
        inputCurrency={inputCurrency}
        outputCurrency={outputCurrency}
        independentValue={independentValue}
        independentValueParsed={independentValueParsed}
        independentField={independentField}
        INPUT={INPUT}
        inputValueParsed={inputValueParsed}
        outputValueParsed={outputValueParsed}
        inputSymbol={inputSymbol}
        outputSymbol={outputSymbol}
        dependentValueMinumum={dependentValueMinumum}
        dependentValueMaximum={dependentValueMaximum}
        dependentDecimals={dependentDecimals}
        independentDecimals={independentDecimals}
        percentSlippageFormatted={percentSlippageFormatted}
        setcustomSlippageError={setcustomSlippageError}
        recipientAddress={recipient.address}
        sending={sending}
      />
      <Flex>
        <Button
          disabled={!isValid || customSlippageError === 'invalid'}
          onClick={onSwap}
          warning={highSlippageWarning || customSlippageError === 'warning'}
        >
          {sending
            ? highSlippageWarning || customSlippageError === 'warning'
              ? t('sendAnyway')
              : t('send')
            : highSlippageWarning || customSlippageError === 'warning'
            ? t('swapAnyway')
            : t('swap')}
        </Button>
      </Flex>
    </>
  )
}
