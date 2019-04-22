/* eslint-disable no-console, require-jsdoc */
'use strict';

const fs = require('fs');
const path = require('path');
const PegTokenizer = require('../src/tokenizer.js');

const nop = () => {};
const returnFalse = () => false;
const env = {
  log: nop,
  conf: {
    wiki: {
      extTags: ['pre', 'nowiki', 'gallery', 'indicator', 'timeline',
        'hiero', 'charinsert', 'ref', 'references', 'inputbox', 'imagemap',
        'source', 'syntaxhighlight', 'poem', 'section', 'score',
        'templatedata', 'math', 'ce', 'chem', 'graph', 'maplink',
        'categorytree'],
      getMagicWordMatcher: () => {return { test: returnFalse };}, /* eslint-disable-line */
      isMagicWord: returnFalse,
      hasValidProtocol: (prot) => /^http/.test(prot),
    },
    maxDepth: 40,
  },
  immutable: false,
  langConverterEnabled: () => true, // true always
  newAboutId: () => '#1', // #1 always
};

function parse(input) {
  const tokenizer = new PegTokenizer.PegTokenizer(env);
  tokenizer.initTokenizer();
  let tokens = [];
  tokenizer.tokenizeSync(input, {
    cb: (t) => {tokens = tokens.concat(t);}, /* eslint-disable-line */
    pegTokenizer: tokenizer,
    pipelineOffset: 0,
    env: env,
    pegIncludes: PegTokenizer.pegIncludes,
    startRule: 'start',
  });
  return tokens;
}
let inputFile = path.join(__dirname, 'gratis.txt');
let input = fs.readFileSync(inputFile, {encoding: 'utf8'});
let output = parse(input).map((t) => JSON.stringify(t)).join('\n') + '\n';
fs.writeFileSync(path.join(__dirname, 'gratis.tokens'), output);

inputFile = path.join(__dirname, 'imap.txt');
input = fs.readFileSync(inputFile, {encoding: 'utf8'});
output = parse(input).map((t) => JSON.stringify(t)).join('\n') + '\n';
fs.writeFileSync(path.join(__dirname, 'imap.tokens'), output);
