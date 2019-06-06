/* eslint-disable no-console, require-jsdoc */
'use strict';

const {Token, KV} = require('../Token.js');

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
    const extSrc = token.getAttribute('source');
    const extTagOffsets = token.dataAttribs.extTagOffsets;
    return extSrc.substring(
        extTagOffsets[1] - extTagOffsets[0],
        extTagOffsets[2] - extTagOffsets[0]);
  },

};

if (typeof module === 'object') {
  module.exports.Util = Util;
}
