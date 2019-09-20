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
    '0x095503392798d9746cD9c0FDdA5792cC13F0D981': {
      [NAME]: 'Synthetix Synth sBTC Token',
      [SYMBOL]: 'sBTC',
      [DECIMALS]: 18
    },
    '0x7DBC8715595cbca834928F64d05a0Af8a8ade528': {
      [NAME]: 'Synthetix Synth sCEX Token',
      [SYMBOL]: 'sCEX',
      [DECIMALS]: 18
    },
    '0xF778Ec504245EfE1eA010C5C3E50b6F5f5E117da': {
      [NAME]: 'Synthetix Synth sCHF Token',
      [SYMBOL]: 'sCHF',
      [DECIMALS]: 18
    },
    '0x72D1342775d090B3F6Faef23999ddf9f06c16Eb8': {
      [NAME]: 'Synthetix Synth sEUR Token',
      [SYMBOL]: 'sEUR',
      [DECIMALS]: 18
    },
    '0xEF8673f2A5ec125Ab993932cad269561a15C2C74': {
      [NAME]: 'Synthetix Synth sGBP Token',
      [SYMBOL]: 'sGBP',
      [DECIMALS]: 18
    },
    '0x84965DCa28c4Eb9dE61d80f80e811eA12BE1c819': {
      [NAME]: 'Synthetix Synth sJPY Token',
      [SYMBOL]: 'sJPY',
      [DECIMALS]: 18
    },
    '0xDDEfe42790f2dEC7b0C37D4399884eFceA5361b1': {
      [NAME]: 'Synthetix Synth sMKR Token',
      [SYMBOL]: 'sMKR',
      [DECIMALS]: 18
    },
    '0x06eb70653FDf56E5A0dc5D48602A11C175515Cb5': {
      [NAME]: 'Synthetix Synth sTRX Token',
      [SYMBOL]: 'sTRK',
      [DECIMALS]: 18
    },
    '0x548c18a49a66Ad1238e17824C18B0b9Be35fB604': {
      [NAME]: 'Synthetix Synth sUSD Token',
      [NAME]: 'Synth sUSD',
      [SYMBOL]: 'sUSD',
      [DECIMALS]: 18
    },
    '0x09400Ec683F70174E1217d6dcdBf42448E8De5d6': {
      [NAME]: 'Synthetix Synth sXAG Token',
      [SYMBOL]: 'sXAG',
      [DECIMALS]: 18
    },
    '0xE00F85613eDdB11328e8922710C4cF2e0c7E5D88': {
      [NAME]: 'Synthetix Synth sXAU Token',
      [SYMBOL]: 'sXAU',
      [DECIMALS]: 18
    },
    '0x55A91C51Db13420A28E8A29239D4Dd1E4e4D1EdF': {
      [NAME]: 'Synthetix Synth sXTZ Token',
      [SYMBOL]: 'sXTZ',
      [DECIMALS]: 18
    },

    '0xC1701AbD559FC263829CA3917d03045F95b5224A': {
      [NAME]: 'Synthetix Synth iBNB Token',
      [SYMBOL]: 'iBNB',
      [DECIMALS]: 18
    },
    '0xf92b129ae126e2Fdb7a5812C9533eDE23f8AA36D': {
      [NAME]: 'Synthetix Synth iBTC Token',
      [SYMBOL]: 'iBTC',
      [DECIMALS]: 18
    },
    '0xd528D731dc0C3763A9064c9A5d56c6569bb65923': {
      [NAME]: 'Synthetix Synth iCEX Token',
      [SYMBOL]: 'iCEX',
      [DECIMALS]: 18
    },
    '0xF37EbCDCBd5eD96fc66027069b570db9f9Dd185d': {
      [NAME]: 'Synthetix Synth iETH Token',
      [SYMBOL]: 'iETH',
      [DECIMALS]: 18
    },
    '0x0Df1B6d92feBCA3B2793AfA3649868991CC4901D': {
      [NAME]: 'Synthetix Synth iMKR Token',
      [SYMBOL]: 'iMKR',
      [DECIMALS]: 18
    },
    '0x5fF1b87fBfDE943568C533f2a5f78F8d9C00539b': {
      [NAME]: 'Synthetix Synth iTRX Token',
      [SYMBOL]: 'iTRX',
      [DECIMALS]: 18
    },
    '0x93516bE2862946798ee6a8a3a95350D3280B7B03': {
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
