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
