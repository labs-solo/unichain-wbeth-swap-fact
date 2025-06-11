open Table
open Enums.EntityType
type id = string

type internalEntity = Internal.entity
module type Entity = {
  type t
  let name: Enums.EntityType.t
  let schema: S.t<t>
  let rowsSchema: S.t<array<t>>
  let table: Table.table
  let entityHistory: EntityHistory.t<t>
}
module type InternalEntity = Entity with type t = internalEntity
external entityModToInternal: module(Entity with type t = 'a) => module(InternalEntity) = "%identity"
external entityModsToInternal: array<module(Entity)> => array<module(InternalEntity)> = "%identity"

@get
external getEntityId: internalEntity => string = "id"

exception UnexpectedIdNotDefinedOnEntity
let getEntityIdUnsafe = (entity: 'entity): id =>
  switch Utils.magic(entity)["id"] {
  | Some(id) => id
  | None =>
    UnexpectedIdNotDefinedOnEntity->ErrorHandling.mkLogAndRaise(
      ~msg="Property 'id' does not exist on expected entity object",
    )
  }

//shorthand for punning
let isPrimaryKey = true
let isNullable = true
let isArray = true
let isIndex = true

@genType
type whereOperations<'entity, 'fieldType> = {
  eq: 'fieldType => promise<array<'entity>>,
  gt: 'fieldType => promise<array<'entity>>
}

module Swap = {
  let name = Swap
  @genType
  type t = {
    amount0: string,
    amount1: string,
    blockNumber: int,
    blockTime: string,
    chainId: int,
    createdAt: string,
    id: id,
    liquidity: string,
    logIndex: int,
    origin: string,
    poolAddress: string,
    poolId: string,
    sender: string,
    sqrtPriceX96: string,
    tick: int,
    token0: string,
    token1: string,
    txHash: string,
  }

  let schema = S.object((s): t => {
    amount0: s.field("amount0", S.string),
    amount1: s.field("amount1", S.string),
    blockNumber: s.field("blockNumber", S.int),
    blockTime: s.field("blockTime", S.string),
    chainId: s.field("chainId", S.int),
    createdAt: s.field("createdAt", S.string),
    id: s.field("id", S.string),
    liquidity: s.field("liquidity", S.string),
    logIndex: s.field("logIndex", S.int),
    origin: s.field("origin", S.string),
    poolAddress: s.field("poolAddress", S.string),
    poolId: s.field("poolId", S.string),
    sender: s.field("sender", S.string),
    sqrtPriceX96: s.field("sqrtPriceX96", S.string),
    tick: s.field("tick", S.int),
    token0: s.field("token0", S.string),
    token1: s.field("token1", S.string),
    txHash: s.field("txHash", S.string),
  })

  let rowsSchema = S.array(schema)

  @genType
  type indexedFieldOperations = {
    
  }

  let table = mkTable(
    (name :> string),
    ~schemaName=Env.Db.publicSchema,
    ~fields=[
      mkField(
      "amount0", 
      Text,
      ~fieldSchema=S.string,
      
      
      
      
      
      ),
      mkField(
      "amount1", 
      Text,
      ~fieldSchema=S.string,
      
      
      
      
      
      ),
      mkField(
      "blockNumber", 
      Integer,
      ~fieldSchema=S.int,
      
      
      
      
      
      ),
      mkField(
      "blockTime", 
      Text,
      ~fieldSchema=S.string,
      
      
      
      
      
      ),
      mkField(
      "chainId", 
      Integer,
      ~fieldSchema=S.int,
      
      
      
      
      
      ),
      mkField(
      "createdAt", 
      Text,
      ~fieldSchema=S.string,
      
      
      
      
      
      ),
      mkField(
      "id", 
      Text,
      ~fieldSchema=S.string,
      ~isPrimaryKey,
      
      
      
      
      ),
      mkField(
      "liquidity", 
      Text,
      ~fieldSchema=S.string,
      
      
      
      
      
      ),
      mkField(
      "logIndex", 
      Integer,
      ~fieldSchema=S.int,
      
      
      
      
      
      ),
      mkField(
      "origin", 
      Text,
      ~fieldSchema=S.string,
      
      
      
      
      
      ),
      mkField(
      "poolAddress", 
      Text,
      ~fieldSchema=S.string,
      
      
      
      
      
      ),
      mkField(
      "poolId", 
      Text,
      ~fieldSchema=S.string,
      
      
      
      
      
      ),
      mkField(
      "sender", 
      Text,
      ~fieldSchema=S.string,
      
      
      
      
      
      ),
      mkField(
      "sqrtPriceX96", 
      Text,
      ~fieldSchema=S.string,
      
      
      
      
      
      ),
      mkField(
      "tick", 
      Integer,
      ~fieldSchema=S.int,
      
      
      
      
      
      ),
      mkField(
      "token0", 
      Text,
      ~fieldSchema=S.string,
      
      
      
      
      
      ),
      mkField(
      "token1", 
      Text,
      ~fieldSchema=S.string,
      
      
      
      
      
      ),
      mkField(
      "txHash", 
      Text,
      ~fieldSchema=S.string,
      
      
      
      
      
      ),
      mkField("db_write_timestamp", TimestampWithoutTimezone, ~fieldSchema=Utils.Schema.dbDate, ~default="CURRENT_TIMESTAMP"),
    ],
  )

  let entityHistory = table->EntityHistory.fromTable(~schema)
}

let allEntities = [
  module(Swap),
  module(TablesStatic.DynamicContractRegistry),
]->entityModsToInternal

let byName =
  allEntities
  ->Js.Array2.map(entityMod => {
    let module(Entity) = entityMod
    (Entity.name :> string, entityMod)
  })
  ->Js.Dict.fromArray
