// @msikma/wiki-ly <https://github.com/msikma/wiki-ly>
// © MIT license

const fs = require('fs').promises
const path = require('path')
const { createParser } = require('./index')

/** These are wikitext files with associated expected token JSONL files. */
const testCases = ['comment', 'gratis', 'heading', 'imap', 'lang_variants', 'links', 'tables']

/** Returns the contents of a test file. */
const getTestFile = async (name, dir, ext) => {
  const filepath = path.join(__dirname, 'tests', dir, `${name}.${ext}`)
  return fs.readFile(filepath, 'utf8')
}

/** Returns the contents of the two files that make up a test case. */
const getTestFiles = async base => {
  const contentText = await getTestFile(base, 'text', 'txt')
  const contentTokens = (await getTestFile(base, 'tokens', 'jsonl')).split('\n')
  return [contentText, contentTokens]
}

describe(`@msikma/wiki-ly package`, () => {
  describe(`createParser()`, () => {
    it(`correctly parses the test cases`, async () => {
      const parser = createParser()
      for (const testCase of testCases) {
        const [text, tokens] = await getTestFiles(testCase)
        const result = parser.parse(text)

        for (let n = 0; n < result.length; ++n) {
          expect(JSON.stringify(result[n])).toBe(tokens[n])
        }
      }
    })
  })
})
