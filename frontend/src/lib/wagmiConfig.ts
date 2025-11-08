import { createWeb3Modal } from "@web3modal/wagmi/react"
import { defaultWagmiConfig } from "@web3modal/wagmi/react/config"
import { WagmiProvider } from "wagmi"
import { mainnet, sepolia } from "wagmi/chains"

const projectId = process.env.NEXT_PUBLIC_WC_PROJECT_ID

if (!projectId) {
  throw new Error("NEXT_PUBLIC_WC_PROJECT_ID is not set")
}

const metadata = {
  name: "Intelligent Yield Aggregator",
  description: "Deposit, Earn, and Fund Public Goods",
  url: "https://my-dapp.com",
  icons: ["https://avatars.githubusercontent.com/u/37784886"],
}

const chains = [mainnet, sepolia] as const

export const config = defaultWagmiConfig({
  chains,
  projectId,
  metadata,
})

if (typeof window !== "undefined") {
  createWeb3Modal({
    wagmiConfig: config,
    projectId,
    enableAnalytics: true,
    themeMode: "dark",
    themeVariables: {
      "--w3m-accent": "#a855f7",
    },
  })
}

export function Web3ModalProvider({ children }: { children: React.ReactNode }) {
  return <WagmiProvider config={config}>{children}</WagmiProvider>
}

