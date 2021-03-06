/**************************************************************
 * External (bracketed and autolinked) links
 **************************************************************/

autolink
  = ! <extlink>
    // this must be a word boundary, so previous character must be non-word
    ! { return /\w/.test(input[endOffset() - 1] || ''); }
  r:(
      // urllink, inlined
      autourl
    / autoref
    / isbn)

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
                    tsr: tsrOffsets(),
                    extLinkContentOffsets: [targetOff, endOffset() - 1],
                }),
            ];
        }
    )

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
      (space_or_nbsp_or_dash? [0-9])+
      space_or_nbsp_or_dash? [xX]?
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

// this is the general url rule on the PHP side
url "url"
  = proto:url_protocol
    addr:(IPAddress / "")
    path:(
            // c = !unispace [^&[\]{<>"\x00-\x20\x7F\uFFFD]
            //   = PHP's EXT_LINK_URL_CLASS, further excluding "&[]{"
            // s = ":" or "{"
            // r = HTML entity or "&"
            ( !inline_breaks
              c:[^&[\]{"<>\x00-\x20\x7F\uFFFD \u00A0\u1680\u2000-\u200A\u202F\u205F\u3000]
            )
            / comment
            / tplarg_or_template
            / s:[:{] { return s; }
            / ! ( "&lt;"i / "&gt;"i )
                r:(& "&" htmlentity / "&")
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
autourl
  = ! '//' // protocol-relative autolinks not allowed (T32269)
    r:(
    proto:url_protocol
    addr:(IPAddress / "")
    path:(
            // c = !unispace [^&[\]{<>"\x00-\x20\x7F\uFFFD]
            //   = PHP's EXT_LINK_URL_CLASS, further excluding "&[]{" and "'"
            // s = ":" or "{"
            // r = HTML entity or "&"
            ( !inline_breaks
              c:[^&[\]{'"<>\x00-\x20\x7F\uFFFD \u00A0\u1680\u2000-\u200A\u202F\u205F\u3000]
            )
            / $("'" !"'") // single quotes are ok, double quotes are bad
            / comment
            / tplarg_or_template
            / s:$([:{])
            / ! ( rhe:raw_htmlentity &{ return /^[<>\u00A0]$/.test(rhe); } )
                r:( & "&" htmlentity / "&")
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
} ) &{ return r !== null; }
{
  return [new SelfclosingTagTk('urllink', [new KV('href', r)], { tsr: tsrOffsets() })];
}

IPAddress
  = $( "[" [0-9A-Fa-f:.]+ "]" )
