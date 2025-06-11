/***** TAKE NOTE ******
This is a hack to get genType to work!

In order for genType to produce recursive types, it needs to be at the 
root module of a file. If it's defined in a nested module it does not 
work. So all the MockDb types and internal functions are defined in TestHelpers_MockDb
and only public functions are recreated and exported from this module.

the following module:
```rescript
module MyModule = {
  @genType
  type rec a = {fieldB: b}
  @genType and b = {fieldA: a}
}
```

produces the following in ts:
```ts
// tslint:disable-next-line:interface-over-type-literal
export type MyModule_a = { readonly fieldB: b };

// tslint:disable-next-line:interface-over-type-literal
export type MyModule_b = { readonly fieldA: MyModule_a };
```

fieldB references type b which doesn't exist because it's defined
as MyModule_b
*/

module MockDb = {
  @genType
  let createMockDb = TestHelpers_MockDb.createMockDb
}

@genType
module Addresses = {
  include TestHelpers_MockAddresses
}

module EventFunctions = {
  //Note these are made into a record to make operate in the same way
  //for Res, JS and TS.

  /**
  The arguements that get passed to a "processEvent" helper function
  */
  @genType
  type eventProcessorArgs<'event> = {
    event: 'event,
    mockDb: TestHelpers_MockDb.t,
    chainId?: int,
  }

  @genType
  type eventProcessor<'event> = eventProcessorArgs<'event> => promise<TestHelpers_MockDb.t>

  /**
  A function composer to help create individual processEvent functions
  */
  let makeEventProcessor = (~register) => {
    async args => {
      let {event, mockDb, ?chainId} = args->(Utils.magic: eventProcessorArgs<'event> => eventProcessorArgs<Internal.event>)

      let config = RegisterHandlers.getConfig()
      let eventConfig: Internal.eventConfig = register()

      // The user can specify a chainId of an event or leave it off
      // and it will default to the first chain in the config
      let chain = switch chainId {
      | Some(chainId) => config->Config.getChain(~chainId)
      | None =>
        switch config.defaultChain {
        | Some(chainConfig) => chainConfig.chain
        | None =>
          Js.Exn.raiseError(
            "No default chain Id found, please add at least 1 chain to your config.yaml",
          )
        }
      }

      //Create an individual logging context for traceability
      let logger = Logging.createChild(
        ~params={
          "Context": `Test Processor for "${eventConfig.name}" event on contract "${eventConfig.contractName}"`,
          "Chain ID": chain->ChainMap.Chain.toChainId,
          "event": event,
        },
      )

      //Deep copy the data in mockDb, mutate the clone and return the clone
      //So no side effects occur here and state can be compared between process
      //steps
      let mockDbClone = mockDb->TestHelpers_MockDb.cloneMockDb

      if !(eventConfig.handler->Belt.Option.isSome || eventConfig.contractRegister->Belt.Option.isSome) {
        Not_found->ErrorHandling.mkLogAndRaise(
          ~logger,
          ~msg=`No registered handler found for "${eventConfig.name}" on contract "${eventConfig.contractName}"`,
        )
      }
      //Construct a new instance of an in memory store to run for the given event
      let inMemoryStore = InMemoryStore.make()
      let loadLayer = LoadLayer.make(
        ~loadEntitiesByIds=TestHelpers_MockDb.makeLoadEntitiesByIds(mockDbClone),
        ~loadEntitiesByField=TestHelpers_MockDb.makeLoadEntitiesByField(mockDbClone),
      )

      //No need to check contract is registered or return anything.
      //The only purpose is to test the registerContract function and to
      //add the entity to the in memory store for asserting registrations
      let eventItem: Internal.eventItem = {
        eventConfig,
        event,
        chain,
        logIndex: event.logIndex,
        timestamp: event.block->Types.Block.getTimestamp,
        blockNumber: event.block->Types.Block.getNumber,
      }

      switch eventConfig.contractRegister {
      | Some(_) =>
        let dcs = await ChainFetcher.runContractRegistersOrThrow(~reversedWithContractRegister=[eventItem])
        // TODO: Reuse FetchState logic to clean up duplicate dcs
        if dcs->Utils.Array.notEmpty {
          inMemoryStore->InMemoryStore.setDcsToStore(
            Js.Dict.fromArray([(chain->ChainMap.Chain.toChainId->Belt.Int.toString, dcs)]),
            ~shouldSaveHistory=false,
          )
        }
      | None => () //No need to run contract registration
      }

      switch eventConfig.handler {
      | Some(handler) =>
        switch await eventItem->EventProcessing.runEventHandler(
          ~inMemoryStore,
          ~loader=eventConfig.loader,
          ~handler,
          ~loadLayer,
          ~shouldSaveHistory=false,
        ) {
        | Ok(_) => ()
        | Error(e) => e->ErrorHandling.logAndRaise
        }
      | None => () //No need to run handler
      }

      //In mem store can still contatin raw events and dynamic contracts for the
      //testing framework in cases where either contract register or loaderHandler
      //is None
      mockDbClone->TestHelpers_MockDb.writeFromMemoryStore(~inMemoryStore)
      mockDbClone
    }
  }

  module MockBlock = {
    @genType
    type t = {
      hash?: string,
      number?: int,
      timestamp?: int,
    }

    let toBlock = (_mock: t) => {
      hash: _mock.hash->Belt.Option.getWithDefault("foo"),
      number: _mock.number->Belt.Option.getWithDefault(0),
      timestamp: _mock.timestamp->Belt.Option.getWithDefault(0),
    }->(Utils.magic: Types.AggregatedBlock.t => Internal.eventBlock)
  }

  module MockTransaction = {
    @genType
    type t = {
    }

    let toTransaction = (_mock: t) => {
    }->(Utils.magic: Types.AggregatedTransaction.t => Internal.eventTransaction)
  }

  @genType
  type mockEventData = {
    chainId?: int,
    srcAddress?: Address.t,
    logIndex?: int,
    block?: MockBlock.t,
    transaction?: MockTransaction.t,
  }

  /**
  Applies optional paramters with defaults for all common eventLog field
  */
  let makeEventMocker = (
    ~params: Internal.eventParams,
    ~mockEventData: option<mockEventData>,
  ): Internal.event => {
    let {?block, ?transaction, ?srcAddress, ?chainId, ?logIndex} =
      mockEventData->Belt.Option.getWithDefault({})
    let block = block->Belt.Option.getWithDefault({})->MockBlock.toBlock
    let transaction = transaction->Belt.Option.getWithDefault({})->MockTransaction.toTransaction
    {
      params,
      transaction,
      chainId: chainId->Belt.Option.getWithDefault(1),
      block,
      srcAddress: srcAddress->Belt.Option.getWithDefault(Addresses.defaultAddress),
      logIndex: logIndex->Belt.Option.getWithDefault(0),
    }
  }
}


