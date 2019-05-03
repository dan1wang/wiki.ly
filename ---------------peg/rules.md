# PEG rules

* autolink
```
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
    / isbn
  ) {
    return r;
  }
```

* autourl
```
autourl
  = ! '//' // protocol-relative autolinks not allowed (T32269)
    r:(
    proto:url_protocol
    addr:(IPAddress / "")
    path:(
        ( !inline_breaks
          c:no_punctuation_char { return c; }
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
      var strip = ',;\\\\\.:!\?'; //,;\.:!?
      if (path.indexOf("(") === -1) {
        strip += '\\)';
      }
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
```

* inlineline
```
  = c:(urltext
          / !inline_breaks
            r:(inline_element / [^\r\n]) { return r; })+ {
      return tu.flattenStringlist(c);
  }
```

* urltext:
```
  (
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
```
