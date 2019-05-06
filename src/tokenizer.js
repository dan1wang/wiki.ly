/* eslint-disable no-console, require-jsdoc */
/**
 * Tokenizer for wikitext, using WikiPEG and a
 * separate PEG grammar file
 * (pegTokenizer.pegjs)
 */

'use strict';

const PEG = require('wikipeg');
const path = require('path');
const fs = require('fs');
const events = require('events');
const util = require('util');
const Util = require('./utils/Util.js').Util;

const HTMLTags = {
  HTML5: [
    'A', 'ABBR', 'ADDRESS', 'AREA', 'ARTICLE',
    'ASIDE', 'AUDIO', 'B', 'BASE', 'BDI', 'BDO', 'BLOCKQUOTE',
    'BODY', 'BR', 'BUTTON', 'CANVAS', 'CAPTION', 'CITE', 'CODE',
    'COL', 'COLGROUP', 'COMMAND', 'DATA', 'DATALIST', 'DD', 'DEL',
    'DETAILS', 'DFN', 'DIV', 'DL', 'DT', 'EM', 'EMBED', 'FIELDSET',
    'FIGCAPTION', 'FIGURE', 'FOOTER', 'FORM',
    'H1', 'H2', 'H3', 'H4', 'H5', 'H6', 'HEAD', 'HEADER', 'HGROUP',
    'HR', 'HTML', 'I', 'IFRAME', 'IMG', 'INPUT', 'INS', 'KBD', 'KEYGEN',
    'LABEL', 'LEGEND', 'LI', 'LINK', 'MAP', 'MARK', 'MENU', 'META',
    'METER', 'NAV', 'NOSCRIPT', 'OBJECT', 'OL', 'OPTGROUP', 'OPTION',
    'OUTPUT', 'P', 'PARAM', 'PRE', 'PROGRESS', 'Q', 'RB', 'RP', 'RT',
    'RTC', 'RUBY', 'S', 'SAMP', 'SCRIPT', 'SECTION', 'SELECT', 'SMALL',
    'SOURCE', 'SPAN', 'STRONG', 'STYLE', 'SUB', 'SUMMARY', 'SUP',
    'TABLE', 'TBODY', 'TD', 'TEXTAREA', 'TFOOT', 'TH', 'THEAD', 'TIME',
    'TITLE', 'TR', 'TRACK', 'U', 'UL', 'VAR', 'VIDEO', 'WBR'],
  DepHTML: ['STRIKE', 'BIG', 'CENTER', 'FONT', 'TT'],
  HTML4Block: [
    'DIV', 'P',
    'TABLE', 'TBODY', 'THEAD', 'TFOOT', 'CAPTION', 'TH', 'TR', 'TD',
    'UL', 'OL', 'LI', 'DL', 'DT', 'DD',
    'H1', 'H2', 'H3', 'H4', 'H5', 'H6', 'HGROUP',
    'ARTICLE', 'ASIDE', 'NAV', 'SECTION', 'FOOTER', 'HEADER',
    'FIGURE', 'FIGCAPTION', 'FIELDSET', 'DETAILS', 'BLOCKQUOTE',
    'HR', 'BUTTON', 'CANVAS', 'CENTER', 'COL', 'COLGROUP', 'EMBED',
    'MAP', 'OBJECT', 'PRE', 'PROGRESS', 'VIDEO'],
  HTML4Inline: [
    'A', 'ABBR', /* 'ACRONYM', */ 'B', 'BIG', 'BDO', 'BR', 'BUTTON',
    'CITE', 'CODE', 'DFN', 'EM', 'FONT', 'I', 'IMG', 'INPUT',
    'KBD', 'LABEL', 'MAP', 'Q', 'OBJECT',
    'S', 'SAMP', 'SCRIPT', 'SELECT', 'SMALL', 'SPAN', 'STRIKE',
    'STRONG', 'SUB', 'SUP', 'TEXTAREA', 'TIME', 'TT',
    'U', 'VAR'],
  Void: [
    'AREA', 'BASE', 'BR', 'COL', 'COMMAND', 'EMBED', 'HR', 'IMG',
    'INPUT', 'KEYGEN', 'LINK', 'META', 'PARAM', 'SOURCE',
    'TRACK', 'WBR'],
};

