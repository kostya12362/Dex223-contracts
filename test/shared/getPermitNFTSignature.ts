import { Signature, Wallet } from 'ethers'
import { ethers } from 'hardhat'
import { DexaransNonfungiblePositionManager } from '../../typechain-types/'

export default async function getPermitNFTSignature(
  wallet: Wallet,
  positionManager: DexaransNonfungiblePositionManager,
  spender: string,
  tokenId: bigint | number,
  deadline: bigint | number = ethers.MaxUint256,
  permitConfig?: { nonce?: bigint; name?: string; chainId?: number; version?: string }
): Promise<Signature> {
  const [nonce, name, version, chainId] = await Promise.all([
    permitConfig?.nonce ?? positionManager.positions(tokenId).then((p) => p.nonce),
    permitConfig?.name ?? (await positionManager.name()),
    permitConfig?.version ?? '1',
    permitConfig?.chainId ?? (await wallet.provider?.getNetwork())?.chainId,
  ])

  return ethers.Signature.from(
    await wallet.signTypedData(
      {
        name,
        version,
        chainId,
        verifyingContract: positionManager.target.toString(),
      },
      {
        Permit: [
          {
            name: 'spender',
            type: 'address',
          },
          {
            name: 'tokenId',
            type: 'uint256',
          },
          {
            name: 'nonce',
            type: 'uint256',
          },
          {
            name: 'deadline',
            type: 'uint256',
          },
        ],
      },
      {
        owner: wallet.address,
        spender,
        tokenId,
        nonce,
        deadline,
      }
    )
  )
}
