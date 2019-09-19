import React, { createContext, useContext, useReducer, useMemo, useCallback, useEffect } from 'react'
import { useWeb3Context } from 'web3-react'
import { ethers } from 'ethers'

import {
  isAddress,
  getTokenName,
  getTokenSymbol,
  getTokenDecimals,
  safeAccess
} from '../utils'

const NAME = 'name'
const SYMBOL = 'symbol'
const DECIMALS = 'decimals'

const UPDATE = 'UPDATE'

const ETH = {
  ETH: {
    [NAME]: 'Ethereum',
    [SYMBOL]: 'ETH',
    [DECIMALS]: 18
  }
}

const INITIAL_TOKENS_CONTEXT = {

    4: {
    '0x2a27a3113368836b2BE598a4BB9a0d4D7A734305': {
      [NAME]: 'Synthetix Synth sETH Token',
      [SYMBOL]: 'sETH',
      [DECIMALS]: 18
    },
    '0x088256945480c884C067a8Bc98A72A1C984f826B': {
      [NAME]: 'Synthetix Synth sAUD Token',
      [SYMBOL]: 'sAUD',
      [DECIMALS]: 18
    },
    '0x406555dbF02e9E4df9AdeAeC9DA76ABeED8C1BC3': {
      [NAME]: 'Synthetix Synth sBNB Token',
      [SYMBOL]: 'sBNB',
      [DECIMALS]: 18
    },
    '0x8cAf6308D571a0D437ea74F80D7B7f5b7d9f9F0b': {
      [NAME]: 'Synthetix Synth sBTC Token',
      [SYMBOL]: 'sBTC',
      [DECIMALS]: 18
    },
    '0x9D377791B8139E790E9BceE3B9fEf3F041B85Ae5': {
      [NAME]: 'Synthetix Synth sCEX Token',
      [SYMBOL]: 'sCEX',
      [DECIMALS]: 18
    },
    '0xe2B26511C64FE18Acc0BE8EA7c888cDFcacD846E': {
      [NAME]: 'Synthetix Synth sCHF Token',
      [SYMBOL]: 'sCHF',
      [DECIMALS]: 18
    },
    '0x56000B741EC31C11acB10390404A9190F8E62EcB': {
      [NAME]: 'Synthetix Synth sEUR Token',
      [SYMBOL]: 'sEUR',
      [DECIMALS]: 18
    },
    '0x23F608ACc41bd7BCC617a01a9202214EE305439a': {
      [NAME]: 'Synthetix Synth sGBP Token',
      [SYMBOL]: 'sGBP',
      [DECIMALS]: 18
    },
    '0x2e542fA43A19F3F07230dD125f9f81411141362F': {
      [NAME]: 'Synthetix Synth sJPY Token',
      [SYMBOL]: 'sJPY',
      [DECIMALS]: 18
    },
    '0x075adeAF9f594c76149b5364bf3143c2e878361d': {
      [NAME]: 'Synthetix Synth sMKR Token',
      [SYMBOL]: 'sMKR',
      [DECIMALS]: 18
    },
    '0x8Fa27a5031684A84961B56cF80D9fFD0c7b6faDE': {
      [NAME]: 'Synthetix Synth sTRX Token',
      [SYMBOL]: 'sTRK',
      [DECIMALS]: 18
    },
    '0x95b92876a85c64Ede4a159161D502FCAeDAFc7C8': {
      [NAME]: 'Synthetix Synth sUSD Token',
      [NAME]: 'Synth sUSD',
      [SYMBOL]: 'sUSD',
      [DECIMALS]: 18
    },
    '0x7c8Aeffdd9978fdcd0B406ffe4a82d50f0c9AC88': {
      [NAME]: 'Synthetix Synth sXAG Token',
      [SYMBOL]: 'sXAG',
      [DECIMALS]: 18
    },
    '0xCbB8dFa37244Ca887DE38b2E496e968fB0571f06': {
      [NAME]: 'Synthetix Synth sXAU Token',
      [SYMBOL]: 'sXAU',
      [DECIMALS]: 18
    },
    '0xE340Cc3e613DB18E1A40De25aA962024368Fa138': {
      [NAME]: 'Synthetix Synth sXTZ Token',
      [SYMBOL]: 'sXTZ',
      [DECIMALS]: 18
    },

    '0xC1701AbD559FC263829CA3917d03045F95b5224A': {
      [NAME]: 'Synthetix Synth iBNB Token',
      [SYMBOL]: 'iBNB',
      [DECIMALS]: 18
    },
    '0x8B5c7bA225658d514e970723B774E78834323229': {
      [NAME]: 'Synthetix Synth iBTC Token',
      [SYMBOL]: 'iBTC',
      [DECIMALS]: 18
    },
    '0x8731Ed67FC19B927bF7736296b78ca860fC1aaBF': {
      [NAME]: 'Synthetix Synth iCEX Token',
      [SYMBOL]: 'iCEX',
      [DECIMALS]: 18
    },
    '0x5D2532a4e37Aafb401779b8f4E7587c2B205B4Cc': {
      [NAME]: 'Synthetix Synth iETH Token',
      [SYMBOL]: 'iETH',
      [DECIMALS]: 18
    },
    '0xc50a0C1138302d68A203c6629Edf059A3ABaD346': {
      [NAME]: 'Synthetix Synth iMKR Token',
      [SYMBOL]: 'iMKR',
      [DECIMALS]: 18
    },
    '0xA6f96D7E0ab295CC38B24e118b2F961919eF8d51': {
      [NAME]: 'Synthetix Synth iTRX Token',
      [SYMBOL]: 'iTRX',
      [DECIMALS]: 18
    },
    '0x17ea940CAbC0e070eaA6E8e2b523000Cc85D58fD': {
      [NAME]: 'Synthetix Synth iXTZ Token',
      [SYMBOL]: 'iXTZ',
      [DECIMALS]: 18
    },

  }
}

