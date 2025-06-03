import { ethers, run } from "hardhat";
import path from "path";
import fs from "fs";
import { loadConfig, saveConfig } from "../utils/config";
import { PoolAddressHelper } from "../../typechain-types/";
import { ContractFactory, Contract, BaseContract } from "ethers";

// Utility to load/save JSON config
const configPath = path.join(__dirname, "config.json");
interface ExchangeConfig {
  WETH9: string; // address of WETH9 token
  POOL_LIBRARY?: string;
  TOKEN_CONVERTER?: string;
  FACTORY?: string;
  ADDRESS_HELPER?: string; // address of PoolAddressHelper
  // POOL_HELPER?: string;
  SWAP_ROUTER?: string;
  // QUOTER?: string;
  // NFT_DESCRIPTOR?: string;
  // POSITION_DESCRIPTOR?: string;
  POSITION_MANAGER?: string;
  // NATIVE_LABEL?: string; // e.g. "ETH"
}

// Link libraries into bytecode
// type LinkRefs = Record<
//   string,
//   Record<string, { start: number; length: number }[]>
// >;
// function linkLibraries(
//   { bytecode, linkReferences }: { bytecode: string; linkReferences: LinkRefs },
//   libraries: Record<string, string>
// ): string {
//   Object.entries(linkReferences).forEach(([fileName, contracts]) => {
//     Object.entries(contracts).forEach(([contractName, refs]) => {
//       const addrHex = ethers
//         .getAddress(libraries[contractName])
//         .slice(2)
//         .toLowerCase();
//       refs.forEach(({ start, length }) => {
//         const startPos = 2 + start * 2;
//         const len = length * 2;
//         bytecode = bytecode
//           .slice(0, startPos)
//           .concat(addrHex)
//           .concat(bytecode.slice(startPos + len));
//       });
//     });
//   });
//   return bytecode;
// }

// async function getPoolHashCode(signer: any, contract: PoolAddressHelper) {
//   const code = await contract.connect(signer).getPoolCreationCode();

//   return contract.connect(signer).hashPoolCode(code);
// }

async function getPoolHashCode(signer: any, contract: PoolAddressHelper) {
  const code = await contract.connect(signer).getPoolCreationCode();

  return contract.connect(signer).hashPoolCode(code);
}

const Dex223PoolArtifact = require(path.join(
  __dirname,
  "../../artifacts/contracts/dex-core/Dex223Pool.sol/Dex223Pool.json"
));

async function computePoolInitCodeHash(POOL_LIBRARY_ADDRESS: string) {
  // 1) Берём сырой байткод Dex223Pool:
  let creationCode: string = Dex223PoolArtifact.bytecode as string;
  const linkRefs = Dex223PoolArtifact.linkReferences as Record<
    string,
    Record<string, Array<{ start: number; length: number }>>
  >;

  // 2) Линкуем PoolLibrary:
  Object.entries(linkRefs).forEach(([fileName, contracts]) => {
    Object.entries(contracts).forEach(([contractName, refs]) => {
      if (contractName === "PoolLibrary") {
        const libAddressHex = POOL_LIBRARY_ADDRESS.replace(
          /^0x/,
          ""
        ).toLowerCase();
        refs.forEach(({ start, length }) => {
          const startPos = 2 + start * 2;
          const replaceLen = length * 2;
          creationCode =
            creationCode.slice(0, startPos) +
            libAddressHex +
            creationCode.slice(startPos + replaceLen);
        });
      }
    });
  });

  // 3) Возвращаем keccak256 от «линкнутого» кода:
  return ethers.keccak256(creationCode);
}

