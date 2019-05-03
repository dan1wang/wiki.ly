heading = & "="
  r:(
   s:$'='+
   ce:(
     // (ill:inlineline<h>? { return ill || []; })
     .*
     $'='+
   )?
   & { return ce || s.length > 2; }
   endTPos:("" { return peg$currPos })
   spc:(spaces / comment)*
   &eolf
  ) {
    return r
  }

//inline_breaks = & [=|!{}:;\r\n[\]\-]
spaces = $[ \t]+
comment = '<!--' c:$(!"-->" .)* ('-->' / eof)
eolf = newline / eof
newline = '\n' / '\r\n'
eof = & { return peg$currPos === input.length; } { return 'EOF' }

urltext = (
       & [/A-Za-z] al:autolink { return al; }
     / & "&" he:htmlentity { return he; }
     // Convert trailing space into &nbsp;
     // XXX: This should be moved to a serializer
     // This is a hack to force a whitespace display before the colon
     / ' ' & ':' {
         var toks = TokenUtils.placeholder('\u00a0', {
           src: ' ',
           tsr: tsrOffsets('start'),
           isDisplayHack: true,
         }, { tsr: tsrOffsets('end'), isDisplayHack: true });
         var typeOf = toks[0].getAttribute('typeof');
         toks[0].setAttribute('typeof', 'mw:DisplaySpace ' + typeOf);
         return toks;
     }
     / & ('__') bs:behavior_switch { return bs; }
     // About 96% of text_char calls originate here, so inline it for efficiency
     /  [^-'<~[{\n\r:;\]}|!=]
   )+

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

inline_breaks = & [=|!{}:;\r\n[\]\-]
eolf = newline / eof
newline = '\n' / '\r\n'
eof = & { return peg$currPos === input.length; } { return 'EOF' }
