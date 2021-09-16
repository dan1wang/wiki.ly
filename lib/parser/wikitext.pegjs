
/*******************************************************************
 * Text variants and other general rules
 *******************************************************************/

/* All chars that cannot start syntactic structures in the middle of a line
 * XXX: ] and other end delimiters should probably only be activated inside
 * structures to avoid unnecessarily leaving the text rule on plain
 * content.
 *
 * TODO: Much of this is should really be context-dependent (syntactic
 * flags). The wikilink_preprocessor_text rule is an example where
 * text_char is not quite right and had to be augmented. Try to minimize /
 * clarify this carefully!
 */

// text_char = [^-'<~[{\n\r:;\]}|!=]

/* Legend
 * '    quotes (italic/bold)
 * <    start of xmlish_tag
 * ~    signatures/dates
 * [    start of links
 * {    start of parser functions, transclusion and template args
 * \n   all sort of block-level markup at start of line
 * \r   ditto
 * A-Za-z autolinks (http(s), nttp(s), mailto, ISBN, PMID, RFC)
 *
 * _    behavior switches (e.g., '__NOTOC__') (XXX: not URL related)
 * ! and | table cell delimiters, might be better to specialize those
 * =    headings - also specialize those!
 *
 * The following chars are also included for now, but only apply in some
 * contexts and should probably be enabled only in those:
 * :    separate definition in ; term : definition
 * ]    end of link
 * }    end of parser func/transclusion/template arg
 * -    start of lang_variant -{ ... }-
 * ;    separator in lang_variant
 */

