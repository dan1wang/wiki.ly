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
        addr:(
          literal:(url_protocol (IPAddress/"") extlink_preprocessor_text<extlink>) /
          parameterized:(
            p:extlink_preprocessor_text<extlink> / ""
            & {
              var flat = tu.flattenString(p);
              // There are templates present
              return ((Array.isArray(flat)) && (flat.length > 0));
            }
          )
        )
        sp:$( space / unispace )*
        targetOff:( "" { return endOffset(); })
        content:inlineline<extlink>?
        "]" {
            return [
                new SelfclosingTagTk('extlink', [
                    new KV('href', tu.flattenString(addr)),
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
url_protocol =
   "%PROTOCOLS%"

// no punctuation, and '{<' to trigger directives
no_punctuation_char = [^ :\]\[\r\n"'<>\x00-\x20\x7f,.&%\u00A0\u1680\u180E\u2000-\u200A\u202F\u205F\u3000{]

// this is the general url rule
// on the PHP side, the path part matches EXT_LINK_URL_CLASS
// which is '[^][<>"\\x00-\\x20\\x7F\p{Zs}]'
// the 's' and 'r' pieces below match the characters in
// EXT_LINK_URL_CLASS which aren't included in no_punctuation_char
url "url"
  = proto:url_protocol
    addr:(IPAddress / "")
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
    addr:(IPAddress / "")
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

IPAddress
  = $( "[" [0-9A-Fa-f:.]+ "]" )
