/* eslint-disable no-console, require-jsdoc */
'use strict';

/**
 * Catch-all class for all token types.
 * @abstract
 * @class
 */
class Token {
  /**
   * Generic set attribute method.
   *
   * @param {string} name
   * @param {any} value
   */
  addAttribute(name, value) {
    this.attribs.push(new KV(name, value));
  }

  /**
   * Generic set attribute method with support for change detection.
   * Set a value and preserve the original wikitext that produced it.
   *
   * @param {string} name
   * @param {any} value
   * @param {any} origValue
   */
  addNormalizedAttribute(name, value, origValue) {
    this.addAttribute(name, value);
    this.setShadowInfo(name, value, origValue);
  }

  /**
   * Generic attribute accessor.
   *
   * @param {string} name
   * @return {any}
   */
  getAttribute(name) {
    return KV.lookup(this.attribs, name);
  }

  /**
   * Generic attribute accessor.
   *
   * @param {string} name
   * @return {boolean}
   */
  hasAttribute(name) {
    return KV.lookupKV(this.attribs, name) !== null;
  }

  /**
   * Set an unshadowed attribute.
   *
   * @param {string} name
   * @param {any} value
   */
  setAttribute(name, value) {
    // First look for the attribute and change the last match if found.
    for (let i = this.attribs.length - 1; i >= 0; i--) {
      const kv = this.attribs[i];
      const k = kv.k;
      if (k.constructor === String && k.toLowerCase() === name) {
        kv.v = value;
        this.attribs[i] = kv;
        return;
      }
    }
    // Nothing found, just add the attribute
    this.addAttribute(name, value);
  }

  /**
   * Store the original value of an attribute in a token's dataAttribs.
   *
   * @param {string} name
   * @param {any} value
   * @param {any} origValue
   */
  setShadowInfo(name, value, origValue) {
    // Don't shadow if value is the same or the orig is null
    if (value !== origValue && origValue !== null) {
      if (!this.dataAttribs.a) {
        this.dataAttribs.a = {};
      }
      this.dataAttribs.a[name] = value;
      if (!this.dataAttribs.sa) {
        this.dataAttribs.sa = {};
      }
      if (origValue !== undefined) {
        this.dataAttribs.sa[name] = origValue;
      }
    }
  }

  /**
   * Attribute info accessor for the wikitext serializer. Performs change
   * detection and uses unnormalized attribute values if set. Expects the
   * context to be set to a token.
   *
   * @param {string} name
   * @return {Object} Information about the shadow info attached to
   * this attribute.
   * @return {any} return.value
   * @return {boolean} return.modified Whether the attribute was changed
   * between parsing and now.
   * @return {boolean} return.fromsrc Whether we needed to get the source
   * of the attribute to round-trip it.
   */
  getAttributeShadowInfo(name) {
    const curVal = this.getAttribute(name);

    // Not the case, continue regular round-trip information.
    if (this.dataAttribs.a === undefined ||
        this.dataAttribs.a[name] === undefined) {
      return {
        value: curVal,
        // Mark as modified if a new element
        modified: Object.keys(this.dataAttribs).length === 0,
        fromsrc: false,
      };
    } else if (this.dataAttribs.a[name] !== curVal) {
      return {
        value: curVal,
        modified: true,
        fromsrc: false,
      };
    } else if (this.dataAttribs.sa === undefined ||
        this.dataAttribs.sa[name] === undefined) {
      return {
        value: curVal,
        modified: false,
        fromsrc: false,
      };
    } else {
      return {
        value: this.dataAttribs.sa[name],
        modified: false,
        fromsrc: true,
      };
    }
  }

  /**
   * Completely remove all attributes with this name.
   *
   * @param {string} name
   */
  removeAttribute(name) {
    const out = [];
    const attribs = this.attribs;
    for (let i = 0, l = attribs.length; i < l; i++) {
      const kv = attribs[i];
      if (kv.k.toLowerCase() !== name) {
        out.push(kv);
      }
    }
    this.attribs = out;
  }

  /**
   * Add a space-separated property value.
   *
   * @param {string} name
   * @param {any} value The value to add to the attribute.
   */
  addSpaceSeparatedAttribute(name, value) {
    const curVal = KV.lookupKV(this.attribs, name);
    let vals;
    if (curVal !== null) {
      vals = curVal.v.split(/\s+/);
      for (let i = 0, l = vals.length; i < l; i++) {
        if (vals[i] === value) {
          // value is already included, nothing to do.
          return;
        }
      }
      // Value was not yet included in the existing attribute, just add
      // it separated with a space
      this.setAttribute(curVal.k, curVal.v + ' ' + value);
    } else {
      // the attribute did not exist at all, just add it
      this.addAttribute(name, value);
    }
  }

