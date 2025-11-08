"use client"

import { LeaderboardTable } from "@/components/LeaderboardTable"
import { useLeaderboardData } from "@/lib/hooks/useLeaderboardData"

export default function LeaderboardPage() {
  const { data, isLoading, error } = useLeaderboardData()

  return (
    <div className="space-y-6">
      <h1 className="text-3xl font-bold">Heroes of Public Goods</h1>
      <p className="text-muted-foreground">The top contributors to public goods, powered by yield.</p>

      {isLoading && <p>Loading leaderboard...</p>}
      {error && <p className="text-red-500">Error: {error.message}</p>}
      {data && <LeaderboardTable data={data} />}
    </div>
  )
}

