#!/usr/bin/env node
import path from 'node:path';
import process from 'node:process';
import { pathToFileURL } from 'node:url';

function parseArgs(argv) {
  const result = {};
  for (let i = 0; i < argv.length; i += 1) {
    const value = argv[i];
    if (!value.startsWith('--')) throw new Error(`UNEXPECTED_ARGUMENT=${value}`);
    const key = value.slice(2);
    const next = argv[i + 1];
    if (!next || next.startsWith('--')) throw new Error(`MISSING_ARGUMENT_VALUE=${key}`);
    result[key] = next;
    i += 1;
  }
  return result;
}

const args = parseArgs(process.argv.slice(2));
const catalogRoot = path.resolve(args['catalog-root'] ?? '');
const outputRoot = path.resolve(args['output-root'] ?? '');
const catalogCommit = String(args['catalog-commit'] ?? '').trim();
const expectedAssetCount = args['expected-asset-count'] ? Number(args['expected-asset-count']) : null;

if (!catalogRoot) throw new Error('CATALOG_ROOT_MISSING');
if (!outputRoot) throw new Error('OUTPUT_ROOT_MISSING');
if (!catalogCommit) throw new Error('CATALOG_COMMIT_MISSING');
if (expectedAssetCount !== null && (!Number.isInteger(expectedAssetCount) || expectedAssetCount < 1)) {
  throw new Error(`EXPECTED_ASSET_COUNT_INVALID=${args['expected-asset-count']}`);
}

const modulePath = path.join(catalogRoot, 'src', 'reusable-asset-export.js');
const moduleUrl = pathToFileURL(modulePath).href;
const imported = await import(moduleUrl);
if (typeof imported.exportReusableAssets !== 'function') {
  throw new Error('MODULECATALOG_EXPORT_API_MISSING');
}

const result = await imported.exportReusableAssets(catalogRoot, outputRoot, { catalogCommit });
if (!result || result.format !== 'gace.reusable-asset.v1') {
  throw new Error(`MODULECATALOG_EXPORT_FORMAT_INVALID=${result?.format}`);
}
if (result.catalog?.repository !== 'seigo-gace/modular-catalog') {
  throw new Error(`MODULECATALOG_EXPORT_REPOSITORY_INVALID=${result.catalog?.repository}`);
}
if (result.catalog?.commit !== catalogCommit) {
  throw new Error(`MODULECATALOG_EXPORT_COMMIT_MISMATCH expected=${catalogCommit} actual=${result.catalog?.commit}`);
}
if (expectedAssetCount !== null && result.assetCount !== expectedAssetCount) {
  throw new Error(`MODULECATALOG_EXPORT_ASSET_COUNT_MISMATCH expected=${expectedAssetCount} actual=${result.assetCount}`);
}

const knowledgeUnits = Array.isArray(result.assets)
  ? result.assets.reduce((total, item) => total + Number(item.knowledgeUnits ?? 0), 0)
  : 0;
const cases = Array.isArray(result.assets)
  ? result.assets.reduce((total, item) => total + Number(item.cases ?? 0), 0)
  : 0;

console.log(`GACE_MODULECATALOG_EXPORT=PASS ASSETS=${result.assetCount} KNOWLEDGE_UNITS=${knowledgeUnits} CASES=${cases} COMMIT=${catalogCommit} OUTPUT=${outputRoot}`);