async function main() {
  const [owner] = await ethers.getSigners();
  const cfg = loadConfig(configPath) as ExchangeConfig;

  // Ensure WETH9 address is provided in config
  if (!cfg.WETH9) {
    throw new Error("WETH9 address missing in config.json (cfg.WETH9)");
  }

  // const nativeLabel = cfg.NATIVE_LABEL || "WETH";
  // const nativeLabelBytes = ethers.encodeBytes32String(nativeLabel);
  // if (!cfg.ADDRESS_HELPER) {
  //   console.log("Deploying PoolAddressHelper...");
  //   // 1) Деплой самого PoolAddressHelper
  //   const addressHelperFactory = await ethers.getContractFactory(
  //     "contracts/dex-core/Dex223Factory.sol:PoolAddressHelper"
  //   );
  //   const addressHelper = await addressHelperFactory.deploy();
  //   await addressHelper.waitForDeployment();
  //   cfg.ADDRESS_HELPER = await addressHelper.getAddress();
  //   console.log("PoolAddressHelper at", cfg.ADDRESS_HELPER);
  //   saveConfig(configPath, cfg);

  //   // 2) Генерация POOL_INIT_CODE_HASH
  //   const poolHash = await getPoolHashCode(owner, addressHelper);
  //   console.log(`PoolHash: ${poolHash}`);

  //   // 3) Замена в PoolAddress.sol
  //   const poolAddressFile = path.join(
  //     __dirname,
  //     "../contracts/dex-periphery/base/PoolAddress.sol"
  //   );
  // }

  // get pool hash from contract

  // 1) Deploy PoolLibrary
  if (!cfg.POOL_LIBRARY) {
    console.log("Deploying PoolLibrary...");
    const libFactory = await ethers.getContractFactory(
      "contracts/dex-core/Dex223PoolLib.sol:Dex223PoolLib"
    );
    const lib = await libFactory.deploy();
    await lib.waitForDeployment();
    cfg.POOL_LIBRARY = await lib.getAddress();
    console.log("PoolLibrary at", cfg.POOL_LIBRARY);
    saveConfig(configPath, cfg);
  }
  const hash = await computePoolInitCodeHash(cfg.POOL_LIBRARY);
  console.log("POOL_INIT_CODE_HASH = ", hash);

  // 2) Deploy TokenConverter
  if (!cfg.TOKEN_CONVERTER) {
    console.log("Deploying TokenConverter...");
    const convFactory = await ethers.getContractFactory(
      "contracts/converter/TokenConverter.sol:ERC7417TokenConverter"
    );
    const conv = await convFactory.deploy();
    await conv.waitForDeployment();
    cfg.TOKEN_CONVERTER = await conv.getAddress();
    console.log("Converter at", cfg.TOKEN_CONVERTER);
    saveConfig(configPath, cfg);
  }

  // 3) Deploy Factory
  if (!cfg.FACTORY) {
    console.log("Deploying Factory...");
    const facFactory = await ethers.getContractFactory(
      "contracts/dex-core/Dex223Factory.sol:Dex223Factory"
    );
    const factory = await facFactory.deploy();
    await factory.waitForDeployment();
    cfg.FACTORY = await factory.getAddress();
    console.log("Factory at", cfg.FACTORY);
    saveConfig(configPath, cfg);
  }

  if (!cfg.SWAP_ROUTER) {
    const swapRouterFactory = await ethers.getContractFactory(
      "contracts/dex-periphery/SwapRouter.sol:ERC223SwapRouter"
    );
    const swapRouter = await swapRouterFactory.deploy(cfg.FACTORY, cfg.WETH9);
    await swapRouter.waitForDeployment();
    cfg.SWAP_ROUTER = await swapRouter.getAddress();
    console.log("SWAP_ROUTER at", cfg.SWAP_ROUTER);
    saveConfig(configPath, cfg);
  }
  // 5) Deploy core periphery contracts
  // const periphery = [
  //   {
  //     key: "SWAP_ROUTER",
  //     fqName: "contracts/dex-periphery/SwapRouter.sol:ERC223SwapRouter",
  //     args: [cfg.FACTORY, cfg.POOL_LIBRARY],
  //   },
  //   // {
  //   //   key: "QUOTER",
  //   //   fqName: "contracts/dex-periphery/lens/Quoter223.sol:ERC223Quoter",
  //   //   args: [cfg.FACTORY, cfg.WETH9],
  //   // },
  //   {
  //     key: "NFT_DESCRIPTOR",
  //     fqName: "contracts/dex-periphery/base/NFTDescriptor.sol:NFTDescriptor",
  //   },
  // ];
  // for (const { key, fqName, args } of periphery) {
  //   if (!cfg[key]) {
  //     console.log(`Deploying ${fqName.split(":")[1]}...`);
  //     const fac = await ethers.getContractFactory(fqName);
  //     const inst = await fac.deploy(...(args || []));
  //     await inst.waitForDeployment();
  //     cfg[key] = await inst.getAddress();
  //     console.log(`${fqName.split(":")[1]} at`, cfg[key]);
  //     saveConfig(configPath, cfg);
  //   }
  // }

  // 6) Link and deploy NonfungibleTokenPositionDescriptor
  // if (!cfg.POSITION_DESCRIPTOR) {
  //   console.log("Linking PositionDescriptor...");
  //   const art = require("../../artifacts/contracts/dex-periphery/NonfungibleTokenPositionDescriptor.sol/NonfungibleTokenPositionDescriptor.json");
  //   const linkedBytecode = linkLibraries(
  //     { bytecode: art.bytecode, linkReferences: art.linkReferences },
  //     { NFTDescriptor: cfg.NFT_DESCRIPTOR! }
  //   );
  //   console.log("Deploying NonfungibleTokenPositionDescriptor...");
  //   const descriptorFactory = new ethers.ContractFactory(
  //     art.abi,
  //     linkedBytecode,
  //     deployer
  //   );
  //   const desc = await descriptorFactory.deploy(cfg.WETH9, nativeLabelBytes);
  //   await desc.waitForDeployment();
  //   cfg.POSITION_DESCRIPTOR = await desc.getAddress();
  //   console.log("PositionDescriptor at", cfg.POSITION_DESCRIPTOR);
  //   saveConfig(configPath, cfg);
  // }

  // 7) Deploy NonfungiblePositionManager
  if (!cfg.POSITION_MANAGER) {
    console.log("Deploying NonfungiblePositionManager...");
    const mgrFac = await ethers.getContractFactory(
      "contracts/dex-periphery/NonfungiblePositionManager.sol:DexaransNonfungiblePositionManager"
    );
    const mgr = await mgrFac.deploy(cfg.FACTORY, cfg.WETH9);
    await mgr.waitForDeployment();
    cfg.POSITION_MANAGER = await mgr.getAddress();
    console.log("PositionManager at", cfg.POSITION_MANAGER);
    saveConfig(configPath, cfg);
  }

  console.log("Deployment complete.");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
