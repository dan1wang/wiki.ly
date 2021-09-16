# Wiki.ly

Wiki.ly is a fork of Mediawiki's [Parsoid](https://github.com/wikimedia/parsoid) project. It's a PEG-based parser that converts wikitext to a Javascript object.

This particular version of Wiki.ly is a fork of [the original by @dan1wang](https://github.com/dan1wang/wiki.ly) to change the interface for package consumers, and to enable pre-compiling the tokenizer.

## Usage

To add this package to your project:

```
npm i --save "@msikma/wiki-ly"
```

### Example

A minimal example of running the parser with the default options:

```js
const { createParser } = require('@msikma/wiki-ly')

const input = `Hello [[world]]!`
const parser = createParser()
const output = parser.parse(input)

console.log(output)
```

This results in the following output:

```js
[
  'Hello ',
  SelfclosingTagTk {
    type: 'SelfclosingTagTk',
    name: 'wikilink',
    attribs: [ KV { k: 'href', v: [ 'world' ], vsrc: 'world' } ],
    dataAttribs: { tsr: [ 6, 15 ], src: '[[world]]' }
  },
  '!',
  EOFTk { type: 'EOFTk' }
]
```

It's possible to pass an object of environment options to the parser, but this is not documented right now. See `lib/env.js` for more information.

## License

This project is a fork of Wikimedia's [Parsoid](https://github.com/wikimedia/parsoid), which is licensed under the GPL v2.0.

[The port by @dan1wang](https://github.com/dan1wang/wiki.ly) is licensed under the MIT license.
