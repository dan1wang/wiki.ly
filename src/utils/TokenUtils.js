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

      // target offset
      if (offset && da.targetOff) {
        da.targetOff += offset;
      }

      // content offsets for ext-links
      if (offset && da.contentOffsets) {
        da.contentOffsets[0] += offset;
        da.contentOffsets[1] += offset;
      }

      // end offset for pre-tag
      if (offset && da.endpos) {
        da.endpos += offset;
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

  // Convert an array of key-value pairs into a hash of keys to values. For
  // duplicate keys, the last entry wins.
  kvToHash: function(kvs, convertValuesToString, useSrc) {
    if (!kvs) {
      console.warn('Invalid kvs!: ' + JSON.stringify(kvs, null, 2));
      return Object.create(null);
    }
    const res = Object.create(null);
    for (let i = 0, l = kvs.length; i < l; i++) {
      const kv = kvs[i];
      const key = this.tokensToString(kv.k).trim();
      // SSS FIXME: Temporary fix to handle extensions which use
      // entities in attribute values. We need more robust handling
      // of non-string template attribute values in general.
      const val =
        (useSrc && kv.vsrc !== undefined)
        ? kv.vsrc
        : convertValuesToString
          ? this.tokensToString(kv.v)
          : kv.v;
      res[key.toLowerCase()] = this.tokenTrim(val);
    }
    return res;
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

  kvsFromArray(a) {
    return a.map(function(e) {
      return new KV(e.k, e.v, e.srcOffsets || null, e.ksrc, e.vsrc);
    });
  },

  /**
   * Get a token from a JSON string
   *
   * @param {Object} jsTk
   * @return {Token}
   */
  getToken(jsTk) {
    if (!jsTk || !jsTk.type) {
      return jsTk;
    }

    switch (jsTk.type) {
      case 'SelfclosingTagTk':
        return new SelfclosingTagTk(
            jsTk.name,
            this.kvsFromArray(jsTk.attribs),
            jsTk.dataAttribs);
      case 'TagTk':
        return new TagTk(
            jsTk.name,
            this.kvsFromArray(jsTk.attribs),
            jsTk.dataAttribs);
      case 'EndTagTk':
        return new EndTagTk(
            jsTk.name,
            this.kvsFromArray(jsTk.attribs),
            jsTk.dataAttribs);
      case 'NlTk': return new NlTk(null, jsTk.dataAttribs);
      case 'EOFTk': return new EOFTk();
      case 'CommentTk': return new CommentTk(jsTk.value, jsTk.dataAttribs);
      default:
        // Looks like data-parsoid can have a 'type' property in some cases
        // We can change that usage and then throw an exception here.
        return jsTk;
    }
  },
};

if (typeof module === 'object') {
  module.exports.TokenUtils = TokenUtils;
}
