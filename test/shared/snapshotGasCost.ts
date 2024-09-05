import { TransactionReceipt, TransactionResponse } from '@ethersproject/abstract-provider'
import { expect } from 'chai'
import {Contract, ContractTransaction, ContractTransactionResponse} from 'ethers'

export default async function snapshotGasCost(
  x:
    | TransactionResponse
    | Promise<TransactionResponse>
    | ContractTransaction
    | Promise<ContractTransactionResponse>
    | TransactionReceipt
    | Promise<bigint>
    | bigint
    | Contract
    | Promise<Contract>
): Promise<void> {
  const resolved = await x

  if (typeof resolved === 'bigint') {
    expect(Number(resolved)).toMatchSnapshot()
  } else if ('deployTransaction' in resolved) {
    // @ts-ignore
    const receipt = await resolved.deployTransaction.wait()
    expect(Number(receipt.gasUsed)).toMatchSnapshot()
  } else if ('wait' in resolved) {
    const waited = await resolved.wait()
    expect(Number(waited.gasUsed)).toMatchSnapshot()
  } else if (!isNaN(Number(resolved))) {
    expect(Number(resolved)).toMatchSnapshot()
  }
}
