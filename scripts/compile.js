#!/usr/bin/env node

const fs = require('fs').promises
const path = require('path')
const { getDefaultEnv } = require('../lib/env')
const PegTokenizer = require('../lib/parser/tokenizer');

async function main() {
  try {
    const tokenizer = new PegTokenizer.PegTokenizer(null, getDefaultEnv())
    const source = await tokenizer.getCompiledTokenizer()
    const filepath = path.join(__dirname, '..', 'lib', 'compiled', 'PegTokenizer.compiled.js')
    await fs.writeFile(filepath, `module.exports = ${source}`)
    process.exitCode = 0
  }
  catch (err) {
    console.log(`compile: could not compile PegTokenizer:\n`)
    console.log(err)
    process.exitCode = 1
  }
}

main()
