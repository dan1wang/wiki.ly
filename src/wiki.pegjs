/**
 * Combined Wiki (MediaWiki) and HTML tokenizer based on pegjs. Emits several
 * chunks of tokens (one chunk per top-level block matched) and eventually an
 * end event. Tokens map to HTML tags as far as possible, with custom tokens
 * used where further processing on the token stream is needed.
 */
{

    var pegIncludes = options.pegIncludes;
    var pegTokenizer = options.pegTokenizer;

    var env = pegTokenizer.env;
    var pipelineOpts = pegTokenizer.options;

    var TokenUtils = pegIncludes.TokenUtils;
    var Util = pegIncludes.Util;
    var PegTokenizer = pegIncludes.PegTokenizer;
    var TokenTypes = pegIncludes.TokenTypes;
    var HTMLTags = pegIncludes.HTMLTags;
    var tu = pegIncludes.tu;
    var NAMED_ENTITIES = {
      "&apos;":"'",
      "&nbsp;":" ",
      "&iexcl;":"¡",
      "&cent;":"¢",
      "&pound;":"£",
      "&curren;":"¤",
      "&yen;":"¥",
      "&brvbar;":"¦",
      "&sect;":"§",
      "&uml;":"¨",
      "&copy;":"©",
      "&ordf;":"ª",
      "&laquo;":"«",
      "&not;":"¬",
      "&shy;":"\xad",
      "&reg;":"®",
      "&macr;":"¯",
      "&deg;":"°",
      "&plusmn;":"±",
      "&sup2;":"²",
      "&sup3;":"³",
      "&acute;":"´",
      "&micro;":"µ",
      "&para;":"¶",
      "&middot;":"·",
      "&cedil;":"¸",
      "&sup1;":"¹",
      "&ordm;":"º",
      "&raquo;":"»",
      "&frac14;":"¼",
      "&frac12;":"½",
      "&frac34;":"¾",
      "&iquest;":"¿",
      "&Agrave;":"À",
      "&Aacute;":"Á",
      "&Acirc;":"Â",
      "&Atilde;":"Ã",
      "&Auml;":"Ä",
      "&Aring;":"Å",
      "&Aelig;":"Æ",
      "&Ccedil;":"Ç",
      "&Egrave;":"È",
      "&Eacute;":"É",
      "&Ecirc;":"Ê",
      "&Euml;":"Ë",
      "&Igrave;":"Ì",
      "&Iacute;":"Í",
      "&Icirc;":"Î",
      "&Iuml;":"Ï",
      "&ETH;":"Ð",
      "&Ntilde;":"Ñ",
      "&Ograve;":"Ò",
      "&Oacute;":"Ó",
      "&Ocirc;":"Ô",
      "&Otilde;":"Õ",
      "&Ouml;":"Ö",
      "&times;":"×",
      "&Oslash;":"Ø",
      "&Ugrave;":"Ù",
      "&Uacute;":"Ú",
      "&Ucirc;":"Û",
      "&Uuml;":"Ü",
      "&Yacute;":"Ý",
      "&THORN;":"Þ",
      "&szlig;":"ß",
      "&agrave;":"à",
      "&aacute;":"á",
      "&acirc;":"â",
      "&atilde;":"ã",
      "&auml;":"ä",
      "&aring;":"å",
      "&aelig;":"æ",
      "&ccedil;":"ç",
      "&egrave;":"è",
      "&eacute;":"é",
      "&ecirc;":"ê",
      "&euml;":"ë",
      "&igrave;":"ì",
      "&iacute;":"í",
      "&icirc;":"î",
      "&iuml;":"ï",
      "&eth;":"ð",
      "&ntilde;":"ñ",
      "&ograve;":"ò",
      "&oacute;":"ó",
      "&ocirc;":"ô",
      "&otilde;":"õ",
      "&ouml;":"ö",
      "&divide;":"÷",
      "&oslash;":"ø",
      "&ugrave;":"ù",
      "&uacute;":"ú",
      "&ucirc;":"û",
      "&uuml;":"ü",
      "&yacute;":"ý",
      "&thorn;":"þ",
      "&yuml;":"ÿ",
      "&quot;":"\"",
      "&amp;":"&",
      "&lt;":"<",
      "&gt;":">",
      "&OElig;":"Œ",
      "&oelig;":"œ",
      "&Scaron;":"Š",
      "&scaron;":"š",
      "&Yuml;":"Ÿ",
      "&circ;":"ˆ",
      "&tilde;":"˜",
      "&ensp;":"\u2002",
      "&emsp;":"\u2003",
      "&thinsp;":"\u2009",
      "&zwnj;":"\u200C",
      "&zwj;":"\u200D",
      "&lrm;":"\u200E",
      "&rlm;":"\u200F",
      "&ndash;":"–",
      "&mdash;":"—",
      "&lsquo;":"‘",
      "&rsquo;":"’",
      "&sbquo;":"‚",
      "&ldquo;":"“",
      "&rdquo;":"”",
      "&bdquo;":"„",
      "&dagger;":"†",
      "&Dagger;":"‡",
      "&permil;":"‰",
      "&lsaquo;":"‹",
      "&rsaquo;":"›",
      "&euro;":"€",
      "&fnof;":"ƒ",
      "&Alpha;":"Α",
      "&Beta;":"Β",
      "&Gamma;":"Γ",
      "&Delta;":"Δ",
      "&Epsilon;":"Ε",
      "&Zeta;":"Ζ",
      "&Eta;":"Η",
      "&Theta;":"Θ",
      "&Iota;":"Ι",
      "&Kappa;":"Κ",
      "&Lambda;":"Λ",
      "&Mu;":"Μ",
      "&Nu;":"Ν",
      "&Xi;":"Ξ",
      "&Omicron;":"Ο",
      "&Pi;":"Π",
      "&Rho;":"Ρ",
      "&Sigma;":"Σ",
      "&Tau;":"Τ",
      "&Upsilon;":"Υ",
      "&Phi;":"Φ",
      "&Chi;":"Χ",
      "&Psi;":"Ψ",
      "&Omega;":"Ω",
      "&alpha;":"α",
      "&beta;":"β",
      "&gamma;":"γ",
      "&delta;":"δ",
      "&epsilon;":"ε",
      "&zeta;":"ζ",
      "&eta;":"η",
      "&theta;":"θ",
      "&iota;":"ι",
      "&kappa;":"κ",
      "&lambda;":"λ",
      "&mu;":"μ",
      "&nu;":"ν",
      "&xi;":"ξ",
      "&omicron;":"ο",
      "&pi;":"π",
      "&rho;":"ρ",
      "&sigmaf;":"ς",
      "&sigma;":"σ",
      "&tau;":"τ",
      "&upsilon;":"υ",
      "&phi;":"φ",
      "&chi;":"χ",
      "&psi;":"ψ",
      "&omega;":"ω",
      "&thetasym;":"ϑ",
      "&upsih;":"ϒ",
      "&piv;":"ϖ",
      "&bull;":"•",
      "&hellip;":"…",
      "&prime;":"′",
      "&Prime;":"″",
      "&oline;":"‾",
      "&frasl;":"⁄",
      "&weierp;":"℘",
      "&image;":"ℑ",
      "&real;":"ℜ",
      "&trade;":"™",
      "&alefsym;":"ℵ",
      "&larr;":"←",
      "&uarr;":"↑",
      "&rarr;":"→",
      "&darr;":"↓",
      "&harr;":"↔",
      "&crarr;":"↵",
      "&lArr;":"⇐",
      "&uArr;":"⇑",
      "&rArr;":"⇒",
      "&dArr;":"⇓",
      "&hArr;":"⇔",
      "&forall;":"∀",
      "&part;":"∂",
      "&exist;":"∃",
      "&empty;":"∅",
      "&nabla;":"∇",
      "&isin;":"∈",
      "&notin;":"∉",
      "&ni;":"∋",
      "&prod;":"∏",
      "&sum;":"∑",
      "&minus;":"−",
      "&lowast;":"∗",
      "&radic;":"√",
      "&prop;":"∝",
      "&infin;":"∞",
      "&ang;":"∠",
      "&and;":"∧",
      "&or;":"∨",
      "&cap;":"∩",
      "&cup;":"∪",
      "&int;":"∫",
      "&there4;":"∴",
      "&sim;":"∼",
      "&cong;":"≅",
      "&asymp;":"≈",
      "&ne;":"≠",
      "&equiv;":"≡",
      "&le;":"≤",
      "&ge;":"≥",
      "&sub;":"⊂",
      "&sup;":"⊃",
      "&nsub;":"⊄",
      "&sube;":"⊆",
      "&supe;":"⊇",
      "&oplus;":"⊕",
      "&otimes;":"⊗",
      "&perp;":"⊥",
      "&sdot;":"⋅",
      "&lceil;":"⌈",
      "&rceil;":"⌉",
      "&lfloor;":"⌊",
      "&rfloor;":"⌋",
      "&lang;":"\u2329",
      "&rang;":"\u232a",
      "&loz;":"◊",
      "&spades;":"♠",
      "&clubs;":"♣",
      "&hearts;":"♥",
      "&diams;":"♦"
    };

    function decodeEntity(encoded) {
      let cp;
      let decoded;
      let hex = /^&#(?:x([A-Fa-f0-9]+)|(\d+));$/.exec(encoded);
      if (hex) {
        if (hex[1]) { // &#xAE
          cp = Number.parseInt(hex[1], 16);
        } else { // &#174
          cp = Number.parseInt(hex[2], 10);
        }
        if (cp > 0x10FFFF) {
          return encoded; // Invalid entity
        }
        if (
          (cp < 0x09) ||
          (cp > 0x0A && cp < 0x20) ||
          (cp > 0x7E && cp < 0xA0) ||
          (cp > 0xD7FF && cp < 0xE000) ||
          (cp > 0xFFFD && cp < 0x10000) ||
          (cp > 0x10FFFF)
        ) {
          return encoded; // Invalid entity
        }
        return String.fromCodePoint(cp);
      } else {
        if (NAMED_ENTITIES.hasOwnProperty(encoded)) {
          return NAMED_ENTITIES[encoded]
        } else {
          return encoded;
        }
      }
    }
    function decodeEntities(text) {
      return text.replace(/&[#0-9a-zA-Z]+;/g, decodeEntity);
    }

    // define some constructor shortcuts
    const { KV, TagTk, EndTagTk, SelfclosingTagTk, NlTk, EOFTk, CommentTk } = TokenTypes;
    var lastItem = function(items) {
      return items[items.length - 1];
    };

    var inlineBreaks = tu.inlineBreaks;

    var prevOffset = 0;
    var headingIndex = 0;

    // Assertions are not safe in the tokenizer, since we catch exceptions
    // thrown and treat it as a "failed match" and backtrack.  Nobody ever
    // sees the assertion failure.  Work around this by using a special
    // assertion method for tokenizer code.
    var assert = function(condition, text) {
      if (condition) { return; }
      env.log('fatal', text || "Tokenizer assertion failure");
    };

    // Some shorthands for legibility
    var startOffset = function() {
      return peg$savedPos;
    };
    var endOffset = function() {
      return peg$currPos;
    };
    var tsrOffsets = function(flag) {
      return tu.tsrOffsets(peg$savedPos, peg$currPos, flag);
    };

    /*
     * Emit a chunk of tokens to our consumers.  Once this has been done, the
     * current expression can return an empty list (true).
     */
    var emitChunk = function(tokens) {
        if (env.immutable) {
            tokens = Util.clone(tokens, true);
        }

        // Shift tsr of all tokens by the pipeline offset
        TokenUtils.shiftTokenTSR(tokens, options.pipelineOffset);
        env.log("trace/peg", pegTokenizer.pipelineId, "---->  ", tokens);

        var i;
        var n = tokens.length;

        // limit the size of individual chunks
        var chunkLimit = 100000;
        if (n > chunkLimit) {
            i = 0;
            while (i < n) {
                options.cb(tokens.slice(i, i + chunkLimit));
                i += chunkLimit;
            }
        } else {
            options.cb(tokens);
        }
    };

    /* ------------------------------------------------------------------------
     * Extension tags should be parsed with higher priority than anything else.
     *
     * The trick we use is to strip out the content inside a matching tag-pair
     * and not tokenize it. The content, if it needs to parsed (for example,
     * for <ref>, <*include*> tags), is parsed in a fresh tokenizer context
     * which means any error correction that needs to happen is restricted to
     * the scope of the extension content and doesn't spill over to the higher
     * level.  Ex: <math><!--foo</math>.
     *
     * IGNORE: {{ this just balances the blocks in this comment for pegjs
     *
     * This trick also lets us prevent extension content (that don't accept WT)
     * from being parsed as wikitext (Ex: <math>\frac{foo\frac{bar}}</math>)
     * We don't want the "}}" being treated as a template closing tag and
     * closing outer templates.
     * --------------------------------------------------------------------- */

    var isXMLTag = function(name, block) {
        var uName = name.toUpperCase();
        return block
            ? (name !== 'VIDEO' && HTMLTags.HTML4Block.includes(name))
            : HTMLTags.HTML5.includes(uName) || HTMLTags.DepHTML.includes(uName);
    };

    var isExtTag = function(name) {
        var lName = name.toLowerCase();
        var isInstalledExt = env.conf.wiki.extTags.includes(lName);
        var isIncludeTag = tu.isIncludeTag(lName);
        return isInstalledExt || isIncludeTag;
    };

    var maybeExtensionTag = function(t) {
        var tagName = t.name.toLowerCase();
        var isInstalledExt = env.conf.wiki.extTags.includes(tagName);
        var isIncludeTag = tu.isIncludeTag(tagName);

        // Extensions have higher precedence when they shadow html tags.
        if (!(isInstalledExt || isIncludeTag)) {
            return t;
        }

        var dp = t.dataAttribs;
        var skipLen = 0;

        switch (t.constructor) {
        case EndTagTk:
            if (isIncludeTag) {
                return t;
            }
            // Similar to TagTk, we rely on the sanitizer to convert to text
            // where necessary and emit tokens to ease the wikitext escaping
            // code.  However, extension tags that shadow html tags will see
            // their unmatched end tags dropped while tree building, since
            // the sanitizer will let them through.
            return t;  // not text()
        case SelfclosingTagTk:
            dp.src = input.substring(dp.tsr[0], dp.tsr[1]);
            dp.extTagWidths = [dp.tsr[1] - dp.tsr[0], 0];
            if (isIncludeTag) {
                return t;
            }
            break;
        case TagTk:
            var tsr0 = dp.tsr[0];
            var endTagRE = new RegExp("^[\\s\\S]*?(</" + tagName + "\\s*>)", "i");
            var restOfInput = input.substring(tsr0);
            var tagContent = restOfInput.match(endTagRE);

            if (!tagContent) {
                dp.src = input.substring(dp.tsr[0], dp.tsr[1]);
                dp.extTagWidths = [dp.tsr[1] - dp.tsr[0], 0];
                if (isIncludeTag) {
                    return t;
                } else {
                    // This is undefined behaviour.  The php parser currently
                    // returns text here (see core commit 674e8388cba),
                    // whereas this results in unclosed
                    // extension tags that shadow html tags falling back to
                    // their html equivalent.  The sanitizer will take care
                    // of converting to text where necessary.  We do this to
                    // simplify `hasWikitextTokens` when escaping wikitext,
                    // which wants these as tokens because it's otherwise
                    // lacking in context.
                    return t;  // not text()
                }
            }

            var extSrc = tagContent[0];
            var endTagWidth = tagContent[1].length;

            if (pipelineOpts.inTemplate) {
                // Support 1-level of nesting in extensions tags while
                // tokenizing in templates to support the #tag parser function.
                //
                // It's necessary to permit this broadly in templates because
                // there's no way to distinguish whether the nesting happened
                // while expanding the #tag parser function, or just a general
                // syntax errors.  In other words,
                //
                //   hi<ref>ho<ref>hi</ref>ho</ref>
                //
                // and
                //
                //   hi{{#tag:ref|ho<ref>hi</ref>ho}}
                //
                // found in template are returned indistinguishably after a
                // preprocessing request, though the php parser renders them
                // differently.  #tag in template is probably a common enough
                // use case that we want to accept these false positives,
                // though another approach could be to drop this code here, and
                // invoke a native #tag handler and forgo those in templates.
                //
                // Expand `extSrc` as long as there is a <tagName> found in the
                // extension source body.
                var s = extSrc.substring(endOffset() - tsr0);
                while (s && s.match(new RegExp("<" + tagName + "[^/<>]*>", "i"))) {
                    tagContent = restOfInput.substring(extSrc.length).match(endTagRE);
                    if (tagContent) {
                        s = tagContent[0];
                        endTagWidth = tagContent[1].length;
                        extSrc += s;
                    } else {
                        s = null;
                    }
                }
            }

            // Extension content source
            dp.src = extSrc;
            dp.extTagWidths = [endOffset() - tsr0, endTagWidth];

            skipLen = extSrc.length - dp.extTagWidths[0] - dp.extTagWidths[1];

            // If the xml-tag is a known installed (not native) extension,
            // skip the end-tag as well.
            if (isInstalledExt) {
                skipLen += endTagWidth;
            }
            break;
        default:
            assert(false, 'Should not be reachable.');
        }

        peg$currPos += skipLen;

        if (isInstalledExt) {
            // update tsr[1] to span the start and end tags.
            dp.tsr[1] = endOffset();  // was just modified above
            return new SelfclosingTagTk('extension', [
                new KV('typeof', 'mw:Extension'),
                new KV('name', tagName),
                new KV('source', dp.src),
                new KV('options', t.attribs),
            ], dp);
        } else if (isIncludeTag) {
            // Parse ext-content, strip eof, and shift tsr
            var extContent = dp.src.substring(dp.extTagWidths[0], dp.src.length - dp.extTagWidths[1]);
            var extContentToks = (new PegTokenizer(env)).tokenizeSync(extContent);
            if (dp.extTagWidths[1] > 0) {
                extContentToks = TokenUtils.stripEOFTkfromTokens(extContentToks);
            }
            TokenUtils.shiftTokenTSR(extContentToks, dp.tsr[0] + dp.extTagWidths[0]);
            return [t].concat(extContentToks);
        } else {
            assert(false, 'Should not be reachable.');
        }
    };
}

/*********************************************************
 * The top-level rule
 *********************************************************/

start "start"
  = tlb* newlineToken* {
      // end is passed inline as a token, as well as a separate event for now.
      emitChunk([ new EOFTk() ]);
      return true;
  }

/*
 * Redirects can only occur as the first thing in a document.  See
 * WikitextContent::getRedirectTarget()
 */
redirect
  = rw:redirect_word
    sp:$space_or_newline*
    c:$(":" space_or_newline*)?
    wl:wikilink & {
      return wl.length === 1 && wl[0] && wl[0].constructor !== String;
  } {
    var link = wl[0];
    if (sp) { rw += sp; }
    if (c) { rw += c; }
    // Build a redirect token
    var redirect = new SelfclosingTagTk('mw:redirect',
            // Put 'href' into attributes so it gets template-expanded
            [KV.lookupKV(link.attribs, 'href')],
            {
                src: rw,
                tsr: tsrOffsets(),
                linkTk: link,
            });
    return redirect;
}

// These rules are exposed as start rules.
generic_newline_attributes "generic_newline_attributes" = generic_newline_attribute*
table_attributes "table_attributes"
  = (table_attribute / optionalSpaceToken b:broken_table_attribute_name_char { return b; })*

/* The 'redirect' magic word.
 * The leading whitespace allowed is due to the PHP trim() function.
 */
redirect_word
  = $([ \t\n\r\0\x0b]* ("%REDIRECTS%"))

/*
 * This rule exists to support tokenizing the document in chunks.
 * The parser's streaming interface will stop tokenization after each iteration
 * of the starred subexpression, and yield to the node.js event-loop to
 * schedule other pending event handlers.
 */
start_async
  = (tlb
    / newlineToken* &{
      if (endOffset() === input.length) {
          emitChunk([ new EOFTk() ]);
      }
      // terminate the loop
      return false;
    }
    )*

/*
 * A document (start rule) is a sequence of toplevelblocks. Tokens are
 * emitted in chunks per toplevelblock to avoid buffering the full document.
 */
tlb "tlb"
  = !eof b:block {
    // Clear the tokenizer's backtracking cache after matching each
    // toplevelblock. There won't be any backtracking as a document is just a
    // sequence of toplevelblocks, so the cache for previous toplevelblocks
    // will never be needed.
    var end = startOffset();
    for (; prevOffset < end; prevOffset++) {
        peg$cache[prevOffset] = undefined;
    }

    var tokens;
    if (Array.isArray(b) && b.length) {
        tokens = tu.flattenIfArray(b);
    } else if (b && b.constructor === String) {
        tokens = [b];
    }

    // Emit tokens for this toplevelblock. This feeds a chunk to the parser pipeline.
    if (tokens) {
        emitChunk(tokens);
    }

    // We don't return any tokens to the start rule to save memory. We
    // just emitted them already to our consumers.
    return true;
  }

/*
 * The actual contents of each block.
 */
block
      // has to be first alternative; otherwise gets parsed as a <ol>
    = &sof r:redirect cil:comment_or_includes bl:block_line? { return [r].concat(cil, bl || []); }
    / block_lines
    / & '<' rs:( c:comment &eolf { return c; }
            // avoid a paragraph if we know that the line starts with a block tag
            / bt:block_tag
            ) { return rs; }
    / paragraph
    // Inlineline includes generic tags; wrapped into paragraphs in token
    // transform and DOM postprocessor
    / inlineline
    / s:sol !inline_breaks { return s; }

/*
 * A block nested in other constructs. Avoid eating end delimiters for other
 * constructs by checking against inline_breaks first.
 */
nested_block = !inline_breaks b:block { return b; }

/*
 * The same, but suitable for use inside a table construct.
 * Doesn't match table_heading_tag, table_row_tag, table_data_tag,
 * table_caption tag, or table_end_tag, although it does allow
 * table_start_tag (for nested tables).
 */
nested_block_in_table
  =
    // XXX: don't rely on a lame look-ahead like this; use syntax stops
    // instead, so that multi-line th content followed by a line prefixed with
    // a comment is also handled. Alternatively, implement a sol look-behind
    // assertion accepting spaces and comments.
    !(sol (space* sol)? space* (pipe / "!"))

    // avoid recursion via nested_block_in_table, as that can lead to stack
    // overflow in large tables
    // See https://phabricator.wikimedia.org/T59670
    b:nested_block<tableDataBlock> {
        return b;
    }

/*
 * Line-based block constructs.
 */
block_lines
  = s:sol
    // eat an empty line before the block
    s2:(os:optionalSpaceToken so:sol { return os.concat(so); })?
    bl:block_line {
        return s.concat(s2 || [], bl);
    }

// Horizontal rules
hr =
  "----" d:$"-"*
  // Check if a newline or content follows
  lineContent:( &sol "" { return undefined; } / "" { return true; } ) {
    var dataAttribs = {
      tsr: tsrOffsets(),
      lineContent: lineContent,
    };
    if (d.length > 0) {
      dataAttribs.extra_dashes = d.length;
    }
    return new SelfclosingTagTk('hr', [], dataAttribs);
  }

/*
 * Block structures with start-of-line wiki syntax
 */
block_line
  = heading
  / list_item
  / hr
  / st:optionalSpaceToken
    r:( & [ <{}|!] tl:table_line { return tl; }
      // tag-only lines should not trigger pre either
      / bts:(bt:block_tag stl:optionalSpaceToken { return bt.concat(stl); })+
        &eolf { return bts; }
      ) {
          return st.concat(r);
      }

/*
 * A paragraph. We don't emit 'p' tokens to avoid issues with template
 * transclusions, <p> tags in the source and the like. Instead, we perform
 * some paragraph wrapping on the token stream and the DOM.
 */
paragraph
  = s1:sol s2:sol c:inlineline {
      return s1.concat(s2, c);
  }

br
  = s:optionalSpaceToken &newline {
    return s.concat([
      new SelfclosingTagTk('br', [], { tsr: tsrOffsets() }),
    ]);
  }

inline_breaks
  = & [=|!{}:;\r\n[\]\-]
    (
        extTag: <extTag>
        h: <h>
        extlink: <extlink>
        templatedepth: <templatedepth>
        preproc: <preproc>
        equal: <equal>
        table: <table>
        templateArg: <templateArg>
        tableCellArg: <tableCellArg>
        semicolon: <semicolon>
        arrow: <arrow>
        linkdesc: <linkdesc>
        colon: <colon>
        th: <th>
        & {
            return inlineBreaks(input, endOffset(), {
                extTag: extTag,
                h: h,
                extlink: extlink,
                templatedepth: templatedepth,
                preproc: preproc,
                equal: equal,
                table: table,
                templateArg: templateArg,
                tableCellArg: tableCellArg,
                semicolon: semicolon,
                arrow: arrow,
                linkdesc: linkdesc,
                colon: colon,
                th: th
            });
        }
    )

inlineline
  = c:(urltext
          / !inline_breaks
            r:(inline_element / [^\r\n]) { return r; })+ {
      return tu.flattenStringlist(c);
  }

inline_element
  =   & '<' r:( xmlish_tag / comment ) { return r; }
    / & '{' r:tplarg_or_template { return r; }
    / & "-{" r:lang_variant_or_tpl { return r; }
    // FIXME: The php parser's replaceInternalLinks2 splits on [[, resulting
    // in sequences with odd number of brackets parsing as text, and sequences
    // with even number of brackets having its innermost pair parse as a
    // wikilink.  For now, we faithfully reproduce what's found there but
    // wikitext, the language, shouldn't be defined by odd tokenizing behaviour
    // in the php parser.  Flagging this for a future cleanup.
    / $('[[' &'[')+
    / & '[' r:( wikilink / extlink ) { return r; }
    / & "'" r:quote { return r; }

/* Headings  */

heading = & "=" // guard, to make sure '='+ will match.
          // XXX: Also check to end to avoid inline parsing?
    r:(
     s:$'='+ // moved in here to make s accessible to inner action
     ce:(
       (ill:inlineline<h>? { return ill || []; })
       $'='+
     )?
     & { return ce || s.length > 2; }
     endTPos:("" { return endOffset(); })
     spc:(spaces / comment)*
     &eolf
     {
        var c;
        var e;
        var level;
        if (ce) {
            c = ce[0];
            e = ce[1];
            level = Math.min(s.length, e.length);
        } else {
            // split up equal signs into two equal parts, with at least
            // one character in the middle.
            level = Math.floor((s.length - 1) / 2);
            c = ['='.repeat(s.length - 2 * level)];
            s = e = '='.repeat(level);
        }
        level = Math.min(6, level);
        // convert surplus equals into text
        if (s.length > level) {
            // Avoid modifying a cached result
            c = Util.clone(c, false);
            var extras1 = s.substr(0, s.length - level);
            if (c[0].constructor === String) {
                c[0] = extras1 + c[0];
            } else {
                c.unshift(extras1);
            }
        }
        if (e.length > level) {
            // Avoid modifying a cached result
            c = Util.clone(c, false);
            var extras2 = e.substr(0, e.length - level);
            var lastElem = lastItem(c);
            if (lastElem.constructor === String) {
                c[c.length - 1] += extras2;
            } else {
                c.push(extras2);
            }
        }

        var tsr = tsrOffsets('start');
        tsr[1] += level;
        // Match PHP behavior by (a) making headingIndex part of tokenizer
        // state(don't reuse pipeline!) and (b) assigning the index when
        // ==*== is tokenized, even if we're inside a template argument
        // or other context which won't end up putting the heading
        // on the output page.  T213468/T214538
        headingIndex++;
        return [
          new TagTk('h' + level, [], { tsr: tsr, tmp: { headingIndex } }),
        ].concat(c, [
          new EndTagTk('h' + level, [], { tsr: [endTPos - level, endTPos] }),
          spc,
        ]);
      }
    ) { return r; }


/* Comments */

// The php parser does a straight str.replace(/<!--((?!-->).)*-->/g, "")
// but, as always, things around here are a little more complicated.
//
// We accept the same comments, but because we emit them as HTML comments
// instead of deleting them, we have to encode the data to ensure that
// we always emit a valid HTML5 comment.  See the encodeComment helper
// for further details.

comment
    = '<!--' c:$(!"-->" .)* ('-->' / eof) {
        return [new CommentTk(c, { tsr: tsrOffsets() })];
    }


// Behavior switches. See:
// https://www.mediawiki.org/wiki/Help:Magic_words#Behavior_switches
behavior_switch
  = bs:$('__' behavior_text '__') {
    if (env.conf.wiki.isMagicWord(bs)) {
      return [
        new SelfclosingTagTk('behavior-switch', [ new KV('word', bs) ],
          { tsr: tsrOffsets(), src: bs, magicSrc: bs }
        ),
      ];
    } else {
      return [ bs ];
    }
  }

// Instead of defining a charset, php's doDoubleUnderscore concats a regexp of
// all the language specific aliases of the behavior switches and then does a
// match and replace. Just be as permissive as possible and let the
// BehaviorSwitchPreprocessor back out of any overreach.
behavior_text = $( !'__' [^'"<~[{\n\r:;\]}|!=] )+
