open Types

let getContractRegisterContext = (~eventItem, ~onRegister) => {
  // TODO: only add contracts we've registered for the event in the config
  addPoolManager: (contractAddress: Address.t) => {
    
    onRegister(~eventItem, ~contractAddress, ~contractName=Enums.ContractType.PoolManager)
  },
}->(Utils.magic: Types.contractRegistrations => Internal.contractRegisterContext)

let getContractRegisterArgs = (eventItem: Internal.eventItem, ~onRegister): Internal.contractRegisterArgs => {
  event: eventItem.event,
  context: getContractRegisterContext(~eventItem, ~onRegister),
}
