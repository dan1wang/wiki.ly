/* eslint-disable no-console, require-jsdoc */
'use strict';

const entities = require('entities');
const TokenUtils = require('./TokenUtils.js').TokenUtils;
const Token = require('../tokens/Token.js').Token;
const KV = require('../tokens/KV.js').KV;

const Util = {
  // Determine if the named tag is void (can not have content).
  isVoidElement: function(name) {
    return [
      'AREA', 'BASE', 'BR', 'COL', 'COMMAND', 'EMBED', 'HR', 'IMG',
      'INPUT', 'KEYGEN', 'LINK', 'META', 'PARAM', 'SOURCE',
      'TRACK', 'WBR'].includes(name.toUpperCase());
  },

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
      for (const key in obj) {
        nobj[key] = Util.clone(obj[key], true);
      }
      return nobj;
    } else {
      return obj;
    }
  },

  // Just a copy `Util.clone` used in *testing* to reverse the effects of
  // freezing an object.  Works with more that just "plain objects"
  unFreeze: function(obj, deepClone) {
    if (deepClone === undefined) {
      deepClone = true;
    }
    if (Array.isArray(obj)) {
      if (deepClone) {
        return obj.map(function(el) {
          return Util.unFreeze(el, true);
        });
      } else {
        return obj.slice();
      }
    } else if (obj instanceof Object) {
      if (deepClone) {
        return Object.keys(obj).reduce(function(nobj, key) {
          nobj[key] = Util.unFreeze(obj[key], true);
          return nobj;
        }, new obj.constructor());
      } else {
        return Object.assign({}, obj);
      }
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
          const c = entities.decodeHTML5(match);
          // Length can be legit greater than one if it is astral
          // XXX there are other banned codepoints we should check;
          //     see T106578.
          if (c.length > 1 && c.endsWith(';')) {
            // Invalid entity!
            return match;
          }
          return c;
        }
    );
  },

  // Determine whether the protocol of a link is potentially valid. Use the
  // environment's per-wiki config to do so.
  isProtocolValid: function(linkTarget, env) {
    const wikiConf = env.conf.wiki;
    if (typeof linkTarget === 'string') {
      return wikiConf.hasValidProtocol(linkTarget);
    } else {
      return true;
    }
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
