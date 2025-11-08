"use client"

import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import { formatTokenAmount } from "@/lib/utils"
import { LeaderboardRow } from "@/lib/hooks/useLeaderboardData"

const BADGE_THRESHOLDS = {
  GOLD: 1_000n * 10n ** 6n,
  SILVER: 500n * 10n ** 6n,
  BRONZE: 100n * 10n ** 6n,
}

function getBadge(amount: bigint) {
  if (amount >= BADGE_THRESHOLDS.GOLD) return "🥇"
  if (amount >= BADGE_THRESHOLDS.SILVER) return "🥈"
  if (amount >= BADGE_THRESHOLDS.BRONZE) return "🥉"
  return "—"
}

interface LeaderboardTableProps {
  data: LeaderboardRow[]
}

export function LeaderboardTable({ data }: LeaderboardTableProps) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Top Donors</CardTitle>
      </CardHeader>
      <CardContent>
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead className="w-[60px]">Rank</TableHead>
              <TableHead>User</TableHead>
              <TableHead>Badges</TableHead>
              <TableHead className="text-right">Total Donated (USDC)</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {data.map((row) => (
              <TableRow key={row.donor}>
                <TableCell className="font-medium">{row.rank}</TableCell>
                <TableCell>{`${row.donor.slice(0, 6)}...${row.donor.slice(-4)}`}</TableCell>
                <TableCell>{getBadge(row.totalDonated)}</TableCell>
                <TableCell className="text-right font-medium">
                  ${formatTokenAmount(row.totalDonated, 6)}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  )
}

