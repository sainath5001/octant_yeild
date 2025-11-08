// @ts-nocheck

import { mainnet } from "wagmi/chains"

/**
 * TODO: Build the backend contracts (`pnpm --filter backend forge build`) to generate
 * JSON artifacts under `../backend/out/` and replace the placeholder ABIs below with
 * the concrete contract ABIs:
 *  - AggregatorVault.sol/AggregatorVault.json
 *  - Leaderboard.sol/Leaderboard.json
 *  - ERC20 token JSON (e.g., IERC20)
 */

export const aggregatorVaultABI = [] as const

export const leaderboardABI = [] as const

export const erc20ABI = [
  {
    stateMutability: "view",
    type: "function",
    name: "allowance",
    inputs: [
      { name: "owner", type: "address" },
      { name: "spender", type: "address" },
    ],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    name: "approve",
    inputs: [
      { name: "spender", type: "address" },
      { name: "value", type: "uint256" },
    ],
    outputs: [{ name: "", type: "bool" }],
  },
] as const

const SEPOLIA_CHAIN_ID = 11155111

export const contracts = {
  [SEPOLIA_CHAIN_ID]: {
    aggregatorVault: "0x0000000000000000000000000000000000000000",
    leaderboard: "0x0000000000000000000000000000000000000000",
    usdcToken: "0x0000000000000000000000000000000000000000",
  },
  [mainnet.id]: {
    aggregatorVault: "0x0000000000000000000000000000000000000000",
    leaderboard: "0x0000000000000000000000000000000000000000",
    usdcToken: "0x0000000000000000000000000000000000000000",
  },
} as const

export function getContractsForChain(chainId: number) {
  return contracts[chainId as keyof typeof contracts]
}

