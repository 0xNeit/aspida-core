import { BytesLike, StorageSlot, CreateTransactionRequestLike } from 'fuels';

declare type DeployContractOptions = {
    salt?: BytesLike;
    storageSlots?: StorageSlot[];
    stateRoot?: BytesLike;
} & CreateTransactionRequestLike;
declare enum Commands {
    "build" = "build",
    "deploy" = "deploy",
    "types" = "types",
    "run" = "run"
}
declare type BuildDeploy = {
    name: string;
    contractId: string;
};
declare type Event = {
    type: Commands.build;
    data: unknown;
} | {
    type: Commands.deploy;
    data: Array<BuildDeploy>;
} | {
    type: Commands.run;
    data: Array<BuildDeploy>;
};
declare type OptionsFunction = (contracts: Array<ContractDeployed>) => DeployContractOptions;
declare type ContractConfig = {
    name: string;
    path: string;
    options?: DeployContractOptions | OptionsFunction;
};
declare type ContractDeployed = {
    name: string;
    contractId: string;
};
declare type Config = {
    onSuccess?: (event: Event) => void;
    onFailure?: (err: unknown) => void;
    env?: {
        [key: string]: string;
    };
    types: {
        artifacts: string;
        output: string;
    };
    contracts: Array<ContractConfig>;
};

export { BuildDeploy, Commands, Config, ContractConfig, ContractDeployed, DeployContractOptions, Event, OptionsFunction };
