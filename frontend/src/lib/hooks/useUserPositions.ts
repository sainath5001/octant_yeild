"use client"

import { useAccount, useChainId } from "wagmi"
import { useQuery } from "@tanstack/react-query"
import { getContractsForChain } from "@/lib/contracts"
import { getPublicClient } from "@wagmi/core"
import { config } from "@/lib/wagmiConfig"

async function fetchUserPositions(chainId: number, userAddress: `0x${string}`) {
  const contracts = getContractsForChain(chainId)

  if (!contracts) {
    throw new Error("Contracts not found for this chain")
  }

  if (contracts.aggregatorVault === "0x0000000000000000000000000000000000000000") {
    return []
  }

  const client = getPublicClient(config, { chainId })

  const depositLogs = await client.getLogs({
    address: contracts.aggregatorVault,
    event: {
      type: "event",
      name: "Deposited",
      inputs: [
        { name: "positionId", type: "uint256", indexed: true },
        { name: "receiver", type: "address", indexed: true },
      ],
    },
    args: {
      receiver: userAddress,
    },
    fromBlock: 0n,
    toBlock: "latest",
  })

  const withdrawLogs = await client.getLogs({
    address: contracts.aggregatorVault,
    event: {
      type: "event",
      name: "Withdrawn",
      inputs: [{ name: "positionId", type: "uint256", indexed: true }],
    },
    fromBlock: 0n,
    toBlock: "latest",
  })

  const withdrawnPositionIds = new Set(
    withdrawLogs.map((log) => (log as { args: { positionId: bigint } }).args.positionId),
  )

  const activePositionIds = depositLogs
    .map((log) => (log as { args: { positionId: bigint } }).args.positionId)
    .filter((id) => !withdrawnPositionIds.has(id))

  return [...new Set(activePositionIds)]
}

export function useUserPositions() {
  const { address } = useAccount()
  const chainId = useChainId()

  return useQuery({
    queryKey: ["userPositions", address, chainId],
    queryFn: () => {
      if (!address || !chainId) {
        throw new Error("Wallet not connected")
      }

      return fetchUserPositions(chainId, address)
    },
    enabled: Boolean(address && chainId),
    staleTime: 15_000,
  })
}

