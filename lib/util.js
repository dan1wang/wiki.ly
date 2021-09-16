// @msikma/wiki-ly <https://github.com/msikma/wiki-ly>
// © MIT license

/** No-op function. */
const noop = () => {}

/** Helper functions used by the parser to switch certain features on/off. */
const alwaysFalse = () => false
const alwaysTrue = () => true

module.exports = {
  noop,
  alwaysFalse,
  alwaysTrue
}
