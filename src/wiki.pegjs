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
    var encodeComment = pegIncludes.encodeComment;
    var PegTokenizer = pegIncludes.PegTokenizer;
    var TokenTypes = pegIncludes.TokenTypes;
    var HTMLTags = pegIncludes.HTMLTags;
    var tu = pegIncludes.tu;

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
            dp.tagWidths = [dp.tsr[1] - dp.tsr[0], 0];
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
                dp.tagWidths = [dp.tsr[1] - dp.tsr[0], 0];
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
            dp.tagWidths = [endOffset() - tsr0, endTagWidth];

            skipLen = extSrc.length - dp.tagWidths[0] - dp.tagWidths[1];

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
            var extContent = dp.src.substring(dp.tagWidths[0], dp.src.length - dp.tagWidths[1]);
            var extContentToks = (new PegTokenizer(env)).tokenizeSync(extContent);
            if (dp.tagWidths[1] > 0) {
                extContentToks = TokenUtils.stripEOFTkfromTokens(extContentToks);
            }
            TokenUtils.shiftTokenTSR(extContentToks, dp.tsr[0] + dp.tagWidths[0]);
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
  = $([ \t\n\r\0\x0b]*
    rw:$(!space_or_newline ![:\[] .)+
    & { return env.conf.wiki.getMagicWordMatcher('redirect').test(rw); })

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
        var data = encodeComment(c);
        return [new CommentTk(data, { tsr: tsrOffsets() })];
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


/**************************************************************
 * External (bracketed and autolinked) links
 **************************************************************/

autolink
  = ! <extlink>
    // this must be a word boundary, so previous character must be non-word
    ! { return /\w/.test(input[endOffset() - 1] || ''); }
  r:(
      // urllink, inlined
      target:autourl {
        var res = [new SelfclosingTagTk('urllink', [new KV('href', target)], { tsr: tsrOffsets() })];
          return res;
      }
    / autoref
    / isbn) { return r; }

extlink "extlink"
  = ! <extlink> // extlink cannot be nested
  r:(
        "["
        addr:(url_protocol urladdr / "")
        target:(extlink_preprocessor_text<extlink> / "")
        & {
          // Protocol must be valid and there ought to be at least one
          // post-protocol character.  So strip last char off target
          // before testing protocol.
          var flat = tu.flattenString([addr, target]);
          if (Array.isArray(flat)) {
             // There are templates present, alas.
             return flat.length > 0;
          }
          return Util.isProtocolValid(flat.slice(0, -1), env);
        }
        sp:$( space / unispace )*
        targetOff:( "" { return endOffset(); })
        content:inlineline<extlink>?
        "]" {
            return [
                new SelfclosingTagTk('extlink', [
                    new KV('href', tu.flattenString([addr, target])),
                    new KV('mw:content', content || ''),
                    new KV('spaces', sp),
                ], {
                    targetOff: targetOff,
                    tsr: tsrOffsets(),
                    contentOffsets: [targetOff, endOffset() - 1],
                }),
            ];
        }
    ) { return r; }

autoref
  = ref:('RFC' / 'PMID') sp:space_or_nbsp+ identifier:$[0-9]+ end_of_word
{
    var base_urls = {
      'RFC': 'https://tools.ietf.org/html/rfc%s',
      'PMID': '//www.ncbi.nlm.nih.gov/pubmed/%s?dopt=Abstract',
    };
    return [
        new SelfclosingTagTk('extlink', [
           new KV('href', tu.sprintf(base_urls[ref], identifier)),
           new KV('mw:content', tu.flattenString([ref, sp, identifier])),
           new KV('typeof', 'mw:ExtLink/' + ref),
        ],
        { stx: "magiclink", tsr: tsrOffsets() }),
    ];
}

isbn
  = 'ISBN' sp:space_or_nbsp+ isbn:(
      [0-9]
      (s:space_or_nbsp_or_dash &[0-9] { return s; } / [0-9])+
      ((space_or_nbsp_or_dash / "") [xX] / "")
    ) isbncode:(
      end_of_word
      {
        // Convert isbn token-and-entity array to stripped string.
        return tu.flattenStringlist(isbn).filter(function(e) {
          return e.constructor === String;
        }).join('').replace(/[^\dX]/ig, '').toUpperCase();
      }
    ) &{
       // ISBNs can only be 10 or 13 digits long (with a specific format)
       return isbncode.length === 10 ||
             (isbncode.length === 13 && /^97[89]/.test(isbncode));
    } {
      return [
        new SelfclosingTagTk('extlink', [
           new KV('href', 'Special:BookSources/' + isbncode),
           new KV('mw:content', tu.flattenString(['ISBN', sp, isbn])),
           new KV('typeof', 'mw:WikiLink/ISBN'),
        ],
        { stx: "magiclink", tsr: tsrOffsets() }),
      ];
}


/* Default URL protocols in MediaWiki (see DefaultSettings). Normally
 * these can be configured dynamically. */

url_protocol =
    & { return Util.isProtocolValid(input.substr(endOffset()), env); }
    p:$( '//' / [A-Za-z] [-A-Za-z0-9+.]* ':' '//'? ) { return p; }

// no punctuation, and '{<' to trigger directives
no_punctuation_char = [^ :\]\[\r\n"'<>\x00-\x20\x7f,.&%\u00A0\u1680\u180E\u2000-\u200A\u202F\u205F\u3000{]

// this is the general url rule
// on the PHP side, the path part matches EXT_LINK_URL_CLASS
// which is '[^][<>"\\x00-\\x20\\x7F\p{Zs}]'
// the 's' and 'r' pieces below match the characters in
// EXT_LINK_URL_CLASS which aren't included in no_punctuation_char
url "url"
  = proto:url_protocol
    addr:(urladdr / "")
    path:(  ( !inline_breaks
              c:no_punctuation_char
              { return c; }
            )
            / s:[.:,']  { return s; }
            / comment
            / tplarg_or_template
            / ! ( "&" ( [lL][tT] / [gG][tT] ) ";" )
                r:(
                    & "&" he:htmlentity { return he; }
                  / [&%{]
                ) { return r; }
         )*
         // Must be at least one character after the protocol
         & { return addr.length > 0 || path.length > 0; }
{
    return tu.flattenString([proto, addr].concat(path));
}

// this is the somewhat-restricted rule used in autolinks
// See Parser::doMagicLinks and Parser.php::makeFreeExternalLink.
// The `path` portion matches EXT_LINK_URL_CLASS, as in the general
// url rule.  As in PHP, we do some fancy fixup to yank out
// trailing punctuation, perhaps including parentheses.
// The 's' and 'r' pieces match the characters in EXT_LINK_URL_CLASS
// which aren't included in no_punctuation_char
autourl
  = ! '//' // protocol-relative autolinks not allowed (T32269)
    r:(
    proto:url_protocol
    addr:(urladdr / "")
    path:(  ( !inline_breaks
              c:no_punctuation_char
              { return c; }
            )
            / [.:,]
            / $(['] ![']) // single quotes are ok, double quotes are bad
            / comment
            / tplarg_or_template
            / ! ( rhe:raw_htmlentity &{ return /^[<>\u00A0]$/.test(rhe); } )
                r:(
                    & "&" he:htmlentity { return he; }
                  / [&%{]
                ) { return r; }
         )*
{
    // as in Parser.php::makeFreeExternalLink, we're going to
    // yank trailing punctuation out of this match.
    var url = tu.flattenStringlist([proto, addr].concat(path));
    // only need to look at last element; HTML entities are strip-proof.
    var last = lastItem(url);
    var trim = 0;
    if (last && last.constructor === String) {
      var strip = ',;\\.:!?';
      if (path.indexOf("(") === -1) {
        strip += ')';
      }
      // Escape special regexp characters
      strip = strip.replace(/[\^\\$*+?.()|{}\[\]\/]/g, '\\$&');
      strip = new RegExp('[' + strip + ']*$');
      trim = strip.exec(last)[0].length;
      url[url.length - 1] = last.slice(0, last.length - trim);
    }
    url = tu.flattenStringlist(url);
    if (url.length === 1 && url[0].constructor === String && url[0].length <= proto.length) {
      return null; // ensure we haven't stripped everything: T106945
    }
    peg$currPos -= trim;
    return url;
} ) &{ return r !== null; } {return r; }

// This is extracted from EXT_LINK_ADDR in Parser.php: a simplified
// expression to match an IPv6 address.  The IPv4 address and "at least
// one character of a host name" portions are punted to the `path`
// component of the `autourl` and `url` productions
urladdr
  = $( "[" [0-9A-Fa-f:.]+ "]" )

/**************************************************************
 * Templates, -arguments and wikilinks
 **************************************************************/

/*
 * Precedence: template arguments win over templates. See
 * http://www.mediawiki.org/wiki/Preprocessor_ABNF#Ideal_precedence
 * 4: {{{{·}}}} → {·{{{·}}}·}
 * 5: {{{{{·}}}}} → {{·{{{·}}}·}}
 * 6: {{{{{{·}}}}}} → {{{·{{{·}}}·}}}
 * 7: {{{{{{{·}}}}}}} → {·{{{·{{{·}}}·}}}·}
 * This is only if close has > 3 braces; otherwise we just match open
 * and close as we find them.
 */
tplarg_or_template
  = &'{{'
    templatedepth:<templatedepth>
    &{
      // Refuse to recurse beyond `maxDepth` levels. Default in the PHP parser
      // is $wgMaxTemplateDepth = 40; This is to prevent crashing from
      // buggy wikitext with lots of unclosed template calls, as in
      // eswiki/Usuario:C%C3%A1rdenas/PRUEBAS?oldid=651094
      return templatedepth + 1 < env.conf.maxDepth;
    }
    t:tplarg_or_template_guarded<templatedepth++> { return t; }

tplarg_or_template_guarded
  = &('{{' &('{{{'+ !'{') tplarg) a:(template/broken_template) { return a; }
    / a:$('{' &('{{{'+ !'{'))? b:tplarg { return [a].concat(b); }
    / a:$('{' &('{{' !'{'))? b:template { return [a].concat(b); }
    / a:broken_template { return a; }

tplarg_or_template_or_bust "tplarg_or_template_or_bust"
    = r:(tplarg_or_template / .)+ { return tu.flattenIfArray(r); }

template
  = template_preproc<&preproc="}}">

// The PHP preprocessor maintains a single stack of "closing token we
// are currently looking for", with no backtracking.  This means that
// once you see `[[ {{` you are looking only for `}}` -- if that template
// turns out to be broken you will never pop the `}}` and there is no way
// to close the `[[`.  Since the PEG tokenizer in Parsoid uses backtracking
// and parses in a single pass (instead of PHP's split preprocessor/parser)
// we have to be a little more careful when we emulate this behavior.
// If we use a rule like:
//   template = "{{" tplname tplargs* "}}"?
// Then we end up having to reinterpret `tplname tplargs*` as a tlb if it
// turns out we never find the `}}`, which involves a lot of tedious gluing
// tokens back together with fingers crossed we haven't discarded any
// significant newlines/whitespace/etc.  An alternative would be a rule like:
//   broken_template = "{{" tlb
// but again, `template` is used in many different contexts; `tlb` isn't
// necessarily the right one to recursively invoke.  Instead we get the
// broken template off of the PEGjs production stack by returning immediately
// after `{{`, but we set the "preproc" reference parameter to false (the
// reference parameter feature having been introduced for this sole purpose)
// to indicate to the parent rule that we're "still in" the {{ context and
// shouldn't ever inlineBreak for any closing tokens above this one.  For
// example:
//   [[Foo{{Bar]]
// This will match as:
//   wikilink->text,template->text             --> FAILS looking for }}
//     backtracks, popping "bracket_bracket" and "brace_brace" off preproc stack
//   wikilink->text,broken_template,text       --> FAILS looking for ]]
//     backtracks, popping "bracket_bracket" and false off preproc stack
//   broken_wikilink,text,broken_template,text --> OK
//     with [false, false] left on the preproc stack

broken_template
  = preproc:<&preproc>
    t:"{{" {
        preproc.set(null);
        return t;
    }

template_preproc
  = "{{" nl_comment_space*
    target:template_param_value
    params:(nl_comment_space* "|"
                r:( p0:("" { return endOffset(); })
                    v:nl_comment_space*
                    p:("" { return endOffset(); })
                    &("|" / "}}")
                    { return new KV('', tu.flattenIfArray(v), [p0, p0, p0, p]); } // empty argument
                    / template_param
                  ) { return r; }
            )*
    nl_comment_space*
    inline_breaks "}}" {
      // Insert target as first positional attribute, so that it can be
      // generically expanded. The TemplateHandler then needs to shift it out
      // again.
      params.unshift(new KV(tu.flattenIfArray(target.tokens), '', target.srcOffsets));
      var obj = new SelfclosingTagTk('template', params, { tsr: tsrOffsets(), src: text() });
      return obj;
    } / $('{{' space_or_newline* '}}')

tplarg
  = tplarg_preproc<&preproc="}}">

tplarg_preproc
  = "{{{"
    p:("" { return endOffset(); })
    target:template_param_value?
    params:(nl_comment_space* "|"
                r:( p0:("" { return endOffset(); })
                    v:nl_comment_space*
                    p1:("" { return endOffset(); })
                    &("|" / "}}}")
                    { return { tokens: v, srcOffsets: [p0, p1] }; }  // empty argument
                    / template_param_value
                  ) { return r; }
            )*
    nl_comment_space*
    inline_breaks "}}}" {
      params = params.map(function(o) {
        var s = o.srcOffsets;
        return new KV('', tu.flattenIfArray(o.tokens), [s[0], s[0], s[0], s[1]]);
      });
      if (target === null) { target = { tokens: '', srcOffsets: [p, p, p, p] }; }
      // Insert target as first positional attribute, so that it can be
      // generically expanded. The TemplateHandler then needs to shift it out
      // again.
      params.unshift(new KV(tu.flattenIfArray(target.tokens), '', target.srcOffsets));
      var obj = new SelfclosingTagTk('templatearg', params, { tsr: tsrOffsets(), src: text() });
      return obj;
    }

template_param
  = name:template_param_name
    val:(
        kEndPos:("" { return endOffset(); })
        optionalSpaceToken
        "="
        vStartPos:("" { return endOffset(); })
        optionalSpaceToken
        tpv:template_param_value? {
            return { kEndPos: kEndPos, vStartPos: vStartPos, value: (tpv && tpv.tokens) || [] };
        }
    )? {
      if (val !== null) {
          if (val.value !== null) {
            return new KV(name, tu.flattenIfArray(val.value), [startOffset(), val.kEndPos, val.vStartPos, endOffset()]);
          } else {
            return new KV(tu.flattenIfArray(name), '', [startOffset(), val.kEndPos, val.vStartPos, endOffset()]);
          }
      } else {
        return new KV('', tu.flattenIfArray(name), [startOffset(), startOffset(), startOffset(), endOffset()]);
      }
    }
  // empty parameter
  / & [|}] {
    return new KV('', '', [startOffset(), startOffset(), startOffset(), endOffset()]);
  }

template_param_name
  = tpt:(template_param_text<equal> / &'=' { return ''; })
    {
        return tpt;
    }

template_param_value
  = tpt:template_param_text<equal=false>
    {
        return { tokens: tpt, srcOffsets: tsrOffsets() };
    }

template_param_text
  = il:(nested_block<table=false, extlink=false, templateArg=true, tableCellArg=false> / newlineToken)+ {
        // il is guaranteed to be an array -- so, tu.flattenIfArray will
        // always return an array
        var r = tu.flattenIfArray(il);
        if (r.length === 1 && r[0].constructor === String) {
            r = r[0];
        }
        return r;
    }

//// Language converter block markup of language variants: -{ ... }-

// Note that "rightmost opening" precedence rule (see
// https://www.mediawiki.org/wiki/Preprocessor_ABNF ) means
// that neither -{{ nor -{{{ are parsed as a -{ token, although
// -{{{{ is (since {{{ has precedence over {{).

lang_variant_or_tpl
  = &('-{' &('{{{'+ !'{') tplarg) a:lang_variant { return a; }
  / a:$('-' &('{{{'+ !'{')) b:tplarg { return [a].concat(b); }
  / a:$('-' &('{{' '{{{'* !'{')) b:template { return [a].concat(b); }
  / &'-{' a:lang_variant { return a; }

broken_lang_variant
  = r:"-{"
    preproc:<&preproc>
    {
        preproc.set(null);
        return r;
    }

lang_variant
  = lang_variant_preproc<&preproc="}-">
  / broken_lang_variant

lang_variant_preproc
  = lv0:("-{" { return startOffset(); })
    f:(
       &{ return env.langConverterEnabled(); }
       ff:opt_lang_variant_flags {
         // Avoid mutating cached expression results
         ff = Util.clone(ff, true);
         // if flags contains 'R', then don't treat ; or : specially inside.
         if (ff.flags) {
           ff.raw = ff.flags.has('R') || ff.flags.has('N');
         } else if (ff.variants) {
           ff.raw = true;
         }
         return ff;
       } /
       &{ return !env.langConverterEnabled(); }
       "" {
         // if language converter not enabled, don't try to parse inside.
         return { raw: true };
       }
    )
    ts:(
      &{ return f.raw; } lv:lang_variant_text { return [{ text: lv }]; }
      /
      &{ return !f.raw; } lv:lang_variant_option_list { return lv; }
    )
    inline_breaks
    lv1:("}-" { return endOffset(); }) {

      if (!env.langConverterEnabled()) {
        return [ "-{", ts[0].text.tokens, "}-" ];
      }
      var lvsrc = input.substring(lv0, lv1);
      var attribs = [];

      // Do a deep clone since we may be destructively modifying
      // (the `t[fld] = name;` below) the result of a cached expression
      ts = Util.clone(ts, true);

      ts.forEach(function(t) {
        // move token strings into KV attributes so that they are
        // properly expanded by early stages of the token pipeline
        ['text','from','to'].forEach(function(fld) {
          if (t[fld] === undefined) { return; }
          var name = 'mw:lv' + attribs.length;
          // Note that AttributeExpander will expect the tokens array to be
          // flattened.  We do that in lang_variant_text / lang_variant_nowiki
          attribs.push(new KV(name, t[fld].tokens, t[fld].srcOffsets));
          t[fld] = name;
        });
      });
      return [
        new SelfclosingTagTk(
          'language-variant',
           attribs,
           {
             tsr: [lv0, lv1],
             src: lvsrc,
             flags: f.flags && Array.from(f.flags).sort(),
             variants: f.variants && Array.from(f.variants).sort(),
             original: f.original,
             flagSp: f.sp,
             texts: ts,
           }),
      ];
    }

opt_lang_variant_flags
  = f:( ff:lang_variant_flags "|" { return ff; } )? {
    // Collect & separate flags and variants into a set and ordered list
    var flags = new Set();
    var variants = new Set();
    var flagList = [];
    var flagSpace = [];
    var variantList = [];
    var variantSpace = [];
    var useVariants = false;
    if (f !== null) {
      // lang_variant_flags returns arrays in reverse order.
      f.flags.reverse();
      f.sp.reverse();
      var spPtr = 0;
      f.flags.forEach(function(item) {
        if (item.flag) {
          flagSpace.push(f.sp[spPtr++]);
          flags.add(item.flag);
          flagList.push(item.flag);
          flagSpace.push(f.sp[spPtr++]);
        }
        if (item.variant) {
          variantSpace.push(f.sp[spPtr++]);
          variants.add(item.variant);
          variantList.push(item.variant);
          variantSpace.push(f.sp[spPtr++]);
        }
      });
      if (spPtr < f.sp.length) {
        // handle space after a trailing semicolon
        flagSpace.push(f.sp[spPtr]);
        variantSpace.push(f.sp[spPtr]);
      }
    }
    // Parse flags (this logic is from core/languages/ConverterRule.php
    // in the parseFlags() function)
    if (flags.size === 0 && variants.size === 0) {
      flags.add('$S');
    } else if (flags.has('R')) {
      flags = new Set(['R']); // remove other flags
    } else if (flags.has('N')) {
      flags = new Set(['N']); // remove other flags
    } else if (flags.has('-')) {
      flags = new Set(['-']); // remove other flags
    } else if (flags.has('T') && flags.size === 1) {
      flags.add('H');
    } else if (flags.has('H')) {
      // Replace A flag, and remove other flags except T and D
      var nf = new Set(['$+', 'H']);
      if (flags.has('T')) { nf.add('T'); }
      if (flags.has('D')) { nf.add('D'); }
      flags = nf;
    } else if (variants.size > 0) {
      useVariants = true;
    } else {
      if (flags.has('A')) {
        flags.add('$+');
        flags.add('$S');
      }
      if (flags.has('D')) {
        flags.delete('$S');
      }
    }
    if (useVariants) {
      return { variants: variants, original: variantList, sp: variantSpace };
    } else {
      return { flags: flags, original: flagList, sp: flagSpace };
    }
  }

lang_variant_flags
  = sp1:$(space_or_newline*) f:lang_variant_flag sp2:$(space_or_newline*)
    more:( ";" lang_variant_flags? )? {
    var r = more && more[1] ? more[1] : { sp: [], flags: [] };
    // Note that sp and flags are in reverse order, since we're using
    // right recursion and want to push instead of unshift.
    r.sp.push(sp2);
    r.sp.push(sp1);
    r.flags.push(f);
    return r;
  }
  / sp:$(space_or_newline*) {
    return { sp: [ sp ], flags: [] };
  }

lang_variant_flag
  = f:[-+A-Z]           { return { flag: f }; }
  / v:lang_variant_name { return { variant: v }; }
  / b:$(!space_or_newline !nowiki [^{}|;])+ { return { bogus: b }; /* bad flag */}

lang_variant_name // language variant name, like zh, zh-cn, etc.
  = $([a-z] [-a-z]+)
  // Escaped otherwise-unrepresentable language names
  // Primarily for supporting html2html round trips; PHP doesn't support
  // using nowikis here (yet!)
  / nowiki_text

lang_variant_option_list
  = o:lang_variant_option rest:( ";" oo:lang_variant_option { return oo; })*
    tr:( ";" $space_or_newline* )? // optional trailing semicolon
    {
      var r = [ o ].concat(rest);
      if (tr) { r.push({ semi: true, sp: tr[1] }); }
      return r;
    }
  / lvtext:lang_variant_text { return [{ text: lvtext }]; }

lang_variant_option
  = sp1:$(space_or_newline*) lang:lang_variant_name
    sp2:$(space_or_newline*) ":"
    sp3:$(space_or_newline*)
    lvtext:(lang_variant_nowiki / lang_variant_text_no_semi)
    {
      return {
        twoway: true,
        lang: lang,
        text: lvtext,
        sp: [sp1, sp2, sp3]
      };
    }
  / sp1:$(space_or_newline*)
    from:(lang_variant_nowiki / lang_variant_text_no_semi_or_arrow)
    "=>"
    sp2:$(space_or_newline*) lang:lang_variant_name
    sp3:$(space_or_newline*) ":"
    sp4:$(space_or_newline*)
    to:(lang_variant_nowiki / lang_variant_text_no_semi)
    {
      return {
        oneway: true,
        from: from,
        lang: lang,
        to: to,
        sp: [sp1, sp2, sp3, sp4]
      };
    }

// html2wt support: If a language name or conversion string can't be
// represented w/o breaking wikitext, just wrap it in a <nowiki>.
// PHP doesn't support this (yet), but Parsoid does.
lang_variant_nowiki
  = n:nowiki_text
    sp:$space_or_newline*
    {
        return { tokens: [ n ], srcOffsets: [startOffset(), endOffset() - sp.length] };
    }

lang_variant_text
  = tokens:(inlineline / "|" )*
    { return { tokens: tu.flattenStringlist(tokens), srcOffsets: [startOffset(), endOffset()] }; }

lang_variant_text_no_semi
  = lang_variant_text<semicolon>

lang_variant_text_no_semi_or_arrow
  = lang_variant_text_no_semi<arrow>

wikilink_content
  = ( pipe startPos:("" { return endOffset(); }) lt:link_text? {
        var maybeContent = new KV('mw:maybeContent', lt, [startPos, endOffset()]);
        maybeContent.vsrc = input.substring(startPos, endOffset());
        return maybeContent;
  } )*

wikilink
  = wikilink_preproc<&preproc="]]">
    / broken_wikilink

// `broken-link` (see [[:mw:Preprocessor_ABNF]]), but careful because the
// second bracket could start an extlink.  Set preproc to false as a reference
// parameter in the parent since we haven't seen a double-close bracket.
// (See full explanation above broken_template production.)
broken_wikilink
  = &"[["
    preproc:<&preproc>
    &{ preproc.set(null); return true; }
    a:("[" (extlink / "[")) {
        return a;
    }

wikilink_preproc
  = "[["
    target:wikilink_preprocessor_text?
    tpos:("" { return endOffset(); })
    lcs:wikilink_content
    inline_breaks "]]"
  {
      var pipeTrick = (lcs.length === 1 && lcs[0].v === null);
      var textTokens = [];
      if (target === null || pipeTrick) {
        textTokens.push("[[");
        if (target) {
          textTokens.push(target);
        }
        lcs.forEach(function(a) {
          // a is a mw:maybeContent attribute
          textTokens.push("|");
          if (a.v !== null) { textTokens.push(a.v); }
        });
        textTokens.push("]]");
        return textTokens;
      }
      var obj = new SelfclosingTagTk('wikilink');
      var hrefKV = new KV('href', target);
      hrefKV.vsrc = input.substring(startOffset() + 2, tpos);
      // XXX: Point to object with path, revision and input information
      // obj.source = input;
      obj.attribs.push(hrefKV);
      obj.attribs = obj.attribs.concat(lcs);
      obj.dataAttribs = {
          tsr: tsrOffsets(),
          src: text(),
      };
      return [obj];
  }

// Tables are allowed inside image captions.
// Suppress the equal flag temporarily in this rule to consume the '=' here.
link_text = link_text_parameterized<equal = false, linkdesc = true>

link_text_parameterized
  = c:(  // This group is similar to "block_line" but "list_item"
         // is omitted since `doBlockLevels` happens after
         // `replaceInternalLinks2`, where newlines are stripped.
         (sol (heading / hr / full_table_in_link_caption))
       / urltext
       / (!inline_breaks
          r:( inline_element / '[' text_char+ ']' $(&(!']' / ']]')) / . ) { return r; }
         )
    )+ {
      return tu.flattenStringlist(c);
    }

/* Generic quote rule for italic and bold, further processed in a token
 * stream transformation in doQuotes. Relies on NlTk tokens being emitted
 * for each line of text to balance quotes per line.
 *
 * We are not using a simple pair rule here as we need to support mis-nested
 * bolds/italics and MediaWiki's special heuristics for apostrophes, which are
 * all not context free. */
quote = quotes:$("''" "'"*) {
    // sequences of four or more than five quotes are assumed to start
    // with some number of plain-text apostrophes.
    var plainticks = 0;
    var result = [];
    if (quotes.length === 4) {
        plainticks = 1;
    } else if (quotes.length > 5) {
        plainticks = quotes.length - 5;
    }
    if (plainticks > 0) {
        result.push(quotes.substring(0, plainticks));
    }
    // mw-quote token Will be consumed in token transforms
    var tsr = tsrOffsets();
    tsr[0] += plainticks;
    var mwq = new SelfclosingTagTk('mw-quote', [new KV('value', quotes.substring(plainticks))], { tsr: tsr });
    if (quotes.length > 2) {
        mwq.addAttribute('preceding-2chars', input.substring(tsr[0] - 2, tsr[0]));
    }
    result.push(mwq);
    return result;
}


/***********************************************************
 * Pre and xmlish tags
 ***********************************************************/

extension_tag =
  !<extTag>
  extToken:xmlish_tag
  // Account for `maybeExtensionTag` returning unmatched start / end tags
  &{ return extToken[0].name === 'extension'; }
  { return extToken[0]; }

nowiki
  = extToken:extension_tag
    &{ return extToken.getAttribute('name') === 'nowiki'; }
    { return extToken; }

// Used by lang_variant productions to protect special language names or
// conversion strings.
nowiki_text
  = extToken:nowiki
  {
    var txt = Util.getExtArgInfo(extToken).dict.body.extsrc;
    return Util.decodeWtEntities(txt);
  }

/* Generic XML-like tags
 *
 * These also cover extensions (including Cite), which will hook into the
 * token stream for further processing. The content of extension tags is
 * parsed as regular inline, but the source positions of the tag are added
 * to allow reconstructing the unparsed text from the input. */

// See http://www.w3.org/TR/html5/syntax.html#tag-open-state and
// following paragraphs.
tag_name_chars = [^\t\n\v />\0]
tag_name = $([A-Za-z] tag_name_chars*)

// This rule is used in carefully crafted places of xmlish tag tokenizing with
// the inclusion of solidus to match where the spec would ignore those
// characters.  In particular, it does not belong in between attribute name
// and value.
space_or_newline_or_solidus = space_or_newline / (s:"/" !">" { return s; })

xmlish_tag
  = "<" tag:(xmlish_tag_opened<isBlock=false, extTag> / xmlish_tag_opened<isBlock=false, extTag=false>)
    { return tag; }

xmlish_tag_opened
  = end:"/"?
    name: tag_name
    extTag: <extTag>
    isBlock: <isBlock>
    & {
        if (extTag) {
            return isExtTag(name);
        } else {
            return isXMLTag(name, isBlock);
        }
    }
    // By the time we get to `doTableStuff` in the php parser, we've already
    // safely encoded element attributes. See 55313f4e in core.
    attribs:generic_newline_attributes<table=false, tableCellArg=false>
    space_or_newline_or_solidus* // No need to preserve this -- canonicalize on RT via dirty diff
    selfclose:"/"?
    space* // not preserved - canonicalized on RT via dirty diff
    ">"
    {
        var lcName = name.toLowerCase();

        // Extension tags don't necessarily have the same semantics as html tags,
        // so don't treat them as void elements.
        var isVoidElt = HTMLTags.Void.includes(lcName.toUpperCase()) && !extTag;

        // Support </br>
        if (lcName === 'br' && end) {
            end = null;
        }

        var tsr = tsrOffsets();
        tsr[0]--; // For "<" matched at the start of xmlish_tag rule
        var res = tu.buildXMLTag(name, lcName, attribs, end, !!selfclose || isVoidElt, tsr);

        // change up data-attribs in one scenario
        // void-elts that aren't self-closed ==> useful for accurate RT-ing
        if (!selfclose && isVoidElt) {
            res.dataAttribs.selfClose = undefined;
            res.dataAttribs.noClose = true;
        }

        var met = maybeExtensionTag(res);
        return Array.isArray(met) ? met : [met];
    }

/*
 * A variant of xmlish_tag, but also checks if the tag name is a block-level
 * tag as defined in
 * http://www.w3.org/TR/html5/syntax.html#tag-open-state and
 * following paragraphs.
 */
block_tag
  = "<" tag:(xmlish_tag_opened<isBlock, extTag> / xmlish_tag_opened<isBlock, extTag=false>)
    { return tag; }

// A generic attribute that can span multiple lines.
generic_newline_attribute
  = space_or_newline_or_solidus*
    namePos0:("" { return endOffset(); })
    name:generic_attribute_name
    namePos:("" { return endOffset(); })
    vd:(space_or_newline* "=" v:generic_att_value? { return v; })?
{
    // NB: Keep in sync w/ table_attibute
    var res;
    // Encapsulate protected attributes.
    if (typeof name === 'string') {
        name = tu.protectAttrs(name);
    }
    if (vd !== null) {
        res = new KV(name, vd.value, [namePos0, namePos, vd.srcOffsets[0], vd.srcOffsets[1]]);
        res.vsrc = input.substring(vd.srcOffsets[0], vd.srcOffsets[1]);
    } else {
        res = new KV(name, '', [namePos0, namePos, namePos, namePos]);
    }
    if (Array.isArray(name)) {
        res.ksrc = input.substring(namePos0, namePos);
    }
    return res;
}

// A single-line attribute.
table_attribute
  = s:optionalSpaceToken
    namePos0:("" { return endOffset(); })
    name:table_attribute_name
    namePos:("" { return endOffset(); })
    vd:(optionalSpaceToken "=" v:table_att_value? { return v; })?
{
    // NB: Keep in sync w/ generic_newline_attribute
    var res;
    // Encapsulate protected attributes.
    if (typeof name === 'string') {
        name = tu.protectAttrs(name);
    }
    if (vd !== null) {
        res = new KV(name, vd.value, [namePos0, namePos, vd.srcOffsets[0], vd.srcOffsets[1]]);
        res.vsrc = input.substring(vd.srcOffsets[0], vd.srcOffsets[1]);
    } else {
        res = new KV(name, '', [namePos0, namePos, namePos, namePos]);
    }
    if (Array.isArray(name)) {
        res.ksrc = input.substring(namePos0, namePos);
    }
    return res;
}

// The php parser's Sanitizer::removeHTMLtags explodes on < so that it can't
// be found anywhere in xmlish tags.  This is a divergence from html5 tokenizing
// which happily permits it in attribute positions.  Extension tags being the
// exception, since they're stripped beforehand.
less_than =
  $(
    &<extTag>
    "<"
  )

// The arrangement of chars is to emphasize the split between what's disallowed
// by html5 and what's necessary to give directive a chance.
// See: http://www.w3.org/TR/html5/syntax.html#attributes-0
generic_attribute_name
  = q:$(["'=]?)  // From #before-attribute-name-state, < is omitted for directive
    r:( $[^ \t\r\n\0/=><&{}\-!|]+
        / !inline_breaks
          // \0/=> is the html5 attribute name set we do not want.
          t:( directive / less_than / $( !( space_or_newline / [\0/=><] ) . )
        ) { return t; }
    )*
    & { return r.length > 0 || q.length > 0; }
  { return tu.flattenString([q].concat(r)); }

// Also accept these chars in a wikitext table or tr attribute name position.
// They are normally not matched by the table_attribute_name.
broken_table_attribute_name_char = c:[\0/=>] { return new KV(c, ''); }

// Same as generic_attribute_name, except for accepting tags and wikilinks.
// (That doesn't make sense (ie. match php) in the generic case.)
// We also give a chance to break on \[ (see T2553).
table_attribute_name
  = q:$(["'=]?)  // From #before-attribute-name-state, < is omitted for directive
    r:( $[^ \t\r\n\0/=><&{}\-!|\[]+
        / !inline_breaks
          // \0/=> is the html5 attribute name set we do not want.
          t:(   $wikilink
              / directive
              // Accept insane tags-inside-attributes as attribute names.
              // The sanitizer will strip and shadow them for roundtripping.
              // Example: <hiddentext>generated with.. </hiddentext>
              / &xmlish_tag ill:inlineline { return ill; }
              / $( !( space_or_newline / [\0/=>] ) . )
        ) { return t; }
    )*
    & { return r.length > 0 || q.length > 0; }
  { return tu.flattenString([q].concat(r)); }

// Attribute value, quoted variants can span multiple lines.
// Missing end quote: accept /> look-ahead as heuristic.
// These need to be kept in sync with the attribute_preprocessor_text_*
generic_att_value
  = s:$(space_or_newline* "'") t:attribute_preprocessor_text_single? q:$("'" / &('/'? '>')) {
      return tu.getAttrVal(t, startOffset() + s.length, endOffset() - q.length);
    }
  / s:$(space_or_newline* '"') t:attribute_preprocessor_text_double? q:$('"' / &('/'? '>')) {
      return tu.getAttrVal(t, startOffset() + s.length, endOffset() - q.length);
    }
  / s:$space_or_newline* t:attribute_preprocessor_text &(space_or_newline / eof / '/'? '>') {
      return tu.getAttrVal(t, startOffset() + s.length, endOffset());
    }

// Attribute value, restricted to a single line.
// Missing end quote: accept |, !!, \r, and \n look-ahead as heuristic.
// These need to be kept in sync with the table_attribute_preprocessor_text_*
table_att_value
  = s:$(space* "'") t:table_attribute_preprocessor_text_single? q:$("'" / &('!!' / [|\r\n])) {
      return tu.getAttrVal(t, startOffset() + s.length, endOffset() - q.length);
    }
  / s:$(space* '"') t:table_attribute_preprocessor_text_double? q:$('"' / &('!!' / [|\r\n])) {
      return tu.getAttrVal(t, startOffset() + s.length, endOffset() - q.length);
    }
  / s:$space* t:table_attribute_preprocessor_text &(space_or_newline/ eof / '!!' / '|') {
      return tu.getAttrVal(t, startOffset() + s.length, endOffset());
    }

/*********************************************************
 *   Lists
 *********************************************************/
list_item = dtdd / hacky_dl_uses / li

li
  = bullets:list_char+
     c:inlineline?
     // The inline_break is to check if we've hit a template end delimiter.
     &(eolf / inline_breaks)
  {
    // Leave bullets as an array -- list handler expects this
    var tsr = tsrOffsets('start');
    tsr[1] += bullets.length;
    var li = new TagTk('listItem', [new KV('bullets', bullets)], { tsr: tsr });
    return [ li ].concat(c || []);
  }

/*
 * This rule is required to support wikitext of this form
 *   ::{|border="1"|foo|bar|baz|}
 * where the leading colons are used to indent the entire table.
 * This hack was added back in 2006 in commit
 * a0746946312b0f1eda30a2c793f5f7052e8e5f3a based on a patch by Carl
 * Fürstenberg.
 */
hacky_dl_uses
  = bullets:":"+
      tbl:(table_line (sol table_line)*)
      line:inlineline?
      &comment_space_eolf
  {
      // Leave bullets as an array -- list handler expects this
      var tsr = tsrOffsets('start');
      tsr[1] += bullets.length;
      var li = new TagTk('listItem', [new KV('bullets', bullets)], { tsr: tsr });
      return tu.flattenIfArray([li, tbl || [], line || []]);
  }

dtdd
  = bullets:(!(";" !list_char) lc:list_char { return lc; })*
    ";"
    c:inlineline_break_on_colon?
    cpos:(":" { return endOffset(); })
    d:inlineline?
    &eolf {
        // Leave bullets as an array -- list handler expects this
        // TSR: +1 for the leading ";"
        const numBullets = bullets.length + 1;
        const tsr = tsrOffsets('start');
        tsr[1] += numBullets;
        const li1Bullets = bullets.slice();
        li1Bullets.push(";");
        const li1 = new TagTk('listItem', [new KV('bullets', li1Bullets)], { tsr: tsr });
        // TSR: -1 for the intermediate ":"
        const li2Bullets = bullets.slice();
        li2Bullets.push(":");
        const li2 = new TagTk('listItem', [new KV('bullets', li2Bullets)], { tsr: [cpos - 1, cpos], stx: 'row' });

        return [ li1 ].concat(c || [], [ li2 ], d || []);
    }

list_char = [*#:;]

inlineline_break_on_colon
  = ill:inlineline<colon>
    { return ill; }
