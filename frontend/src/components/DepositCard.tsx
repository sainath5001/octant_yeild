"use client"

import { useMemo, useState } from "react"
import { toast } from "sonner"
import {
  useAccount,
  useReadContract,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi"
import { parseUnits, maxUint256 } from "viem"
import { aggregatorVaultABI, erc20ABI, getContractsForChain } from "@/lib/contracts"
import { Button } from "@/components/ui/button"
import { Card, CardHeader, CardTitle, CardContent, CardFooter } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Slider } from "@/components/ui/slider"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"

const LOCKUP_DURATIONS = {
  "3m": 7_889_400,
  "6m": 15_778_800,
  "12m": 31_557_600,
} as const

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"

export function DepositCard() {
  const { address, chainId } = useAccount()

  const [amount, setAmount] = useState("")
  const [donationBps, setDonationBps] = useState(10)
  const [lockupKey, setLockupKey] = useState<keyof typeof LOCKUP_DURATIONS>("3m")
  const [planId, setPlanId] = useState(0)

  const contracts = useMemo(() => (chainId ? getContractsForChain(chainId) : undefined), [chainId])
  const isConfigured =
    contracts &&
    contracts.aggregatorVault !== ZERO_ADDRESS &&
    contracts.usdcToken !== ZERO_ADDRESS &&
    aggregatorVaultABI.length > 0

  const parsedAmount = useMemo(
    () => (amount ? parseUnits(amount, 6) : 0n),
    [amount],
  )

  const {
    data: allowance,
    refetch: refetchAllowance,
  } = useReadContract({
    abi: erc20ABI,
    address: contracts?.usdcToken,
    functionName: "allowance",
    args: address && contracts ? [address, contracts.aggregatorVault] : undefined,
    query: {
      enabled: Boolean(address && isConfigured),
      refetchInterval: 5_000,
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
      toast.success("Transaction Confirmed!", {
        description: `Tx: ${receipt.transactionHash.slice(0, 10)}...`,
      })
      refetchAllowance()
      setAmount("")
    },
    onError: (error) => {
      toast.error("Transaction Failed", {
        description: error.message,
      })
    },
  })

  const needsApproval = isConfigured && (allowance ?? 0n) < parsedAmount
  const isLoading = isPending || isConfirming

  async function handleApprove() {
    if (!contracts || !isConfigured) {
      toast.error("Vault configuration missing")
      return
    }

    const dismiss = toast.loading("Sending approval transaction...")
    try {
      await writeContractAsync({
        abi: erc20ABI,
        address: contracts.usdcToken,
        functionName: "approve",
        args: [contracts.aggregatorVault, maxUint256],
      })
      toast.success("Approval submitted")
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unknown error"
      toast.error("Approval failed", { description: message })
    } finally {
      toast.dismiss(dismiss)
    }
  }

  async function handleDeposit() {
    if (!contracts || !address || !isConfigured) {
      toast.error("Vault configuration missing")
      return
    }

    if (parsedAmount === 0n) {
      toast.error("Amount cannot be zero")
      return
    }

    const lockDuration = BigInt(LOCKUP_DURATIONS[lockupKey])
    const donationBpsScaled = donationBps * 100

    const dismiss = toast.loading("Sending deposit transaction...")
    try {
      await writeContractAsync({
        abi: aggregatorVaultABI,
        address: contracts.aggregatorVault,
        functionName: "deposit",
        args: [parsedAmount, donationBpsScaled, lockDuration, planId, address],
      })
      toast.success("Deposit submitted")
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unknown error"
      toast.error("Deposit failed", { description: message })
    } finally {
      toast.dismiss(dismiss)
    }
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Deposit &amp; Earn</CardTitle>
      </CardHeader>
      <CardContent className="space-y-6">
        <Tabs value={planId.toString()} onValueChange={(value) => setPlanId(Number(value))}>
          <TabsList className="grid w-full grid-cols-3">
            <TabsTrigger value="0">Basic</TabsTrigger>
            <TabsTrigger value="1">Standard</TabsTrigger>
            <TabsTrigger value="2">Premium</TabsTrigger>
          </TabsList>
          <TabsContent value={planId.toString()} className="sr-only" />
        </Tabs>

        <div className="space-y-2">
          <label htmlFor="amount" className="text-sm font-medium text-foreground">
            Amount (USDC)
          </label>
          <Input
            id="amount"
            type="number"
            min="0"
            step="0.01"
            placeholder="100.00"
            value={amount}
            onChange={(event) => setAmount(event.target.value)}
            disabled={isLoading}
          />
        </div>

        <div className="grid gap-4 md:grid-cols-2">
          <div className="space-y-2">
            <label htmlFor="lockup" className="text-sm font-medium text-foreground">
              Lock-in Period
            </label>
            <Select value={lockupKey} onValueChange={(value) => setLockupKey(value as keyof typeof LOCKUP_DURATIONS)} disabled={isLoading}>
              <SelectTrigger id="lockup">
                <SelectValue placeholder="Select duration" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="3m">3 Months</SelectItem>
                <SelectItem value="6m">6 Months</SelectItem>
                <SelectItem value="12m">12 Months</SelectItem>
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-2">
            <label htmlFor="donation" className="text-sm font-medium text-foreground">
              Donation: {donationBps}%
            </label>
            <Slider
              id="donation"
              min={0}
              max={50}
              step={5}
              value={[donationBps]}
              onValueChange={([next]) => setDonationBps(next ?? donationBps)}
              disabled={isLoading}
            />
          </div>
        </div>
      </CardContent>
      <CardFooter>
        {needsApproval ? (
          <Button className="w-full bg-purple-600 hover:bg-purple-500" onClick={handleApprove} disabled={isLoading || !address || !isConfigured}>
            {isLoading ? "Approving..." : isConfigured ? "Approve USDC" : "Configuration Required"}
          </Button>
        ) : (
          <Button className="w-full bg-purple-600 hover:bg-purple-500" onClick={handleDeposit} disabled={isLoading || !address || !isConfigured}>
            {isLoading ? "Depositing..." : isConfigured ? "Deposit" : "Configuration Required"}
          </Button>
        )}
      </CardFooter>
    </Card>
  )
}

