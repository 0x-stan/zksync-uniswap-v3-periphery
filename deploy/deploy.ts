import { asciiStringToBytes32, deployContract, deployContractWithArtifact } from './utils'
import * as fs from 'fs'
import * as path from 'path'
import { network } from 'hardhat'
import { ADD_1BP_FEE_TIER } from './add-1bp-fee-tier'

export default async function () {
  const weth9Address = '0x771C933F280B5b1a5Ef5D45A504935D142B15549'
  const factoryAddress = '0x24593C0BF4B17a129Eb7B2346B76e3fFE7720443'

  // UniswapV3Factory added a new fee tier
  await ADD_1BP_FEE_TIER(factoryAddress)

  // DEPLOY_MULTICALL2
  const multicall2 = await deployContract('UniswapInterfaceMulticall')

  // DEPLOY_TICK_LENS
  const tickLens = await deployContract('TickLens')

  // DEPLOY_NFT_DESCRIPTOR_LIBRARY
  const nftDescriptorLibrary = await deployContract('NFTDescriptor')

  const nftDescriptorLibraryAddress = await nftDescriptorLibrary.getAddress()

  // set hardhat config libraries after lib deployed
  const hre = require('hardhat')
  hre.config.zksolc.settings.libraries = {
    'contracts/libraries/NFTDescriptor.sol': {
      NFTDescriptor: nftDescriptorLibraryAddress,
    },
  }
  await hre.run('compile')

  // DEPLOY_NFT_POSITION_DESCRIPTOR_V1_3_0
  const positionDescriptor = await deployContractWithArtifact(
    hre.artifacts.readArtifactSync('NonfungibleTokenPositionDescriptor'),
    [weth9Address, asciiStringToBytes32('ETH')]
  )

  // DEPLOY_NONFUNGIBLE_POSITION_MANAGER
  const positionManager = await deployContract('NonfungiblePositionManager', [
    factoryAddress,
    weth9Address,
    await positionDescriptor.getAddress(),
  ])
  const positionManagerAddress = await positionManager.getAddress();

  // DEPLOY_V3_MIGRATOR
  const v3Migrator = await deployContract('V3Migrator', [factoryAddress, weth9Address, positionManagerAddress])

  // DEPLOY_V3_STAKER

  // DEPLOY_QUOTER_V2
  const quoterV2 = await deployContract('QuoterV2', [factoryAddress, weth9Address])

  // DEPLOY_V3_SWAP_ROUTER_02
  const router = await deployContract('SwapRouter', [factoryAddress, weth9Address])

  const deploymentFileDir = path.join(__dirname, `../deployments/deployment.${network.name}.json`)
  fs.writeFileSync(
    deploymentFileDir,
    JSON.stringify({
      multicall2Address: await multicall2.getAddress(),
      tickLensAddress: await tickLens.getAddress(),
      nftDescriptorLibraryAddress: await nftDescriptorLibrary.getAddress(),
      nonfungibleTokenPositionDescriptorAddress: await positionDescriptor.getAddress(),
      nonfungibleTokenPositionManagerAddress: positionManagerAddress,
      v3MigratorAddress: await v3Migrator.getAddress(),
      quoterV2Address: await quoterV2.getAddress(),
      swapRouter02Address: await router.getAddress(),
    })
  )
}
