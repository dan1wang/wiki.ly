/* eslint-disable no-console, require-jsdoc */
'use strict';

const {KV, TagTk, EndTagTk, SelfclosingTagTk, NlTk, EOFTk, CommentTk} =
  require('../tokens/TokenTypes.js');

const lastItem = (array) => array[array.length - 1];

const TokenUtils = {
  shiftTokenTSR: function(tokens, offset, clearIfUnknownOffset) {
    // Bail early if we can
    if (offset === 0) return;

    // offset should either be a valid number or null
    if (offset === undefined) {
      if (clearIfUnknownOffset) {
        offset = null;
      } else {
        return;
      }
    }

    const THIS = this;

    function updateTsr(i, t) {
      const da = tokens[i].dataAttribs;
      const tsr = da.tsr;
      if (tsr) {
        if (offset !== null) {
          da.tsr = [tsr[0] + offset, tsr[1] + offset];
        } else {
          da.tsr = null;
        }
      }

      // SSS FIXME: offset will always be available in
      // chunky-tokenizer mode in which case we wont have
      // buggy offsets below.  The null scenario is only
      // for when the token-stream-patcher attempts to
      // reparse a string -- it is likely to only patch up
      // small string fragments and the complicated use cases
      // below should not materialize.

      // content offsets for ext-links
      if (offset && da.extLinkContentOffsets) {
        da.extLinkContentOffsets[0] += offset;
        da.extLinkContentOffsets[1] += offset;
      }

      //  Process attributes
      if (t.attribs) {
        for (let j = 0, m = t.attribs.length; j < m; j++) {
          const a = t.attribs[j];
          if (Array.isArray(a.k)) {
            THIS.shiftTokenTSR(a.k, offset, clearIfUnknownOffset);
          }
          if (Array.isArray(a.v)) {
            THIS.shiftTokenTSR(a.v, offset, clearIfUnknownOffset);
          }

          // src offsets used to set mw:TemplateParams
          if (offset === null) {
            a.srcOffsets = null;
          } else if (a.srcOffsets) {
            for (let k = 0; k < a.srcOffsets.length; k++) {
              a.srcOffsets[k] += offset;
            }
          }
        }
      }
    }

    // update/clear tsr
    for (let i = 0, n = tokens.length; i < n; i++) {
      const t = tokens[i];
      switch (t && t.constructor) {
        case TagTk:
        case SelfclosingTagTk:
        case NlTk:
        case CommentTk:
        case EndTagTk: updateTsr(i, t); break;
        default: break;
      }
    }
  },

  // Trim space and newlines from leading and trailing text tokens.
  tokenTrim: function(tokens) {
    if (!Array.isArray(tokens)) {
      if (tokens.constructor === String) return tokens.trim();
      return tokens;
    }

    // Since the tokens array might be frozen,
    // we have to create a new array -- but, create it
    // only if needed
    //
    // FIXME: If tokens is not frozen, we can avoid
    // all this circus with leadingToks and trailingToks
    // but we will need a new function altogether -- so,
    // something worth considering if this is a perf. problem.

    let i;
    let token;
    const n = tokens.length;

    // strip leading space
    const leadingToks = [];
    for (i = 0; i < n; i++) {
      token = tokens[i];
      if (token.constructor === NlTk) {
        leadingToks.push('');
      } else if (token.constructor === String) {
        leadingToks.push(token.replace(/^\s+/, ''));
        if (token !== '') {
          break;
        }
      } else {
        break;
      }
    }

    i = leadingToks.length;
    if (i > 0) {
      tokens = leadingToks.concat(tokens.slice(i));
    }

    // strip trailing space
    const trailingToks = [];
    for (i = n - 1; i >= 0; i--) {
      token = tokens[i];
      if (token.constructor === NlTk) {
        trailingToks.push(''); // replace newline with empty
      } else if (token.constructor === String) {
        trailingToks.push(token.replace(/\s+$/, ''));
        if (token !== '') {
          break;
        }
      } else {
        break;
      }
    }

    const j = trailingToks.length;
    if (j > 0) {
      tokens = tokens.slice(0, n - j).concat(trailingToks.reverse());
    }

    return tokens;
  },

  // Strip EOFTk token from token chunk.
  stripEOFTkfromTokens: function(tokens) {
    // this.dp( 'stripping end or whitespace tokens' );
    if (!Array.isArray(tokens)) {
      tokens = [tokens];
    }
    if (!tokens.length) {
      return tokens;
    }
    // Strip 'end' token
    if (tokens.length && lastItem(tokens).constructor === EOFTk) {
      const rank = tokens.rank;
      tokens = tokens.slice(0, -1);
      tokens.rank = rank;
    }

    return tokens;
  },

  placeholder: function(content, dataAttribs, endAttribs) {
    if (content === null) {
      return [
        new SelfclosingTagTk('meta', [
          new KV('typeof', 'mw:Placeholder'),
        ], dataAttribs),
      ];
    } else {
      return [
        new TagTk('span', [
          new KV('typeof', 'mw:Placeholder'),
        ], dataAttribs),
        content,
        new EndTagTk('span', [], endAttribs),
      ];
    }
  },
};

if (typeof module === 'object') {
  module.exports.TokenUtils = TokenUtils;
}
