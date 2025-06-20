
/***** TAKE NOTE ******
This file module is a hack to get genType to work!

In order for genType to produce recursive types, it needs to be at the 
root module of a file. If it's defined in a nested module it does not 
work. So all the MockDb types and internal functions are defined here in TestHelpers_MockDb
and only public functions are recreated and exported from TestHelpers.MockDb module.

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

open Belt

/**
A raw js binding to allow deleting from a dict. Used in store delete operation
*/
let deleteDictKey: (dict<'a>, string) => unit = %raw(`
    function(dict, key) {
      delete dict[key]
    }
  `)

/**
The mockDb type is simply an InMemoryStore internally. __dbInternal__ holds a reference
to an inMemoryStore and all the the accessor methods point to the reference of that inMemory
store
*/
@genType.opaque
type inMemoryStore = InMemoryStore.t

@genType
type rec t = {
  __dbInternal__: inMemoryStore,
  entities: entities,
  rawEvents: storeOperations<InMemoryStore.rawEventsKey, TablesStatic.RawEvents.t>,
  eventSyncState: storeOperations<Types.chainId, TablesStatic.EventSyncState.t>,
  dynamicContractRegistry: entityStoreOperations<TablesStatic.DynamicContractRegistry.t>,
}

// Each user defined entity will be in this record with all the store or "mockdb" operators
@genType
and entities = {
    @as("Swap") swap: entityStoreOperations<Entities.Swap.t>,
  }
// User defined entities always have a string for an id which is used as the
// key for entity stores
@genType
and entityStoreOperations<'entity> = storeOperations<string, 'entity>
// all the operator functions a user can access on an entity in the mock db
// stores refer to the the module that MakeStore functor outputs in IO.res
@genType
and storeOperations<'entityKey, 'entity> = {
  getAll: unit => array<'entity>,
  get: 'entityKey => option<'entity>,
  set: 'entity => t,
  delete: 'entityKey => t,
}

/**
Removes all existing indices on an entity in the mockDB and
adds an index for each field to ensure getWhere queries are
always accounted for
*/
let updateEntityIndicesMockDb = (
  ~mockDbTable: InMemoryTable.Entity.t<'entity>,
  ~entity: 'entity,
  ~entityId,
) => {
  let entityIndices = switch mockDbTable.table
  ->InMemoryTable.get(entityId)
  ->Option.map(r => r.entityIndices) {
  | Some(entityIndices) => entityIndices
  | None => Js.Exn.raiseError("Unexpected, updateEntityIndicesMockDb was called before entity was set")
  }
  //first prune all indices to avoid stale values
  mockDbTable->InMemoryTable.Entity.deleteEntityFromIndices(~entityId, ~entityIndices)

  //then add all indices
  entity
  ->Utils.magic
  ->Js.Dict.entries
  ->Array.forEach(((fieldName, fieldValue)) => {
    TableIndices.Operator.values->Array.forEach(operator => {
      let index = TableIndices.Index.makeSingle(~fieldName, ~fieldValue, ~operator)
      mockDbTable->InMemoryTable.Entity.addIdToIndex(~index, ~entityId)
      entityIndices->Utils.Set.add(index)->ignore
    })
  })
}

/**
a composable function to make the "storeOperations" record to represent all the mock
db operations for each entity.
*/
let makeStoreOperatorEntity = (
  ~inMemoryStore: InMemoryStore.t,
  ~makeMockDb,
  ~getStore: InMemoryStore.t => InMemoryTable.Entity.t<'entity>,
  ~getKey: 'entity => Types.id,
): storeOperations<Types.id, 'entity> => {
  let {getUnsafe, values, set} = module(InMemoryTable.Entity)

  let get = id => {
    let store = inMemoryStore->getStore
    if store.table->InMemoryTable.hasByHash(id) {
      getUnsafe(store)(id)
    } else {
      None
    }
  }

  let getAll = () =>
    inMemoryStore
    ->getStore
    ->values

  let set = entity => {
    let cloned = inMemoryStore->InMemoryStore.clone
    let table = cloned->getStore
    let entityId = entity->getKey

    table->set(
      Set(entity)->Types.mkEntityUpdate(
        ~entityId,
        ~eventIdentifier={chainId: -1, blockNumber: -1, blockTimestamp: 0, logIndex: -1},
      ),
      ~shouldSaveHistory=false,
    )

    updateEntityIndicesMockDb(~mockDbTable=table, ~entity, ~entityId)
    cloned->makeMockDb
  }

  let delete = key => {
    let cloned = inMemoryStore->InMemoryStore.clone
    let store = cloned->getStore
    let entityIndices = switch store.table->InMemoryTable.get(key) {
    | Some({entityIndices}) => entityIndices
    | None => Utils.Set.make()
    }
    store->InMemoryTable.Entity.deleteEntityFromIndices(~entityId=key, ~entityIndices)
    store.table.dict->deleteDictKey(key)
    cloned->makeMockDb
  }

  {
    getAll,
    get,
    set,
    delete,
  }
}

let makeStoreOperatorMeta = (
  ~inMemoryStore: InMemoryStore.t,
  ~makeMockDb,
  ~getStore: InMemoryStore.t => InMemoryTable.t<'key, 'value>,
  ~getKey: 'value => 'key,
): storeOperations<'key, 'value> => {
  let {get, values, set} = module(InMemoryTable)

  let get = id => get(inMemoryStore->getStore, id)

  let getAll = () => inMemoryStore->getStore->values->Array.map(row => row)

  let set = metaData => {
    let cloned = inMemoryStore->InMemoryStore.clone
    cloned->getStore->set(metaData->getKey, metaData)
    cloned->makeMockDb
  }

  // TODO: Remove. Is delete needed for meta data?
  let delete = key => {
    let cloned = inMemoryStore->InMemoryStore.clone
    let store = cloned->getStore
    store.dict->deleteDictKey(key->store.hash)
    cloned->makeMockDb
  }

  {
    getAll,
    get,
    set,
    delete,
  }
}

/**
The internal make function which can be passed an in memory store and
instantiate a "MockDb". This is useful for cloning or making a MockDb
out of an existing inMemoryStore
*/
let rec makeWithInMemoryStore: InMemoryStore.t => t = (inMemoryStore: InMemoryStore.t) => {
  let rawEvents = makeStoreOperatorMeta(
    ~inMemoryStore,
    ~makeMockDb=makeWithInMemoryStore,
    ~getStore=db => db.rawEvents,
    ~getKey=({chainId, eventId}) => {
      chainId,
      eventId: eventId->BigInt.toString,
    },
  )

  let eventSyncState = makeStoreOperatorMeta(
    ~inMemoryStore,
    ~makeMockDb=makeWithInMemoryStore,
    ~getStore=db => db.eventSyncState,
    ~getKey=({chainId}) => chainId,
  )

  let dynamicContractRegistry = makeStoreOperatorEntity(
    ~inMemoryStore,
    ~getStore=db =>
      db.entities->InMemoryStore.EntityTables.get(module(TablesStatic.DynamicContractRegistry)),
    ~makeMockDb=makeWithInMemoryStore,
    ~getKey=({chainId, contractAddress}) =>
      TablesStatic.DynamicContractRegistry.makeId(~chainId, ~contractAddress),
  )

  let entities = {
      swap: {
        makeStoreOperatorEntity(
          ~inMemoryStore,
          ~makeMockDb=makeWithInMemoryStore,
          ~getStore=db => db.entities->InMemoryStore.EntityTables.get(module(Entities.Swap)),
          ~getKey=({id}) => id,
        )
      },
  }

  {__dbInternal__: inMemoryStore, entities, rawEvents, eventSyncState, dynamicContractRegistry}
}

/**
The constructor function for a mockDb. Call it and then set up the inital state by calling
any of the set functions it provides access to. A mockDb will be passed into a processEvent 
helper. Note, process event helpers will not mutate the mockDb but return a new mockDb with
new state so you can compare states before and after.
*/
//Note: It's called createMockDb over "make" to make it more intuitive in JS and TS
@genType 
let createMockDb = () => makeWithInMemoryStore(InMemoryStore.make())

/**
Accessor function for getting the internal inMemoryStore in the mockDb
*/
let getInternalDb = (self: t) => self.__dbInternal__

/**
Deep copies the in memory store data and returns a new mockDb with the same
state and no references to data from the passed in mockDb
*/
let cloneMockDb = (self: t) => {
  let clonedInternalDb = self->getInternalDb->InMemoryStore.clone
  clonedInternalDb->makeWithInMemoryStore
}

let getEntityOperations = (mockDb: t, ~entityMod): entityStoreOperations<Entities.internalEntity> => {
  let module(Entity: Entities.InternalEntity) = entityMod
  mockDb.entities
  ->Utils.magic
  ->Utils.Dict.dangerouslyGetNonOption((Entity.name :> string))
  ->Utils.Option.getExn("Mocked operations for entity " ++ (Entity.name :> string) ++ " not found")
}

let makeLoadEntitiesByIds = (mockDb: t) => {
  (ids, ~entityMod, ~logger as _=?) => {
    let operations = mockDb->getEntityOperations(~entityMod)
    ids->Array.keepMap(id => operations.get(id))->Promise.resolve
  }
}


let makeLoadEntitiesByField = (mockDb: t) => {
  async (
    ~operator,
    ~entityMod,
    ~fieldName,
    ~fieldValue,
    ~fieldValueSchema as _,
    ~logger as _=?,
  ) => {
    let mockDbTable = mockDb.__dbInternal__->InMemoryStore.getInMemTable(~entityMod)
    let fieldValueHash =
      fieldValue->TableIndices.FieldValue.castFrom->TableIndices.FieldValue.toString
    if (mockDbTable->InMemoryTable.Entity.hasIndex(~fieldName, ~operator))(fieldValueHash) {
      (mockDbTable->InMemoryTable.Entity.getUnsafeOnIndex(~fieldName, ~operator))(fieldValueHash)
    } else {
      []
    }
  }
}

/**
A function composer for simulating the writing of an inMemoryStore to the external db with a mockDb.
Runs all set and delete operations currently cached in an inMemory store against the mockDb
*/
let executeRowsEntity = (
  type entity,
  mockDb: t,
  ~inMemoryStore: InMemoryStore.t,
  ~entityMod: module(Entities.Entity with type t = entity),
  ~getKey: entity => 'key,
) => {
  let getInMemTable = (inMemoryStore: InMemoryStore.t) =>
    inMemoryStore.entities->InMemoryStore.EntityTables.get(entityMod)

  let inMemTable = getInMemTable(inMemoryStore)

  inMemTable.table
  ->InMemoryTable.values
  ->Array.forEach(row => {
    let mockDbTable = mockDb->getInternalDb->getInMemTable
    switch row.entityRow {
    | Updated({latest: {entityUpdateAction: Set(entity)}})
    | InitialReadFromDb(AlreadySet(entity)) =>
      let key = getKey(entity)
      mockDbTable->InMemoryTable.Entity.initValue(
        ~allowOverWriteEntity=true,
        ~key,
        ~entity=Some(entity),
      )
      updateEntityIndicesMockDb(~mockDbTable, ~entity, ~entityId=key)
    | Updated({latest: {entityUpdateAction: Delete, entityId}}) =>
      mockDbTable.table.dict->deleteDictKey(entityId)
      mockDbTable->InMemoryTable.Entity.deleteEntityFromIndices(
        ~entityId,
        ~entityIndices=Utils.Set.make(),
      )
    | InitialReadFromDb(NotSet) => ()
    }
  })
}

let executeRowsMeta = (
  mockDb: t,
  ~inMemoryStore: InMemoryStore.t,
  ~getInMemTable: InMemoryStore.t => InMemoryTable.t<'key, 'entity>,
  ~getKey: 'entity => 'key,
) => {
  inMemoryStore
  ->getInMemTable
  ->InMemoryTable.values
  ->Array.forEach(row => {
    mockDb->getInternalDb->getInMemTable->InMemoryTable.set(getKey(row), row)
  })
}

/**
Simulates the writing of processed data in the inMemoryStore to a mockDb. This function
executes all the rows on each "store" (or pg table) in the inMemoryStore
*/
let writeFromMemoryStore = (mockDb: t, ~inMemoryStore: InMemoryStore.t) => {
  //INTERNAL STORES/TABLES EXECUTION
  mockDb->executeRowsMeta(
    ~inMemoryStore,
    ~getInMemTable=inMemStore => {inMemStore.rawEvents},
    ~getKey=(entity): InMemoryStore.rawEventsKey => {
      chainId: entity.chainId,
      eventId: entity.eventId->BigInt.toString,
    },
  )

  mockDb->executeRowsMeta(
    ~inMemoryStore,
    ~getInMemTable=inMemStore => {inMemStore.eventSyncState},
    ~getKey=entity => entity.chainId,
  )

  mockDb->executeRowsEntity(
    ~inMemoryStore,
    ~entityMod=module(TablesStatic.DynamicContractRegistry),
    ~getKey=entity => entity.id,
  )

//ENTITY EXECUTION
  mockDb->executeRowsEntity(
    ~inMemoryStore,
    ~entityMod=module(Entities.Swap),
    ~getKey=entity => entity.id,
  )
}

