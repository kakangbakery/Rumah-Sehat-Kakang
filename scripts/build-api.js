import {build} from 'esbuild';
import {mkdir,readFile,writeFile} from 'node:fs/promises';
// Merge Express into the SvelteKit Vercel Build Output so /api is a real Node function.
const output='.vercel/output';
await mkdir(output+'/functions/api.func',{recursive:true});
await build({entryPoints:['server/app.js'],bundle:true,platform:'node',target:'node22',format:'cjs',outfile:output+'/functions/api.func/index.cjs',footer:{js:'module.exports = module.exports.default;'}});
await writeFile(output+'/functions/api.func/.vc-config.json',JSON.stringify({runtime:'nodejs22.x',handler:'index.cjs',launcherType:'Nodejs',shouldAddHelpers:true}));
const config=JSON.parse(await readFile(output+'/config.json','utf8'));
config.routes.unshift({src:'/api(?:/.*)?',dest:'/api'});
await writeFile(output+'/config.json',JSON.stringify(config,null,2));