  /**
   * Get the wikitext source of a token.
   *
   * @param {MWParserEnvironment} env
   * @return {string}
   */
  getWTSource(env) {
    const tsr = this.dataAttribs.tsr;
    console.assert(Array.isArray(tsr), 'Expected token to have tsr info.');
    return env.page.src.substring(tsr[0], tsr[1]);
  }
}

class CommentTk extends Token {
  /**
   * @param {string} value
   * @param {Object} dataAttribs data-parsoid object.
   */
  constructor(value, dataAttribs) {
    super();
    this.type = 'CommentTk';
    /** @type {string} */
    this.value = value;
    // won't survive in the DOM, but still useful for token serialization
    if (dataAttribs !== undefined) {
      /** @type {Object} */
      this.dataAttribs = dataAttribs;
    }
  }
}

/**
 * HTML tag token for a self-closing tag (like a br or hr).
 * @class
 * @extends ~Token
 */
class SelfclosingTagTk extends Token {
  /**
   * @param {string} name
   * @param {KV[]} attribs
   * @param {Object} dataAttribs
   */
  constructor(name, attribs, dataAttribs) {
    super();
    this.type = 'SelfclosingTagTk';
    /** @type {string} */
    this.name = name;
    /** @type {KV[]} */
    this.attribs = attribs || [];
    /** @type {Object} */
    this.dataAttribs = dataAttribs || {};
  }
}

/**
 * HTML tag token.
 * @class
 * @extends ~Token
 */
class TagTk extends Token {
  /**
   * @param {string} name
   * @param {KV[]} attribs
   * @param {Object} dataAttribs Data-parsoid object.
   */
  constructor(name, attribs, dataAttribs) {
    super();
    this.type = 'TagTk';
    /** @type {string} */
    this.name = name;
    /** @type {KV[]} */
    this.attribs = attribs || [];
    /** @type {Object} */
    this.dataAttribs = dataAttribs || {};
  }
}

/**
 * HTML end tag token.
 * @class
 * @extends ~Token
 */
class EndTagTk extends Token {
  /*
  * @param {string} name
  * @param {KV[]} attribs
  * @param {Object} dataAttribs
  */
  constructor(name, attribs, dataAttribs) {
    super();
    this.type = 'EndTagTk';
    /** @type {string} */
    this.name = name;
    /** @type {KV[]} */
    this.attribs = attribs || [];
    /** @type {Object} */
    this.dataAttribs = dataAttribs || {};
  }
}

class EOFTk extends Token {
  constructor() {
    super();
    this.type = 'EOFTk';
  }
}

class NlTk extends Token {
  /**
   * @param {Array} tsr The TSR of the newline(s).
   * @param {Object} dataAttribs
   */
  constructor(tsr, dataAttribs) {
    super();
    this.type = 'NlTk';
    if (dataAttribs) {
      /** @type {Object} */
      this.dataAttribs = dataAttribs;
    } else if (tsr) {
      /** @type {Object} */
      this.dataAttribs = {tsr: tsr};
    }
  }
}

/**
 * Key-value pair.
 * @class
 */
class KV {
  /**
   * @param {any} k key
   * @param {any} v value
   * @param {Array} srcOffsets The source offsets.
   * @param {string|null} ksrc
   * @param {string|null} vsrc
   */
  constructor(k, v, srcOffsets, ksrc = null, vsrc = null) {
    /** Key. */
    this.k = k;
    /** Value. */
    this.v = v;
    if (srcOffsets) {
      /** The source offsets. */
      this.srcOffsets = srcOffsets;
    }
    if (ksrc) {
      this.ksrc = ksrc;
    }
    if (vsrc) {
      this.vsrc = vsrc;
    }
  }

  /**
   * @return {string}
   */
  toJSON() {
    const ret = {k: this.k, v: this.v, srcOffsets: this.srcOffsets};
    if (this.ksrc) {
      ret.ksrc = this.ksrc;
    }
    if (this.vsrc) {
      ret.vsrc = this.vsrc;
    }
    return ret;
  }

  static lookupKV(kvs, key) {
    if (!kvs) {
      return null;
    }
    let kv;
    for (let i = 0, l = kvs.length; i < l; i++) {
      kv = kvs[i];
      if (kv.k.constructor === String && kv.k.trim() === key) {
        // found, return it.
        return kv;
      }
    }
    // nothing found!
    return null;
  }

  static lookup(kvs, key) {
    const kv = this.lookupKV(kvs, key);
    return kv === null ? null : kv.v;
  }
}

if (typeof module === 'object') {
  module.exports = {
    Token,
    CommentTk,
    EndTagTk,
    EOFTk,
    NlTk,
    TagTk,
    SelfclosingTagTk,
    KV,
  };
}