urltext =
   (
      & [A-Za-z] autolink
    / & "&" htmlentity
    / & ('__') behavior_switch
    / [^-'<~[{\n\r:;\]}|!=]
  )+

raw_htmlentity = encoded:$("&" [#0-9a-zA-Z]+ ";") { return decodeEntity(encoded) }

htmlentity = cc:raw_htmlentity {
    // if this is an invalid entity, don't tag it with 'mw:Entity'
    if (cc.length > 2 /* decoded entity would be 1 or 2 UTF-16 characters */) {
        return cc;
    }
    return [
        // If this changes, the nowiki extension's toDOM will need to follow suit
        new TagTk('span', [new KV('typeof', 'mw:Entity')], { src: text(), srcContent: cc, tsr: tsrOffsets('start') }),
        cc,
        new EndTagTk('span', [], { tsr: tsrOffsets('end') }),
    ];
}

spaces
  = $[ \t]+

optional_spaces
  = $[ \t]*

space = [ \t]

optionalSpaceToken
  = s:optional_spaces {
      if (s.length) {
          return [s];
      } else {
          return [];
      }
  }

/* This rule corresponds to \s in the PHP preg_* functions,
 * which is used frequently in the PHP parser.  The inclusion of
 * form feed (but not other whitespace, like vertical tab) is a quirk
 * of Perl, which PHP inherited via the PCRE (Perl-Compatible Regular
 * Expressions) library.
 */
space_or_newline
  = [ \t\n\r\x0c]

/* This rule corresponds to \b in the PHP preg_* functions,
 * after a word character.  That is, it's a zero-width lookahead that
 * the next character is not a word character.
 */
end_of_word
  = eof / ![A-Za-z0-9_]

// Unicode "separator, space" category.  It covers the \u0020 space as well
// as \u3000 IDEOGRAPHIC SPACE (see bug 19052).  In PHP this is \p{Zs}.
// Keep this up-to-date with the characters tagged ;Zs; in
// http://www.unicode.org/Public/UNIDATA/UnicodeData.txt
unispace = [ \u00A0\u1680\u2000-\u200A\u202F\u205F\u3000]

// Non-newline whitespace, including non-breaking spaces.  Used for magic links.
space_or_nbsp
  = space // includes \t
  / unispace
  / he:htmlentity &{ return Array.isArray(he) && /^\u00A0$/.test(he[1]); }

// Used within ISBN magic links
space_or_nbsp_or_dash
  = space_or_nbsp / "-"

// Extra newlines followed by at least another newline. Usually used to
// compress surplus newlines into a meta tag, so that they don't trigger
// paragraphs.
optionalNewlines
  = spc:$([\n\r\t ] &[\n\r])* {
        if (spc.length) {
            return [spc];
        } else {
            return [];
        }
    }

comment_or_includes = (comment / include_limits<sol_il>)*

sol = (empty_line_with_comments / sol_prefix) comment_or_includes

sol_prefix
  = newlineToken
  / & {
      // Use the sol flag only at the start of the input
      // Flag should always be an actual boolean (not falsy or undefined)
      assert(typeof options.sol === 'boolean');
      return endOffset() === 0 && options.sol;
  } { return []; }

empty_line_with_comments
  = sp:sol_prefix p:("" { return endOffset(); }) c:(space* comment (space / comment)* newline)+ {
        return [
            sp,
            new SelfclosingTagTk("meta", [new KV('typeof', 'mw:EmptyLine')], {
                tokens: tu.flattenIfArray(c),
                tsr: [p, endOffset()],
            }),
        ];
    }

comment_space = comment / space

nl_comment_space = newlineToken / comment_space

/**
 * noinclude / includeonly / onlyinclude rules. These are normally
 * handled by the xmlish_tag rule, except where generic tags are not
 * allowed- for example in directives, which are allowed in various attribute
 * names and -values.
 *
 * Example test case:
 * {|
 * |-<includeonly>
 * foo
 * </includeonly>
 * |Hello
 * |}
 */

include_limits =
  & ("<" "/"? n:$[oyinclude]i+ & { return tu.isIncludeTag(n.toLowerCase()); })
  il:xmlish_tag
  sol_il: <sol_il>
  & {
    il = il[0];
    var lname = il.name.toLowerCase();
    if (!tu.isIncludeTag(lname)) { return false; }
    // Preserve SOL where necessary (for onlyinclude and noinclude)
    // Note that this only works because we encounter <*include*> tags in
    // the toplevel content and we rely on the php preprocessor to expand
    // templates, so we shouldn't ever be tokenizing inInclude.
    // Last line should be empty (except for comments)
    if (lname !== "includeonly" && sol_il && il.constructor === TagTk) {
        var dp = il.dataAttribs;
		var inclContent = dp.src.substring(dp.extTagOffsets[1] - dp.extTagOffsets[0], dp.extTagOffsets[2] - dp.extTagOffsets[0]);
        var last = lastItem(inclContent.split('\n'));
        if (!/^(<!--([^-]|-(?!->))*-->)*$/.test(last)) {
            return false;
        }
    }
    return true;
  }
  { return il; }

// Start of file
sof = & { return endOffset() === 0 && !options.pipelineOffset; }

// End of file
eof = & { return endOffset() === input.length; }

newline = '\n' / '\r\n'

newlineToken = newline { return [new NlTk(tsrOffsets())]; }

eolf = newline / eof

comment_space_eolf = (space+ / comment)* eolf

// 'Preprocessor' directive- higher-level things that can occur in otherwise
// plain-text content.
directive
  = comment
  / extension_tag
  / tplarg_or_template
  / & "-{" v:lang_variant_or_tpl
  / & "&" e:htmlentity
  / include_limits

wikilink_preprocessor_text
  = r:( t:$[^<[{\n\r\t|!\]} &\-]+
        // XXX gwicke: any more chars we need to allow here?
        / !inline_breaks
          wr:(
              directive
            / $( !"]]" [^'~[{:;|=] )
          )
    )+ {
      return tu.flattenStringlist(r);
  }

extlink_preprocessor_text
  // added special separator character class inline: separates url from
  // description / text
  =
    // Prevent breaking on pipes when we're in a link description.
    // See the test, 'Images with the "|" character in the comment'.
    extlink_preprocessor_text_parameterized<linkdesc=false>

extlink_preprocessor_text_parameterized
  = r:(
      $[^{|!=&[\]'"<>\x00-\x20\x7F\uFFFD \u00A0\u1680\u2000-\u200A\u202F\u205F\u3000]+
    / !inline_breaks s:( directive / [{|!=] ) { return s; }
    / $("'" !"'") // single quotes are ok, double quotes are bad
    )+ {
        return tu.flattenString(r);
    }

// Attribute values with preprocessor support

// n.b. / is a permissible char in the three rules below.
// We only break on />, enforced by the negated expression.
// Hence, it isn't included in the stop set.

// The stop set is space_or_newline and > which matches generic_att_value.
attribute_preprocessor_text
  = r:( $[^{}&<\-|/ \t\n\r\x0c>]+
  / !inline_breaks
    !'/>'
    ( directive / less_than / [{}&\-|/] )
  )+ {
    return tu.flattenString(r);
  }

// The stop set is '> which matches generic_att_value.
attribute_preprocessor_text_single
  = r:( $[^{}&<\-|/'>]+
  / !inline_breaks
    !'/>'
    ( directive / less_than / [{}&\-|/] )
  )* {
    return tu.flattenString(r);
  }

// The stop set is "> which matches generic_att_value.
attribute_preprocessor_text_double
  = r:( $[^{}&<\-|/">]+
  / !inline_breaks
    !'/>'
    ( directive / less_than / [{}&\-|/] )
  )* {
    return tu.flattenString(r);
  }

// Variants with the entire attribute on a single line

// n.b. ! is a permissible char in the three rules below.
// We only break on !! in th, enforced by the inline break.
// Hence, it isn't included in the stop set.
// [ is also permissible but we give a chance to break
// for the [[ special case in php's doTableStuff (See T2553).

// The stop set is space_or_newline and | which matches table_att_value.
table_attribute_preprocessor_text
  = r:( $[^{}&<\-!\[ \t\n\r\x0c|]+
  / !inline_breaks
    ( directive / [{}&<\-!\[] )
  )+ {
    return tu.flattenString(r);
  }

// The stop set is '\r\n| which matches table_att_value.
table_attribute_preprocessor_text_single
  = r:( $[^{}&<\-!\['\r\n|]+
  / !inline_breaks
    ( directive / [{}&<\-!\[] )
  )* {
    return tu.flattenString(r);
  }

// The stop set is "\r\n| which matches table_att_value.
table_attribute_preprocessor_text_double
  = r:( $[^{}&<\-!\["\r\n|]+
  / !inline_breaks
    ( directive / [{}&<\-!\[] )
  )* {
    return tu.flattenString(r);
  }

// Special-case support for those pipe templates
pipe = "|" / "{{!}}"

// SSS FIXME: what about |{{!}} and {{!}}|
pipe_pipe = "||" / "{{!}}{{!}}"
