"use client"

import { useEffect, useMemo, useState } from "react"
import { toast } from "sonner"
import {
  useAccount,
  useReadContract,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi"
import { aggregatorVaultABI, getContractsForChain } from "@/lib/contracts"
import { formatTimestamp, formatTokenAmount } from "@/lib/utils"
import { Card, CardHeader, CardTitle, CardContent, CardFooter } from "@/components/ui/card"
import { Button } from "@/components/ui/button"

interface PortfolioCardProps {
  positionId: bigint
}

export function PortfolioCard({ positionId }: PortfolioCardProps) {
  const { address, chainId } = useAccount()
  const contracts = useMemo(() => (chainId ? getContractsForChain(chainId) : undefined), [chainId])
  const [isClient, setIsClient] = useState(false)

  useEffect(() => {
    setIsClient(true)
  }, [])

  const {
    data: position,
    isLoading: isLoadingPosition,
    refetch,
  } = useReadContract({
    abi: aggregatorVaultABI,
    address: contracts?.aggregatorVault,
    functionName: "positions",
    args: [positionId],
    query: {
      enabled: Boolean(contracts && aggregatorVaultABI.length > 0),
    },
  })

  const {
    writeContractAsync,
    data: hash,
    isPending,
  } = useWriteContract()

  const { isLoading: isConfirming } = useWaitForTransactionReceipt({
    hash,
    onSuccess: (receipt) => {
      toast.success("Withdrawal Confirmed!", {
        description: `Tx: ${receipt.transactionHash.slice(0, 10)}...`,
      })
      refetch()
    },
  })

  if (!isClient || isLoadingPosition) {
    return (
      <Card className="flex h-64 items-center justify-center">
        <p>Loading position...</p>
      </Card>
    )
  }

  if (!position) {
    return (
      <Card className="flex h-64 items-center justify-center">
        <p>Position not found.</p>
      </Card>
    )
  }

  const [owner, amountDeposited, , donationBps, lockupEndTimestamp] = position as [
    `0x${string}`,
    bigint,
    bigint,
    number,
    bigint,
  ]

  const now = BigInt(Math.floor(Date.now() / 1000))
  const isLocked = now < lockupEndTimestamp
  const isLoading = isPending || isConfirming

  async function handleWithdraw() {
    if (!contracts || !address || aggregatorVaultABI.length === 0) {
      toast.error("Wallet not connected")
      return
    }

    if (owner.toLowerCase() !== address.toLowerCase()) {
      toast.error("You do not own this position")
      return
    }

    const dismiss = toast.loading("Sending withdrawal transaction...")
    try {
      await writeContractAsync({
        abi: aggregatorVaultABI,
        address: contracts.aggregatorVault,
        functionName: "withdraw",
        args: [positionId, address],
      })
      toast.success("Withdrawal submitted")
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unknown error"
      toast.error("Withdrawal failed", { description: message })
    } finally {
      toast.dismiss(dismiss)
    }
  }

  return (
    <Card className="flex h-full flex-col justify-between">
      <CardHeader>
        <CardTitle>Position #{positionId.toString()}</CardTitle>
      </CardHeader>
      <CardContent className="space-y-2">
        <p>
          <span className="font-medium text-muted-foreground">Amount:</span>{" "}
          {formatTokenAmount(amountDeposited, 6)} USDC
        </p>
        <p>
          <span className="font-medium text-muted-foreground">Donation:</span>{" "}
          {donationBps / 100}%
        </p>
        <p>
          <span className="font-medium text-muted-foreground">Unlocks:</span>{" "}
          {formatTimestamp(lockupEndTimestamp)}
        </p>
      </CardContent>
      <CardFooter>
        <Button
          className="w-full bg-purple-600 hover:bg-purple-500"
          disabled={isLocked || isLoading}
          onClick={handleWithdraw}
        >
          {isLoading ? "Withdrawing..." : isLocked ? "Locked" : "Withdraw"}
        </Button>
      </CardFooter>
    </Card>
  )
}

