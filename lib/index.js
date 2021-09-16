// @msikma/wiki-ly <https://github.com/msikma/wiki-ly>
// © MIT license

const tokenizerModule = require('./compiled/PegTokenizer.compiled.js')
const PegTokenizer = require('./parser/tokenizer')
const { getEnv } = require('./env')

/**
 * Creates a wikitext parser and returns an object with a parse() function.
 * 
 * This requires the tokenizer to have been compiled and available as <compiled/PegTokenizer.compiled.js>.
 */
const createParser = (opts = {}) => {
  const env = getEnv(opts)
  const parser = new PegTokenizer.PegTokenizer(tokenizerModule, env)

  /** Parses given input and returns an object of tokens. */
  const parse = input => {
    const tokens = []
    parser.tokenizeSync(input, {
      cb: t => tokens.push(...t),
      pegTokenizer: parser,
      pipelineOffset: 0,
      env: env,
      pegIncludes: PegTokenizer.pegIncludes,
      startRule: 'start',
    })
    return tokens
  }

  return {
    parse
  }
}

module.exports = {
  createParser
}
