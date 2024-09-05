import { bytecode } from '../../artifacts/contracts/dex-core/Dex223Pool.sol/Dex223Pool.json'
import { ethers } from 'ethers'

export const POOL_BYTECODE_HASH = ethers.keccak256(bytecode)

export function computePoolAddress(factoryAddress: string, [tokenA, tokenB]: [string, string], fee: number): string {
  const [token0, token1] = tokenA.toLowerCase() < tokenB.toLowerCase() ? [tokenA, tokenB] : [tokenB, tokenA]
  const constructorArgumentsEncoded = ethers.AbiCoder.defaultAbiCoder().encode(
    ['address', 'address', 'uint24'],
    [token0, token1, fee]
  )

  // console.log(`POOL_BYTECODE_HASH: ${POOL_BYTECODE_HASH}`);
  
  const create2Inputs = [
    '0xff',
    factoryAddress,
    // salt
    ethers.keccak256(constructorArgumentsEncoded),
    // init code hash
    POOL_BYTECODE_HASH,
  ]
  const sanitizedInputs = `0x${create2Inputs.map((i) => i.slice(2)).join('')}`
  return ethers.getAddress(`0x${ethers.keccak256(sanitizedInputs).slice(-40)}`)
}
