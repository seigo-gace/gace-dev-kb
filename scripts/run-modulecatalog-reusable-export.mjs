#!/usr/bin/env node
import path from 'node:path';
import process from 'node:process';
import { pathToFileURL } from 'node:url';

const [catalogRootArg, outputRootArg, catalogCommit] = process.argv.slice(2);
if (!catalogRootArg || !outputRootArg || !catalogCommit) {
  console.error('usage: node run-modulecatalog-reusable-export.mjs <catalog-root> <output-root> <catalog-commit>');
  process.exit(2);
}

const catalogRoot = path.resolve(catalogRootArg);
const outputRoot = path.resolve(outputRootArg);
const moduleUrl = pathToFileURL(path.join(catalogRoot, 'src', 'reusable-asset-export.js')).href;
const { exportReusableAssets } = await import(moduleUrl);
const result = await exportReusableAssets(catalogRoot, outputRoot, { catalogCommit });
if (result?.catalog?.commit !== catalogCommit) {
  throw new Error(`EXPORT_COMMIT_MISMATCH expected=${catalogCommit} actual=${result?.catalog?.commit}`);
}
console.log(`MODULECATALOG_REUSABLE_EXPORT=PASS COMMIT=${catalogCommit} ASSETS=${result.assetCount} OUTPUT=${outputRoot}`);
console.log(JSON.stringify(result));
