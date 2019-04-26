/* eslint-disable no-console, require-jsdoc */
'use strict';

const entities = require('entities');
const TokenUtils = require('./TokenUtils.js').TokenUtils;
const Token = require('../tokens/Token.js').Token;
const KV = require('../tokens/KV.js').KV;

const Util = {
  // deep clones by default.
  clone: function(obj, deepClone) {
    if (deepClone === undefined) {
      deepClone = true;
    }
    if (Array.isArray(obj)) {
      if (deepClone) {
        return obj.map(function(el) {
          return Util.clone(el, true);
        });
      } else {
        return obj.slice();
      }
    } else if (obj instanceof Object && // only "plain objects"
          Object.getPrototypeOf(obj) === Object.prototype) {
      /* This definition of "plain object" comes from jquery,
       * via zepto.js.  But this is really a big hack; we should
       * probably put a console.assert() here and more precisely
       * delimit what we think is legit to clone. (Hint: not
       * DOM trees.) */
      if (deepClone) {
        return Object.keys(obj).reduce(function(nobj, key) {
          nobj[key] = Util.clone(obj[key], true);
          return nobj;
        }, {});
      } else {
        return Object.assign({}, obj);
      }
    } else if (obj instanceof Token
        || obj instanceof KV) {
      // Allow cloning of Token and KV objects, since that is useful
      const nobj = new obj.constructor();
      for (const key in obj) {/* eslint-disable-line guard-for-in */
        nobj[key] = Util.clone(obj[key], true);
      }
      return nobj;
    } else {
      return obj;
    }
  },

  extractExtBody: function(token) {
    const src = token.getAttribute('source');
    const tagWidths = token.dataAttribs.tagWidths;
    return src.substring(tagWidths[0], src.length - tagWidths[1]);
  },

  /**
   * Decode HTML5 entities in wikitext.
   *
   * NOTE that wikitext only allows semicolon-terminated entities, while
   * HTML allows a number of "legacy" entities to be decoded without
   * a terminating semicolon.  This function deliberately does not
   * decode these HTML-only entity forms.
   *
   * @param {string} text
   * @return {string}
   */
  decodeWtEntities: function(text) {
    // HTML5 allows semicolon-less entities which wikitext does not:
    // in wikitext all entities must end in a semicolon.
    return text.replace(
        /&[#0-9a-zA-Z]+;/g,
        (match) => {
          // Be careful: `&ampamp;` can get through the above, which
          // decodeHTML5 will decode to `&amp;` -- but that's a sneaky
          // semicolon-less entity!
          const m = /^&#(?:x([A-Fa-f0-9]+)|(\d+));$/.exec(match);
          let c;
          let cp;
          if (m) {
            // entities contains a bunch of weird legacy mappings
            // for numeric codepoints (T113194) which we don't want.
            if (m[1]) {
              cp = Number.parseInt(m[1], 16);
            } else {
              cp = Number.parseInt(m[2], 10);
            }
            if (cp > 0x10FFFF) {
              // Invalid entity, don't give to String.fromCodePoint
              return match;
            }
            c = String.fromCodePoint(cp);
          } else {
            c = entities.decodeHTML5(match);
            // Length can be legit greater than one if it is astral
            if (c.length > 1 && c.endsWith(';')) {
              return match; // Invalid entity!
            }
            cp = c.codePointAt(0);
          }
          // Check other banned codepoints (T106578)
          if (
            (cp < 0x09) ||
            (cp > 0x0A && cp < 0x20) ||
            (cp > 0x7E && cp < 0xA0) ||
            (cp > 0xD7FF && cp < 0xE000) ||
            (cp > 0xFFFD && cp < 0x10000) ||
            (cp > 0x10FFFF)
          ) {
            // Invalid entity!
            return match;
          }
          return c;
        }
    );
  },

  getExtArgInfo: function(extToken) {
    const name = extToken.getAttribute('name');
    const options = extToken.getAttribute('options');
    return {
      dict: {
        name: name,
        attrs: TokenUtils.kvToHash(options, true),
        body: {extsrc: Util.extractExtBody(extToken)},
      },
    };
  },
};

if (typeof module === 'object') {
  module.exports.Util = Util;
}