const TokensContext = createContext()

function useTokensContext() {
  return useContext(TokensContext)
}

function reducer(state, { type, payload }) {
  switch (type) {
    case UPDATE: {
      const { networkId, tokenAddress, name, symbol, decimals } = payload
      return {
        ...state,
        [networkId]: {
          ...(safeAccess(state, [networkId]) || {}),
          [tokenAddress]: {
            [NAME]: name,
            [SYMBOL]: symbol,
            [DECIMALS]: decimals
          }
        }
      }
    }
    default: {
      throw Error(`Unexpected action type in TokensContext reducer: '${type}'.`)
    }
  }
}

export default function Provider({ children }) {
  const [state, dispatch] = useReducer(reducer, INITIAL_TOKENS_CONTEXT)

  const update = useCallback((networkId, tokenAddress, name, symbol, decimals) => {
    dispatch({ type: UPDATE, payload: { networkId, tokenAddress, name, symbol, decimals } })
  }, [])

  return (
    <TokensContext.Provider value={useMemo(() => [state, { update }], [state, update])}>
      {children}
    </TokensContext.Provider>
  )
}

export function useTokenDetails(tokenAddress) {
  const { networkId, library } = useWeb3Context()

  const [state, { update }] = useTokensContext()
  const allTokensInNetwork = { ...ETH, ...(safeAccess(state, [networkId]) || {}) }
  const { [NAME]: name, [SYMBOL]: symbol, [DECIMALS]: decimals} =
    safeAccess(allTokensInNetwork, [tokenAddress]) || {}

  useEffect(() => {
    if (
      isAddress(tokenAddress) &&
      (name === undefined || symbol === undefined || decimals === undefined) &&
      (networkId || networkId === 0) &&
      library
    ) {
      let stale = false

      const namePromise = getTokenName(tokenAddress, library).catch(() => null)
      const symbolPromise = getTokenSymbol(tokenAddress, library).catch(() => null)
      const decimalsPromise = getTokenDecimals(tokenAddress, library).catch(() => null)

      Promise.all([namePromise, symbolPromise, decimalsPromise]).then(
        ([resolvedName, resolvedSymbol, resolvedDecimals]) => {
          if (!stale) {
            update(networkId, tokenAddress, resolvedName, resolvedSymbol, resolvedDecimals)
          }
        }
      )
      return () => {
        stale = true
      }
    }
  }, [tokenAddress, name, symbol, decimals, networkId, library, update])

  return { name, symbol, decimals }
}

export function useAllTokenDetails() {
  const { networkId } = useWeb3Context()

  const [state] = useTokensContext()
  const tokenDetails = { ...ETH, ...(safeAccess(state, [networkId]) || {}) }

  return Object.keys(tokenDetails)
        .filter(
          tokenAddress =>
            tokenAddress === 'ETH' ||
            (safeAccess(tokenDetails, [tokenAddress]) &&
              safeAccess(tokenDetails, [tokenAddress]) !== ethers.constants.AddressZero)
        )
        .reduce((accumulator, tokenAddress) => {
          accumulator[tokenAddress] = tokenDetails[tokenAddress]
          return accumulator
        }, {})
}
