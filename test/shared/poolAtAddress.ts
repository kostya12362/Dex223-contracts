import { abi as POOL_ABI } from '../../artifacts/contracts/dex-core/Dex223Pool.sol/Dex223Pool.json'
import { BaseContract, Wallet } from 'ethers'
import { IUniswapV3Pool } from '../../typechain-types/'

export default function poolAtAddress(address: string, wallet: Wallet): IUniswapV3Pool {
  return new BaseContract(address, POOL_ABI, wallet) as IUniswapV3Pool
}
