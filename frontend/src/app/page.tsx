import { readContract } from "@wagmi/core"
import { mainnet } from "viem/chains"
import { Card, CardHeader, CardTitle, CardContent } from "@/components/ui/card"
import { DepositCard } from "@/components/DepositCard"
import { aggregatorVaultABI, getContractsForChain } from "@/lib/contracts"
import { formatTokenAmount } from "@/lib/utils"
import { config } from "@/lib/wagmiConfig"

async function getGlobalStats() {
  const chainId = mainnet.id
  const contracts = getContractsForChain(chainId)

  if (!contracts || aggregatorVaultABI.length === 0) {
    return { tvl: 0n, totalDonated: 0n }
  }

  try {
    const tvl = await readContract(config, {
      abi: aggregatorVaultABI,
      address: contracts.aggregatorVault,
      functionName: "totalAssets",
      chainId,
    })

    return { tvl: tvl as bigint, totalDonated: 0n }
  } catch (error) {
    console.error("Failed to fetch global stats:", error)
    return { tvl: 0n, totalDonated: 0n }
  }
}

export default async function HomePage() {
  const { tvl, totalDonated } = await getGlobalStats()

  return (
    <div className="grid grid-cols-1 gap-8 md:grid-cols-3">
      <div className="md:col-span-2">
        <DepositCard />
      </div>
      <div className="space-y-6">
        <Card>
          <CardHeader>
            <CardTitle>Total Value Locked</CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-3xl font-bold">${formatTokenAmount(tvl, 6)}</p>
            <p className="text-sm text-muted-foreground">Across all strategies</p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Total Donated</CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-3xl font-bold">${formatTokenAmount(totalDonated, 6)}</p>
            <p className="text-sm text-muted-foreground">To public goods</p>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
