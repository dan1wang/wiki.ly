// @msikma/wiki-ly <https://github.com/msikma/wiki-ly>
// © MIT license

const { noop, alwaysFalse, alwaysTrue } = require('./util')

/** Maximum recursion depth when parsing templates. This is the Parsoid default. */
const defaultMaxDepth = 40

/** List of protocols used for detecting URLs. */
const defaultProtocols = [
  'bitcoin:', 'ftp://',       'ftps://',
  'geo:',     'git://',       'gopher://',
  'http://',  'https://',     'irc://',
  'ircs://',  'magnet:',      'mailto:',
  'mms://',   'news:',        'nntp://',
  'redis://', 'sftp://',      'sip:',
  'sips:',    'sms:',         'ssh://',
  'svn://',   'tel:',         'telnet://',
  'urn:',     'worldwind://', 'xmpp:'
]

/** HTML tags that are treated as extensions; these may or may not be standard HTML tags. */
const defaultExtensionTags = [
  'pre',             'nowiki',
  'gallery',         'indicator',
  'timeline',        'hiero',
  'charinsert',      'ref',
  'references',      'inputbox',
  'imagemap',        'source',
  'syntaxhighlight', 'poem',
  'section',         'score',
  'templatedata',    'math',
  'ce',              'chem',
  'graph',           'maplink',
  'categorytree'
]

/** Magic words that indicate a page redirect. */
const defaultRedirectWords = [
  '#REDIRECT'
]

/**
 * Returns an environment object to use with a PegTokenizer.
 */
const getEnv = (opts = {}) => {
  const maxDepth = opts.maxDepth ?? defaultMaxDepth
  const protocols = opts.protocols ?? defaultProtocols
  const extensionTags = opts.extensionTags ?? defaultExtensionTags
  const redirectWords = opts.redirectWords ?? defaultRedirectWords
  const env = {
    log: noop,
    conf: {
      wiki: {
        protocols,
        extTags: extensionTags,
        redirectWords,
        redirectWordsIsCaseSensitive: true,
        // This might not be working correctly yet since it's disabled in wiki.ly's tests.
        // See <lib/parser/wiki.pegjs:892>.
        isMagicWord: alwaysFalse,
      },
      maxDepth,
    },
    immutable: false,
    langConverterEnabled: alwaysTrue
  }
  return env
}

/**
 * Calls getEnv() with an empty object to get all the defaults.
 */
const getDefaultEnv = (opts) => {
  return getEnv({})
}

module.exports = {
  getEnv,
  getDefaultEnv,
  defaultRedirectWords,
  defaultExtensionTags,
  defaultProtocols,
  defaultMaxDepth
}
