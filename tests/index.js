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
      protocols: ['ftp://', 'ftps://', 'git://', 'http://', 'https://', 'mailto:'],
      extTags: ['pre', 'nowiki', 'gallery', 'indicator', 'timeline',
        'hiero', 'charinsert', 'ref', 'references', 'inputbox', 'imagemap',
        'source', 'syntaxhighlight', 'poem', 'section', 'score',
        'templatedata', 'math', 'ce', 'chem', 'graph', 'maplink',
        'categorytree'],
      redirectWords: ['#REDIRECT', '#REDIRECCIÓN'],
      redirectWordsIsCaseSensitive: true,
      isMagicWord: returnFalse,
    },
    maxDepth: 40,
  },
  immutable: false,
  langConverterEnabled: () => true, // true always
};

const tokenizer = new PegTokenizer.PegTokenizer(env);
tokenizer.initTokenizer();

function parse(input) {
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

const pathText = path.join(__dirname, '/text');
const pathToken = path.join(__dirname, '/tokens');
fs.readdirSync(pathText).forEach((fName) => {
  const inputFilePath = path.join(pathText, '/', fName);
  const outputFilePath = path.join(
      pathToken, '/', fName.replace(/\..*$/, '') + '.tokens'
  );
  const input = fs.readFileSync(inputFilePath, {encoding: 'utf8'});
  const output = parse(input).map((t) => JSON.stringify(t)).join('\n') + '\n';
  fs.writeFileSync(outputFilePath, output);
});

// #REDIRECT only works if preceeded by nothing except spaces and line feeds.
// Otherwise, it should evalutes as a list item
const redirectTest =
  (parse('#REDIRECT\r\n\t [[somewhere]]')[0].name === 'mw:redirect') &&
  (parse('<!--????-->#REDIRECT [[somewhere]]')[2] === 'REDIRECT ');
console.log('Redirect test: ' + (redirectTest?'pass':'fail'));
