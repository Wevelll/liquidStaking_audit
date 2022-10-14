/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */

import { Contract, Signer, utils } from "ethers";
import type { Provider } from "@ethersproject/providers";
import type {
  IAdaptersDistributor,
  IAdaptersDistributorInterface,
} from "../../../../contracts/audit/interfaces/IAdaptersDistributor";

const _abi = [
  {
    inputs: [
      {
        internalType: "address",
        name: "user",
        type: "address",
      },
    ],
    name: "getUserBalanceInAdapters",
    outputs: [
      {
        internalType: "uint256",
        name: "",
        type: "uint256",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
];

export class IAdaptersDistributor__factory {
  static readonly abi = _abi;
  static createInterface(): IAdaptersDistributorInterface {
    return new utils.Interface(_abi) as IAdaptersDistributorInterface;
  }
  static connect(
    address: string,
    signerOrProvider: Signer | Provider
  ): IAdaptersDistributor {
    return new Contract(
      address,
      _abi,
      signerOrProvider
    ) as IAdaptersDistributor;
  }
}