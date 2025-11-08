"use client"

import { useChainId } from "wagmi"
import { useQuery } from "@tanstack/react-query"
import { getContractsForChain } from "@/lib/contracts"
import { getPublicClient } from "@wagmi/core"
import { config } from "@/lib/wagmiConfig"

export interface LeaderboardRow {
  rank: number
  donor: `0x${string}`
  totalDonated: bigint
}

async function fetchLeaderboardData(chainId: number) {
  const contracts = getContractsForChain(chainId)

  if (!contracts) {
    throw new Error("Contracts not found for this chain")
  }

  if (contracts.leaderboard === "0x0000000000000000000000000000000000000000") {
    return []
  }

  const client = getPublicClient(config, { chainId })

  const donationLogs = await client.getLogs({
    address: contracts.leaderboard,
    event: {
      type: "event",
      name: "DonationNotified",
      inputs: [
        { name: "donor", type: "address", indexed: true },
        { name: "amount", type: "uint256", indexed: false },
        { name: "planId", type: "uint8", indexed: false },
      ],
    },
    fromBlock: 0n,
    toBlock: "latest",
  })

  const donationMap = new Map<`0x${string}`, bigint>()

  for (const log of donationLogs) {
    const { donor, amount } = (log as { args: { donor: `0x${string}`; amount: bigint } }).args
    const currentTotal = donationMap.get(donor) ?? 0n
    donationMap.set(donor, currentTotal + amount)
  }

  return Array.from(donationMap.entries())
    .sort(([, a], [, b]) => (a > b ? -1 : 1))
    .map<LeaderboardRow>(([donor, totalDonated], index) => ({
      rank: index + 1,
      donor,
      totalDonated,
    }))
}

export function useLeaderboardData() {
  const chainId = useChainId()

  return useQuery({
    queryKey: ["leaderboardData", chainId],
    queryFn: () => {
      if (!chainId) {
        throw new Error("Wallet not connected")
      }

      return fetchLeaderboardData(chainId)
    },
    enabled: Boolean(chainId),
    staleTime: 60_000,
  })
}