module PoolManager = {
  module Swap = {
    @genType
    let processEvent: EventFunctions.eventProcessor<Types.PoolManager.Swap.event> = EventFunctions.makeEventProcessor(
      ~register=(Types.PoolManager.Swap.register :> unit => Internal.eventConfig),
    )

    @genType
    type createMockArgs = {
      @as("id")
      id?: string,
      @as("sender")
      sender?: Address.t,
      @as("amount0")
      amount0?: bigint,
      @as("amount1")
      amount1?: bigint,
      @as("sqrtPriceX96")
      sqrtPriceX96?: bigint,
      @as("liquidity")
      liquidity?: bigint,
      @as("tick")
      tick?: bigint,
      @as("fee")
      fee?: bigint,
      mockEventData?: EventFunctions.mockEventData,
    }

    @genType
    let createMockEvent = args => {
      let {
        ?id,
        ?sender,
        ?amount0,
        ?amount1,
        ?sqrtPriceX96,
        ?liquidity,
        ?tick,
        ?fee,
        ?mockEventData,
      } = args

      let params = 
      {
       id: id->Belt.Option.getWithDefault("foo"),
       sender: sender->Belt.Option.getWithDefault(TestHelpers_MockAddresses.defaultAddress),
       amount0: amount0->Belt.Option.getWithDefault(0n),
       amount1: amount1->Belt.Option.getWithDefault(0n),
       sqrtPriceX96: sqrtPriceX96->Belt.Option.getWithDefault(0n),
       liquidity: liquidity->Belt.Option.getWithDefault(0n),
       tick: tick->Belt.Option.getWithDefault(0n),
       fee: fee->Belt.Option.getWithDefault(0n),
      }
->(Utils.magic: Types.PoolManager.Swap.eventArgs => Internal.eventParams)

      EventFunctions.makeEventMocker(~params, ~mockEventData)
        ->(Utils.magic: Internal.event => Types.PoolManager.Swap.event)
    }
  }

}

