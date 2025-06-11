@val external require: string => unit = "require"

let registerContractHandlers = (
  ~contractName,
  ~handlerPathRelativeToRoot,
  ~handlerPathRelativeToConfig,
) => {
  try {
    require("root/" ++ handlerPathRelativeToRoot)
  } catch {
  | exn =>
    let params = {
      "Contract Name": contractName,
      "Expected Handler Path": handlerPathRelativeToConfig,
      "Code": "EE500",
    }
    let logger = Logging.createChild(~params)

    let errHandler = exn->ErrorHandling.make(~msg="Failed to import handler file", ~logger)
    errHandler->ErrorHandling.log
    errHandler->ErrorHandling.raiseExn
  }
}

%%private(
  let makeGeneratedConfig = () => {
    let chains = [
      {
        let contracts = [
          {
            Config.name: "PoolManager",
            abi: Types.PoolManager.abi,
            addresses: [
              "0x1f98400000000000000000000000000000000004"->Address.Evm.fromStringOrThrow
,
            ],
            events: [
              (Types.PoolManager.Swap.register() :> Internal.eventConfig),
            ],
          },
        ]
        let chain = ChainMap.Chain.makeUnsafe(~chainId=11877)
        {
          Config.confirmedBlockThreshold: 200,
          startBlock: 18650793,
          endBlock: None,
          chain,
          contracts,
          sources: NetworkSources.evm(~chain, ~contracts=[{name: "PoolManager",events: [Types.PoolManager.Swap.register()],abi: Types.PoolManager.abi}], ~hyperSync=None, ~allEventSignatures=[Types.PoolManager.eventSignatures]->Belt.Array.concatMany, ~shouldUseHypersyncClientDecoder=true, ~rpcs=[{url: "https://unichain-mainnet.g.alchemy.com/v2/7LcTJXKrcZO7J_VH22ppv", sourceFor: Sync, syncConfig: {}}])
        }
      },
    ]

    Config.make(
      ~shouldRollbackOnReorg=true,
      ~shouldSaveFullHistory=false,
      ~isUnorderedMultichainMode=false,
      ~chains,
      ~enableRawEvents=false,
      ~entities=[
        module(Entities.Swap),
      ],
    )
  }

  let config: ref<option<Config.t>> = ref(None)
)

let registerAllHandlers = () => {
  registerContractHandlers(
    ~contractName="PoolManager",
    ~handlerPathRelativeToRoot="infra/hyperindex/mappings.ts",
    ~handlerPathRelativeToConfig="infra/hyperindex/mappings.ts",
  )

  let generatedConfig = makeGeneratedConfig()
  config := Some(generatedConfig)
  generatedConfig
}

let getConfig = () => {
  switch config.contents {
  | Some(config) => config
  | None => registerAllHandlers()
  }
}
