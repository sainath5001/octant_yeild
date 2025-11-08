"use client"

import { useAccount } from "wagmi"
import { useUserPositions } from "@/lib/hooks/useUserPositions"
import { PortfolioCard } from "@/components/PortfolioCard"

export default function PortfolioPage() {
  const { address, isConnected } = useAccount()
  const {
    data: positionIds,
    isLoading,
    error,
  } = useUserPositions()

  if (!isConnected || !address) {
    return <p className="text-center text-muted-foreground">Please connect your wallet to view your positions.</p>
  }

  if (isLoading) {
    return <p className="text-center text-muted-foreground">Loading your positions...</p>
  }

  if (error) {
    return <p className="text-center text-red-500">Error loading positions: {error.message}</p>
  }

  if (!positionIds || positionIds.length === 0) {
    return <p className="text-center text-muted-foreground">You have no active positions.</p>
  }

  return (
    <div className="space-y-6">
      <h1 className="text-3xl font-bold">My Positions ({positionIds.length})</h1>
      <div className="grid grid-cols-1 gap-6 md:grid-cols-2 lg:grid-cols-3">
        {positionIds.map((positionId) => (
          <PortfolioCard key={positionId.toString()} positionId={positionId} />
        ))}
      </div>
    </div>
  )
}