const pegIncludes = {
  HTMLTags: HTMLTags,
  Token: require('./Token.js'),
  TokenUtils: require('./utils/TokenUtils.js').TokenUtils,
  tu: require('./tokenizer.utils.js'),
  Util: Util,
};

/**
 * @class
 * @extends EventEmitter
 * @param {MWParserEnvironment} env
 * @param {Object} options
 */
function PegTokenizer(env, options) {
  events.EventEmitter.call(this);
  this.env = env;
  this.options = options || {};
  this.offsets = {};
}

pegIncludes.PegTokenizer = PegTokenizer;

// Inherit from EventEmitter
util.inherits(PegTokenizer, events.EventEmitter);

PegTokenizer.prototype.compileTokenizer = function() {
  function readSrc(fName) {
    const pegSrcPath = path.join(__dirname, fName);
    return fs.readFileSync(pegSrcPath, 'utf8');
  }
  function pegOrExpression(words, caseSensitive) {
    const re = /['"\\]/g;
    const replacer = '\\$&';
    return words.map( (w) => {
      return `"${w.replace(re, replacer)}"${(caseSensitive?'':'i')}`;
    }).join('/');
  }

  const protocols =
    pegOrExpression(this.env.conf.wiki.protocols, false);
  const redirects =
    pegOrExpression(
        this.env.conf.wiki.redirectWords,
        this.env.conf.wiki.redirectWordsIsCaseSensitive
    );

  const src = readSrc('wiki.pegjs').replace('"%REDIRECTS%"', redirects) // link
        + readSrc('wikilink.pegjs').replace('"%PROTOCOLS%"', protocols) // link
        + readSrc('wikitemplate.pegjs') // template and links
        + readSrc('wikitag.pegjs') // <tag>
        + readSrc('wikilist.pegjs')
        + readSrc('wikitable.pegjs')
        + readSrc('wikitext.pegjs');
  // fs.writeFileSync('src.pegjs', src);
  const parseTokenizer = PEG.parser.parse(src);

  const compiler = PEG.compiler;

  const passes = {
    check: [
      compiler.passes.check.reportMissingRules,
      compiler.passes.check.reportLeftRecursion,
    ],
    transform: [
      compiler.passes.transform.analyzeParams,
    ],
    generate: [
      compiler.passes.generate.astToCode,
    ],
  };

  function jsCacheRuleHook(opts) {
    let keyParts = [
      opts.variantIndex + opts.variantCount * (opts.ruleIndex + opts.ruleCount),
    ];
    if (opts.params.length) {
      keyParts = keyParts.concat(opts.params);
    }
    const key = (keyParts.length === 1)
      ? keyParts[0]
      : `[${keyParts.join(', ')}].map(String).join(':')`;

    const maxVisitCount = 20;
    const cacheBits = {
      start:
  `const checkCache = visitCounts[${opts.startPos}] > ${maxVisitCount};
  let cached, bucket, key;
  if (checkCache) {
    key = ${key};
    bucket = ${opts.startPos};
    if ( !peg$cache[bucket] ) { peg$cache[bucket] = {}; }
    cached = peg$cache[bucket][key];
    if (cached) {
      peg$currPos = cached.nextPos;
          ${opts.loadRefs}
      return cached.result;
    }
      ${opts.saveRefs}
  } else {
    visitCounts[${opts.startPos}]++;
  }`,
      store:
`if (checkCache) {
cached = peg$cache[bucket][key] = {
  nextPos: ${opts.endPos},
  result: ${opts.result},
};
${opts.storeRefs}
}`,
    };
    return cacheBits;
  }

  function jsCacheInitHook(opts) {
    return [
      'const peg$cache = {};',
      'const visitCounts = new Uint8Array(input.length);',
    ].join('\n');
  }

  const options = {
    cache: true,
    trackLineAndColumn: false,
    output: 'source',
    language: 'javascript',
    cacheRuleHook: jsCacheRuleHook,
    cacheInitHook: jsCacheInitHook,
    className: null,
    allowedStartRules: [
      'start',
      'table_start_tag',
      'url',
      'row_syntax_table_args',
      'table_attributes',
      'generic_newline_attributes',
      'tplarg_or_template_or_bust',
      'extlink',
    ],
    allowedStreamRules: [
      'start_async',
    ],
  };

  return compiler.compile(parseTokenizer, passes, options);
};

PegTokenizer.prototype.initTokenizer = function() {
  const tokenizerSource = this.compileTokenizer();
  PegTokenizer.prototype.tokenizer = new Function('return ' + tokenizerSource)();  // eslint-disable-line
};

// Debugging aid: Set pipeline id.
PegTokenizer.prototype.setPipelineId = function(id) {
  this.pipelineId = id;
};

PegTokenizer.prototype._tokenize = function(text, args) {
  if (typeof text === 'object') text = text.toString('utf8');
  const ret = this.tokenizer.parse(text, args);
  return ret;
};

/**
 * The main worker. Sets up event emission ('chunk' and 'end' events).
 * Consumers are supposed to register with PegTokenizer before calling
 * process().
 *
 * @param {string} text
 * @param {boolean} sol Whether text should be processed in start-of-line
 *   context.
 */
PegTokenizer.prototype.tokenizeAsync = function(text, sol) {
  if (!this.tokenizer) {
    this.initTokenizer();
  }

  // ensure we're processing text
  text = String(text || '');

  const chunkCB = (tokens) => this.emit('chunk', tokens);

  // Kick it off!
  const pipelineOffset = this.offsets.startOffset || 0;
  const args = {
    cb: chunkCB,
    pegTokenizer: this,
    pipelineOffset: pipelineOffset,
    pegIncludes: pegIncludes,
    sol: sol,
  };

  args.startRule = 'start_async';
  args.stream = true;

  let iterator;
  const pegTokenizer = this;

  const tokenizeChunk = () => {
    let next;
    try {
      if (iterator === undefined) {
        iterator = pegTokenizer._tokenize(text, args);
      }
      next = iterator.next();
    } catch (e) {
      pegTokenizer.env.log('fatal', e);
      return;
    }

    if (next.done) {
      pegTokenizer.onEnd();
    } else {
      setImmediate(tokenizeChunk);
    }
  };

  tokenizeChunk();
};


PegTokenizer.prototype.onEnd = function() {
  // Reset source offsets
  this.offsets.startOffset = 0;
  this.offsets.endOffset = 0;
  this.emit('end');
};

/**
 * Tokenize via a rule passed in as an arg.
 * The text is tokenized synchronously in one shot.
 *
 * @param {string} text
 * @param {Object} [args]
 * @return {Array}
 */
PegTokenizer.prototype.tokenizeSync = function(text, args) {
  if (!this.tokenizer) {
    this.initTokenizer();
  }
  let toks = [];
  args = Object.assign({
    pipelineOffset: this.offsets.startOffset || 0,
    startRule: 'start',
    sol: true,
  }, {
    // Some rules use callbacks: start, tlb, toplevelblock.
    // All other rules return tokens directly.
    cb: function(r) {toks = toks.concat(r);}, /* eslint-disable-line */
    pegTokenizer: this,
    pegIncludes: pegIncludes,
  }, args);
  const retToks = this._tokenize(text, args);
  if (Array.isArray(retToks) && retToks.length > 0) {
    toks = toks.concat(retToks);
  }
  return toks;
};

// Tokenizes a string as a rule, otherwise returns an `Error`
PegTokenizer.prototype.tokenizeAs = function(text, rule, sol) {
  try {
    const args = {
      startRule: rule,
      sol: sol,
      pipelineOffset: 0,
    };
    return this.tokenizeSync(text, args);
  } catch (e) {
    // console.warn('Input: ' + text);
    // console.warn('Rule : ' + rule);
    // console.warn('ERROR: ' + e);
    // console.warn('Stack: ' + e.stack);
    return (e instanceof Error) ? e : new Error(e);
  }
};

module.exports = {
  PegTokenizer: PegTokenizer,
  pegIncludes: pegIncludes,
};
